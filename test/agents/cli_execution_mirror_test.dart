import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Live stderr mirroring for the CLI command execution paths (gh-50): every
/// child output line is mirrored to the configured sink as it arrives while
/// `commandResponses` stays byte-identical to the buffered capture format —
/// the contract JS actions and tool callers read.
void main() {
  bufferedPathTests();
  monitoredPathTests();
  mirrorResilienceTests();
  lenientDecodeTests();
  predicateThrowLeakTests();
  monitoredExitCodeTests();
}

/// Buffered path (`executeCommands`): mirror + exact response formats.
void bufferedPathTests() {
  group('CliExecutionHelper.executeCommands live mirror', () {
    test('mirrors lines while responses stay byte-identical', () async {
      final mirrored = <String>[];
      final r = await const CliExecutionHelper().executeCommands(
        ['echo one', 'echo two'],
        mirror: mirrored.add,
      );
      expect(mirrored, ['one', 'two']);
      expect(
        r.commandResponses,
        'CLI Command: echo one\nResponse:\none\n\n\n'
        'CLI Command: echo two\nResponse:\ntwo\n\n\n',
      );
      expect(r.hasFatalError, isFalse);
    });

    test('keeps the failing-command response format byte-identical', () async {
      final mirrored = <String>[];
      final r = await const CliExecutionHelper().executeCommands(
        ['echo stdout-msg; echo stderr-msg 1>&2; exit 3'],
        mirror: mirrored.add,
      );
      expect(r.hasFatalError, isTrue);
      expect(r.lastExitCode, 3);
      // lastErrorMessage is the captured stderr verbatim, trailing newline
      // included (the no-op `.toString()` cleanup must not change this).
      expect(r.lastErrorMessage, 'stderr-msg\n');
      expect(
        r.commandResponses,
        'CLI Command: echo stdout-msg; echo stderr-msg 1>&2; exit 3\n'
        'Error: stderr-msg\n\n'
        'Output:\nstdout-msg\n\n',
      );
      expect(mirrored, containsAll(['stdout-msg', 'stderr-msg']));
    });

    test('multiple commands mirror in execution order', () async {
      final mirrored = <String>[];
      await const CliExecutionHelper().executeCommands(
        ['echo a1', 'echo a2', 'echo a3'],
        mirror: mirrored.add,
      );
      expect(mirrored, ['a1', 'a2', 'a3']);
    });
  });
}

/// Monitored path (`executeCommandsWithCallbacks`): mirroring coexists with
/// the timer/error/line hooks.
void monitoredPathTests() {
  group('CliExecutionHelper.executeCommandsWithCallbacks live mirror', () {
    test('mirrors lines and keeps hooks working', () async {
      final mirrored = <String>[];
      final seenLines = <String>[];
      final live = LiveCliOutput();
      final r = await const CliExecutionHelper().executeCommandsWithCallbacks(
        ['echo first', 'echo second'],
        callbacks: CliExecutionCallbacks(
          timerIntervalSeconds: 0,
          liveOutput: live,
          lineStopPredicate: (line) {
            seenLines.add(line);
            return false;
          },
        ),
        mirror: mirrored.add,
      );
      expect(mirrored, ['first', 'second']);
      expect(seenLines, ['first', 'second'],
          reason: 'line hook still sees every line');
      expect(live.value, contains('first'));
      expect(r.hasFatalError, isFalse);
    });

    test('mirrors the stopping line before the kill', () async {
      final mirrored = <String>[];
      final r = await const CliExecutionHelper().executeCommandsWithCallbacks(
        ['echo keep-going; sleep 30'],
        callbacks: const CliExecutionCallbacks(
          timerIntervalSeconds: 0,
          lineStopPredicate: _stopOnKeepGoing,
        ),
        mirror: mirrored.add,
      );
      expect(mirrored, ['keep-going']);
      expect(r.commandResponses, contains('Stopped: CLI execution stopped'));
    });
  });
}

/// Mirror resilience (review threads on gh-50): the mirror is a
/// side-channel, so a throwing sink must never abort the batch — the
/// captured response format stays byte-identical.
void mirrorResilienceTests() {
  group('CliExecutionHelper throwing-mirror resilience', () {
    test('buffered batch completes when the mirror throws', () async {
      final r = await const CliExecutionHelper().executeCommands(
        ['echo one', 'echo two'],
        mirror: (line) => throw StateError('stderr pipe closed'),
      );
      expect(r.hasFatalError, isFalse);
      expect(
        r.commandResponses,
        'CLI Command: echo one\nResponse:\none\n\n\n'
        'CLI Command: echo two\nResponse:\ntwo\n\n\n',
        reason: 'capture stays byte-identical to a non-throwing mirror',
      );
    });

    test('monitored batch completes when the mirror throws', () async {
      final seenLines = <String>[];
      final r = await const CliExecutionHelper().executeCommandsWithCallbacks(
        ['echo first', 'echo second'],
        callbacks: CliExecutionCallbacks(
          timerIntervalSeconds: 0,
          lineStopPredicate: (line) {
            seenLines.add(line);
            return false;
          },
        ),
        mirror: (line) => throw StateError('stderr pipe closed'),
      );
      expect(r.hasFatalError, isFalse);
      // The hooks still see every line even though the sink failed.
      expect(seenLines, ['first', 'second']);
      expect(
        r.commandResponses,
        'CLI Command: echo first\nResponse:\nfirst\n\n\n'
        'CLI Command: echo second\nResponse:\nsecond\n\n\n',
      );
    });
  });
}

