/// Capture-plus-tee helper for child process output.
///
/// The `cli_execute_command` contract captures the child's combined output
/// and returns it as a string — that stays byte-identical. What this adds is
/// the live half: every output line is mirrored to dmtools' own stderr as it
/// arrives (line-buffered, not buffered until exit), so humans — and CI step
/// logs — can watch long-running commands (inner agents) work, the way
/// copilot's CLI behaves in GitHub Actions.
///
/// Used by the process-execution paths behind the CLI tool surface
/// ([runCaptured]) and the CliAgent command phases (see
/// `CliExecutionHelper`). Mirroring is best-effort ([safeMirrorLine]): a
/// failing sink never breaks the capture. The synchronous JS-bridge path
/// cannot mirror: FFI host functions are synchronous and `dart:io` has no
/// synchronous streaming API, so its capture stays buffered by contract.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sink for one mirrored output line.
typedef OutputLineSink = void Function(String line);

/// Invokes [mirror] best-effort for one output [line].
///
/// Mirroring is an observability side-channel (humans and CI step logs),
/// never a correctness surface: a failing sink — closed fd 2, detached
/// process — must not abort the capture or the command batch. Exceptions
/// from [mirror] are swallowed; the capture is unaffected.
void safeMirrorLine(OutputLineSink mirror, String line) {
  try {
    mirror(line);
  } catch (_) {
    // Side-channel only: a broken mirror must never break the capture.
  }
}

/// Captured output of a finished child process (the fields mirror the
/// `ProcessResult` shape the tool executors expose).
class CapturedProcessResult {
  /// Creates a result.
  const CapturedProcessResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  /// Captured stdout, byte-identical to a full-buffer read.
  final String stdout;

  /// Captured stderr, byte-identical to a full-buffer read.
  final String stderr;

  /// The child's exit code.
  final int exitCode;
}

/// Starts [executable] with [arguments] and drains its output streams,
/// mirroring every complete stdout/stderr line through [mirror] as it
/// arrives while capturing both streams verbatim.
///
/// Returns after the process has exited and both streams are fully drained
/// (no deadlock on large outputs). [mirror] defaults to dmtools' own stderr;
/// tests inject a collector.
///
/// Decoding contract: both streams are decoded as UTF-8, tolerating
/// malformed byte sequences (`allowMalformed: true` — bad bytes become
/// U+FFFD). The capture is UTF-8-only by design and deliberately differs
/// from `Process.run`, whose `stdoutEncoding`/`stderrEncoding` default to
/// `systemEncoding` — the platform codepage (UTF-8 on Linux/macOS, but
/// typically the OEM/ANSI codepage on Windows consoles) — and whose default
/// decode is strict (a malformed sequence throws [FormatException] instead
/// of substituting U+FFFD). For well-formed UTF-8 output the returned
/// strings are byte-identical to a full-buffer read, including multi-byte
/// sequences split across chunk boundaries.
Future<CapturedProcessResult> runCaptured(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  OutputLineSink? mirror,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
  );
  return drainCaptured(
    process.stdout,
    process.stderr,
    process.exitCode,
    mirror: mirror,
  );
}

/// Drains [stream], returning its decoded text and mirroring every complete
/// line through [mirror] as it arrives (a partial final line is mirrored
/// when the stream closes).
///
/// The capture decodes as UTF-8, tolerating malformed byte sequences
/// (`allowMalformed: true`): bad bytes are replaced with U+FFFD where a
/// strict decode — what `Process.run`'s default UTF-8/systemEncoding does —
/// would throw a [FormatException]. For well-formed UTF-8 output the
/// returned string is byte-identical to a full-buffer read, including
/// multi-byte sequences split across chunk boundaries.
Future<String> captureAndMirror(
  Stream<List<int>> stream, {
  OutputLineSink? mirror,
}) async {
  final sink = _CaptureSink(mirror ?? mirrorLineToStderr);
  try {
    await stream.forEach(sink.add);
  } finally {
    // Flush even when the stream completes with an error: the chunked
    // UTF-8 decoder and the line splitter must emit the buffered tail
    // (a partial multi-byte sequence and the partial final line) instead
    // of silently dropping it from the mirror.
    sink.close();
  }
  return sink.captured.toString();
}

/// Drains the output streams of an already-started child process into a
/// [CapturedProcessResult], mirroring every complete line through [mirror]
/// as it arrives.
///
/// Both capture futures and [exitCode] are awaited together through
/// [Future.wait], so every capture future has its error listener attached
/// the moment it is created: a byte stream that completes with an error
/// mid-capture (e.g. an OS read error on the child pipe) makes the
/// returned future throw deterministically instead of surfacing as an
/// unhandled zone error while the orchestrator is still awaiting
/// [exitCode] — and the second stream's flush is never left without an
/// awaiter because the first await threw.
Future<CapturedProcessResult> drainCaptured(
  Stream<List<int>> stdoutStream,
  Stream<List<int>> stderrStream,
  Future<int> exitCode, {
  OutputLineSink? mirror,
}) async {
  final stdout = captureAndMirror(stdoutStream, mirror: mirror);
  final stderr = captureAndMirror(stderrStream, mirror: mirror);
  final results = await Future.wait<Object>([stdout, stderr, exitCode]);
  return CapturedProcessResult(
    stdout: results[0] as String,
    stderr: results[1] as String,
    exitCode: results[2] as int,
  );
}

/// Production mirror target: dmtools' own stderr. Stdout stays untouched —
/// it is the machine-readable surface (JS console bridge, tool results).
void mirrorLineToStderr(String line) {
  stderr.writeln(line);
}

/// Byte sink wired as: bytes → UTF-8 decode → capture + line-split → mirror.
///
/// One shared decoder feeds both consumers so multi-byte sequences split
/// across chunks decode identically in the capture and the mirrored lines.
class _CaptureSink implements Sink<List<int>> {
  _CaptureSink(this._mirror);

  final OutputLineSink _mirror;
  final StringBuffer captured = StringBuffer();
  late final Sink<String> _splitter =
      const LineSplitter().startChunkedConversion(_LineSink(_mirror));
  late final Sink<List<int>> _decoder =
      const Utf8Decoder(allowMalformed: true).startChunkedConversion(_TeeSink(
    captured,
    _splitter,
  ));

  @override
  void add(List<int> chunk) => _decoder.add(chunk);

  @override
  void close() => _decoder.close();
}

/// String sink that captures the decoded text and forwards it to the
/// line splitter.
class _TeeSink implements Sink<String> {
  _TeeSink(this._captured, this._next);

  final StringBuffer _captured;
  final Sink<String> _next;

  @override
  void add(String data) {
    _captured.write(data);
    _next.add(data);
  }

  @override
  void close() => _next.close();
}

/// String sink mirroring each complete line the splitter emits.
class _LineSink implements Sink<String> {
  _LineSink(this._mirror);

  final OutputLineSink _mirror;

  @override
  void add(String line) => safeMirrorLine(_mirror, line);

  @override
  void close() {}
}
