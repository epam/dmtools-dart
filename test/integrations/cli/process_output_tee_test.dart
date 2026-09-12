import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the capture-plus-tee helper backing live child-output
/// mirroring (`cli_execute_command` / CliAgent process paths).
///
/// The captured-string contract is what JS scripts and tool callers see, so
/// the capture must stay byte-identical to a full-buffer read while every
/// complete output line is mirrored as it arrives — not buffered until exit.
void main() {
  captureTests();
  lineMirrorTests();
  liveStreamTests();
  runCapturedTests();
  resilienceTests();
}

/// Capture fidelity: the returned string is byte-identical to a full-buffer
/// read, including utf8 sequences split across chunk boundaries.
void captureTests() {
  group('captureAndMirror capture', () {
    test('captures raw stream bytes byte-identically', () async {
      final controller = StreamController<List<int>>();
      final done = captureAndMirror(controller.stream);
      controller.add(utf8.encode('first line\n'));
      controller.add(utf8.encode('second line\n'));
      await controller.close();
      expect(await done, 'first line\nsecond line\n');
    });

    test('preserves a missing trailing newline in the capture', () async {
      final controller = StreamController<List<int>>();
      final done = captureAndMirror(controller.stream);
      controller.add(utf8.encode('no newline at end'));
      await controller.close();
      expect(await done, 'no newline at end');
    });

    test('decodes utf8 sequences split across chunk boundaries', () async {
      final controller = StreamController<List<int>>();
      final done = captureAndMirror(controller.stream);
      final eBytes = utf8.encode('é');
      controller.add(utf8.encode('h'));
      controller.add([eBytes[0]]);
      controller.add([...eBytes.sublist(1), ...utf8.encode('llo\nwörld\n')]);
      await controller.close();
      expect(await done, 'héllo\nwörld\n');
    });

    test('captures an empty stream', () async {
      final controller = StreamController<List<int>>();
      final done = captureAndMirror(controller.stream);
      await controller.close();
      expect(await done, '');
    });

    test('decodes malformed utf8 leniently as U+FFFD, not a throw', () async {
      // 0xFF is never valid UTF-8: the lenient decoder substitutes U+FFFD
      // where Process.run's default (strict) decode throws a
      // FormatException. Well-formed bytes around it are untouched.
      final controller = StreamController<List<int>>();
      final done = captureAndMirror(controller.stream);
      controller.add(utf8.encode('ok '));
      controller.add([0xFF]);
      controller.add(utf8.encode(' bad\n'));
      await controller.close();
      expect(await done, 'ok \u{FFFD} bad\n');
    });
  });
}

/// Line mirroring: every complete line is handed to the sink, a partial
/// final line when the stream closes.
void lineMirrorTests() {
  group('captureAndMirror line mirroring', () {
    test('mirrors every complete line, including empty ones', () async {
      final controller = StreamController<List<int>>();
      final mirrored = <String>[];
      final done = captureAndMirror(controller.stream, mirror: mirrored.add);
      controller.add(utf8.encode('a\n\nb\n'));
      await controller.close();
      await done;
      expect(mirrored, ['a', '', 'b']);
    });

    test('mirrors a partial final line when the stream closes', () async {
      final controller = StreamController<List<int>>();
      final mirrored = <String>[];
      final done = captureAndMirror(controller.stream, mirror: mirrored.add);
      controller.add(utf8.encode('whole\npart'));
      await controller.close();
      await done;
      expect(mirrored, ['whole', 'part']);
    });

    test('mirrors lines from many chunks without an empty-stream case',
        () async {
      final controller = StreamController<List<int>>();
      final mirrored = <String>[];
      final done = captureAndMirror(controller.stream, mirror: mirrored.add);
      controller.add(utf8.encode('one\ntwo\n'));
      controller.add(utf8.encode('three\nfour\n'));
      await controller.close();
      await done;
      expect(mirrored, ['one', 'two', 'three', 'four']);
    });
  });
}