/// The monitored path must decode like the buffered path
/// (`captureAndMirror`): malformed child UTF-8 becomes U+FFFD instead of
/// throwing a FormatException mid-batch.
void lenientDecodeTests() {
  group('CliExecutionHelper monitored-path lenient decoding', () {
    test('malformed utf-8 child output completes the batch as U+FFFD',
        () async {
      final seenLines = <String>[];
      // \377 is octal for 0xFF — never valid UTF-8. The buffered path
      // (captureAndMirror) already decodes this leniently; the monitored
      // path must behave the same instead of aborting the batch.
      final r = await const CliExecutionHelper().executeCommandsWithCallbacks(
        [r"printf 'bad\377byte\n'; echo done"],
        callbacks: CliExecutionCallbacks(
          timerIntervalSeconds: 0,
          lineStopPredicate: (line) {
            seenLines.add(line);
            return false;
          },
        ),
        mirror: (_) {},
      );
      expect(r.hasFatalError, isFalse);
      expect(seenLines, contains('bad\u{FFFD}byte'),
          reason: 'the line hook sees the leniently-decoded line');
      expect(r.commandResponses, contains('bad\u{FFFD}byte\ndone\n'),
          reason: 'the batch continues past the malformed bytes');
    });
  });
}

/// Line-stop predicate for the monitored-path mirror tests.
bool _stopOnKeepGoing(String line) => line == 'keep-going';

/// A throwing `lineStopPredicate` (a JS `cliOutputLineJSAction` through the
/// bridge) fails the batch — but the child must not outlive it: the process
/// is killed on the error path instead of executing detached.
void predicateThrowLeakTests() {
  group('CliExecutionHelper throwing-lineStopPredicate resilience', () {
    test('a throwing predicate fails the batch and kills the child', () async {
      final marker = '${Directory.systemTemp.path}/gh50_leak_probe_'
          '${DateTime.now().microsecondsSinceEpoch}.txt';
      final file = File(marker);
      // Emits a stdout line (so the predicate is invoked and throws on
      // the first one) and ticks a marker file every 100 ms; if the child
      // survives the failed batch (the pre-fix leak), the file keeps
      // growing.
      final ticker = 'i=0; while [ \$i -lt 100 ]; do i=\$((i+1)); '
          "echo tick; echo tick >> '$marker'; sleep 0.1; done";
      addTearDown(() {
        try {
          file.deleteSync();
        } catch (_) {}
      });
      await expectLater(
        () => const CliExecutionHelper().executeCommandsWithCallbacks(
          [ticker],
          callbacks: CliExecutionCallbacks(
            timerIntervalSeconds: 0,
            lineStopPredicate: _throwingPredicate,
          ),
          mirror: (_) {},
        ),
        throwsStateError,
      );
      // The exception propagated; now prove the child is gone: the marker
      // file must stop growing. A leaked child appends ~6 more ticks in
      // this window; a killed one, none.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final countAfterThrow = _lineCount(file);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(
        _lineCount(file),
        countAfterThrow,
        reason: 'the child process must be killed when the line-stop '
            'predicate throws, not left running detached',
      );
    });
  });
}

/// The success path never kills (stdout EOF means the shell already
/// exited), so exit codes keep their meaning under the kill guard.
void monitoredExitCodeTests() {
  group('CliExecutionHelper monitored exit codes under the kill guard', () {
    test('the success path is untouched: exit codes keep their meaning',
        () async {
      final r = await const CliExecutionHelper().executeCommandsWithCallbacks(
        ['sh -c "exit 0"'],
        callbacks: CliExecutionCallbacks(
          timerIntervalSeconds: 0,
          lineStopPredicate: (line) {
            throw StateError('never called on a silent command');
          },
        ),
        mirror: (_) {},
      );
      expect(r.hasFatalError, isFalse);
      expect(r.lastExitCode, isNull);
      expect(
          r.commandResponses, 'CLI Command: sh -c "exit 0"\nResponse:\n\n\n');
    });

    test('a non-zero exit code survives the kill guard', () async {
      final r = await const CliExecutionHelper().executeCommandsWithCallbacks(
        ['sh -c "echo boom; exit 7"'],
        callbacks: CliExecutionCallbacks(
          timerIntervalSeconds: 0,
          lineStopPredicate: (_) => false,
        ),
        mirror: (_) {},
      );
      expect(r.hasFatalError, isTrue);
      expect(r.lastExitCode, 7);
      expect(r.commandResponses, contains('exit code 7'));
    });
  });
}

/// A hook that always throws — models a JS callback erroring mid-stream.
bool _throwingPredicate(String line) {
  throw StateError('predicate JS action failed');
}

int _lineCount(File file) {
  if (!file.existsSync()) return 0;
  return file.readAsLinesSync().length;
}
