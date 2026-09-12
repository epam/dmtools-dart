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
/// `CliExecutionHelper`). The synchronous JS-bridge path cannot mirror: FFI
/// host functions are synchronous and `dart:io` has no synchronous
/// streaming API, so its capture stays buffered by contract.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sink for one mirrored output line.
typedef OutputLineSink = void Function(String line);

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
  final stdout = captureAndMirror(process.stdout, mirror: mirror);
  final stderr = captureAndMirror(process.stderr, mirror: mirror);
  final exitCode = await process.exitCode;
  return CapturedProcessResult(
    stdout: await stdout,
    stderr: await stderr,
    exitCode: exitCode,
  );
}

/// Drains [stream], returning its decoded text and mirroring every complete
/// line through [mirror] as it arrives (a partial final line is mirrored
/// when the stream closes).
///
/// The capture decodes with the same lenient UTF-8 fallback `Process.run`
/// uses, so the returned string is byte-identical to a full-buffer read —
/// even for multi-byte sequences split across chunk boundaries.
Future<String> captureAndMirror(
  Stream<List<int>> stream, {
  OutputLineSink? mirror,
}) async {
  final sink = _CaptureSink(mirror ?? mirrorLineToStderr);
  await stream.forEach(sink.add);
  sink.close();
  return sink.captured.toString();
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
  void add(String line) => _mirror(line);

  @override
  void close() {}
}
