import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Live stderr mirroring for the CLI command execution paths (gh-50): every
/// child output line is mirrored to the configured sink as it arrives while
/// `commandResponses` stays byte-identical to the buffered capture format —
/// the contract JS actions and tool callers read.
void main() {
  bufferedPathTests();
  monitoredPathTests();
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

/// Line-stop predicate for the monitored-path mirror tests.
bool _stopOnKeepGoing(String line) => line == 'keep-going';