/// Live-streaming proof: lines reach the sink while the producer is still
/// running — not buffered until exit.
void liveStreamTests() {
  group('captureAndMirror live streaming', () {
    test('mirrors lines live while the process is still running', () async {
      // exec makes the shell *become* the sleep, so the kill below closes
      // the stdout pipe immediately instead of orphaning a sleep child.
      final proc =
          await Process.start('/bin/sh', ['-c', 'echo early; exec sleep 30']);
      final mirrored = <String>[];
      final captured = captureAndMirror(proc.stdout, mirror: mirrored.add);
      try {
        final sawEarly = await _waitUntil(
          () => mirrored.contains('early'),
          timeout: const Duration(seconds: 10),
        );
        // The line was mirrored while the producer is still sleeping —
        // proof of live streaming, not buffered-until-exit mirroring.
        expect(sawEarly, isTrue, reason: 'early line never mirrored');
        expect(mirrored, isNot(contains('late')),
            reason: 'process should still be running');
      } finally {
        proc.kill();
        await captured;
      }
    });
  });
}

/// [runCaptured]: process-level capture + mirroring with separate streams.
void runCapturedTests() {
  group('runCaptured', () {
    test('captures stdout and stderr separately', () async {
      final result = await runCaptured(
          '/bin/sh',
          [
            '-c',
            'echo to_stdout; echo to_stderr 1>&2',
          ],
          mirror: (_) {});
      expect(result.stdout, 'to_stdout\n');
      expect(result.stderr, 'to_stderr\n');
      expect(result.exitCode, 0);
    });

    test('propagates a non-zero exit code', () async {
      final result =
          await runCaptured('/bin/sh', ['-c', 'exit 7'], mirror: (_) {});
      expect(result.exitCode, 7);
    });

    test('mirrors stdout and stderr lines to the same sink', () async {
      final mirrored = <String>[];
      await runCaptured(
          '/bin/sh',
          [
            '-c',
            'echo one; echo two; echo err 1>&2',
          ],
          mirror: mirrored.add);
      expect(mirrored, containsAll(['one', 'two', 'err']));
      expect(mirrored.length, 3);
    });

    test('applies workingDirectory and environment', () async {
      final tmp = await Directory.systemTemp.createTemp('dmtools_tee_');
      try {
        final result = await runCaptured('/bin/sh', ['-c', 'pwd; echo \$PROBE'],
            workingDirectory: tmp.path,
            environment: {'PROBE': 'probe-value'},
            mirror: (_) {});
        expect(result.stdout, contains(tmp.path));
        expect(result.stdout, contains('probe-value'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('drains large output without deadlocking', () async {
      final result = await runCaptured(
          '/bin/sh',
          [
            '-c',
            'i=0; while [ \$i -lt 5000 ]; do echo line-\$i; i=\$((i+1)); done'
          ],
          mirror: (_) {});
      expect(result.stdout.split('\n').length, greaterThan(4999));
    });
  });
}

/// Resilience: the mirror is a side-channel (humans/CI logs), so a sink
/// that throws must never break the capture or the process run — the
/// captured strings stay byte-identical to a non-throwing run.
void resilienceTests() {
  group('captureAndMirror best-effort mirror', () {
    test('completes the capture when the mirror throws', () async {
      final controller = StreamController<List<int>>();
      final done = captureAndMirror(controller.stream, mirror: _throwingSink);
      controller.add(utf8.encode('line one\n'));
      controller.add(utf8.encode('line two\n'));
      await controller.close();
      expect(await done, 'line one\nline two\n');
    });

    test('still mirrors the lines before the sink starts throwing', () async {
      final controller = StreamController<List<int>>();
      final seen = <String>[];
      final done = captureAndMirror(
        controller.stream,
        mirror: (line) {
          seen.add(line);
          if (line == 'boom') throw StateError('stderr closed');
        },
      );
      controller.add(utf8.encode('boom\nafter\n'));
      await controller.close();
      await done;
      expect(seen, contains('boom'));
    });
  });

  group('runCaptured best-effort mirror', () {
    test('returns the captured result when the mirror throws', () async {
      final result = await runCaptured(
        '/bin/sh',
        ['-c', 'echo out; echo err 1>&2; exit 5'],
        mirror: _throwingSink,
      );
      expect(result.stdout, 'out\n');
      expect(result.stderr, 'err\n');
      expect(result.exitCode, 5);
    });
  });
}

/// A mirror sink that always fails (closed fd 2, detached process, ...).
void _throwingSink(String line) {
  throw StateError('stderr pipe closed');
}

/// Polls [condition] until it holds or [timeout] elapses.
Future<bool> _waitUntil(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return condition();
}
