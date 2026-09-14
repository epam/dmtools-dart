import 'dart:io';

import 'package:test/test.dart';

/// Regression tests for gh-59: the agents' commit flow (dmtools-agents
/// submodule, fixed strings we cannot change) stages with
///
///     git add . -- ":!.dmtools/copilot-sessions" ":!.dmtools/copilot-sessions/**"
///
/// git's untracked walk collects ANY ignored path whose string prefix matches
/// a pathspec item — exclude items included (dir.c:exclude_matches_pathspec)
/// — into a fatal "The following paths are ignored" error (exit 1). While
/// `.gitignore` ignores the `.dmtools` directory itself, `.dmtools`
/// prefix-matches both negated pathspecs and every dev run dies at Git
/// Operations.
///
/// The contract under test:
/// 1. the agents' exact staging commands exit 0;
/// 2. nothing under `.dmtools/` is ever staged (no #57-kind regression);
/// 3. ordinary working-tree changes still get staged.
void main() {
  agentsStagingTests();
  blanketAddTests();
}

/// The agents' exact staging commands (dev, rework, timer auto-save) must
/// exit 0 and must never stage anything under `.dmtools/`.
void agentsStagingTests() {
  group('agents commit flow staging commands', () {
    test('dev/rework staging command exits 0 (gh-59)', () {
      final sandbox = _sandbox(withCopilotSessions: true);
      addTearDown(() => sandbox.dir.deleteSync(recursive: true));

      // Mirrors developTicketAndCreatePR.js / pushReworkChanges.js.
      final rm = sandbox.runGit(_rmCopilotSessionsArgs());
      expect(rm.exitCode, 0, reason: rm.stderr);
      final add = _runAgentsAdd(sandbox, '.');
      expect(add.exitCode, 0, reason: add.stderr);
    });

    test('staging command stages changes but nothing under .dmtools/', () {
      final sandbox = _sandbox(withCopilotSessions: true);
      addTearDown(() => sandbox.dir.deleteSync(recursive: true));

      final add = _runAgentsAdd(sandbox, '.');
      expect(add.exitCode, 0, reason: add.stderr);

      final staged = sandbox.stagedPaths();
      expect(staged, contains('notes.md'));
      expect(
        staged.where((p) => p.startsWith('.dmtools/')),
        isEmpty,
        reason: 'session/trace artifacts leaked into the commit (#57)',
      );
    });

    test('timer auto-save variant (git add -A) exits 0 and stages clean', () {
      final sandbox = _sandbox(withCopilotSessions: true);
      addTearDown(() => sandbox.dir.deleteSync(recursive: true));

      final add = _runAgentsAdd(sandbox, '-A');
      expect(add.exitCode, 0, reason: add.stderr);
      expect(
        sandbox.stagedPaths().where((p) => p.startsWith('.dmtools/')),
        isEmpty,
      );
    });
  });
}

/// Plain blanket adds (no pathspec magic) are the #57 regression guard:
/// they must stay silent AND never stage `.dmtools/` artifacts.
void blanketAddTests() {
  group('plain blanket git add .', () {
    for (final withCopilotSessions in [true, false]) {
      test(
          'never stages .dmtools/ (copilot-sessions dir present: '
          '$withCopilotSessions)', () {
        final sandbox = _sandbox(withCopilotSessions: withCopilotSessions);
        addTearDown(() => sandbox.dir.deleteSync(recursive: true));

        final add = sandbox.runGit(['add', '.']);
        expect(add.exitCode, 0, reason: add.stderr);
        expect(
          sandbox.stagedPaths().where((p) => p.startsWith('.dmtools/')),
          isEmpty,
        );
      });
    }
  });
}

/// The negation pathspecs used by developTicketAndCreatePR.js,
/// developBugAndCreatePR.js, pushReworkChanges.js and timerAutoCommitAndSave.js.
ProcessResult _runAgentsAdd(_Sandbox sandbox, String mode) => sandbox.runGit([
      'add',
      mode,
      '--',
      ':!.dmtools/copilot-sessions',
      ':!.dmtools/copilot-sessions/**',
    ]);

List<String> _rmCopilotSessionsArgs() => [
      'rm',
      '-r',
      '--ignore-unmatch',
      '.dmtools/copilot-sessions',
    ];

/// Sandbox repo mirroring the runner state: the repo's real `.gitignore`,
/// fa-session.sh's `.git/info/exclude` lines, `.dmtools/` artifacts, one
/// tracked file and one ordinary untracked change. All git calls run with
/// hermetic config so global/system gitignore rules cannot leak in.
_Sandbox _sandbox({required bool withCopilotSessions}) {
  final dir = Directory.systemTemp.createTempSync('gitignore_gh59_');
  final sandbox = _Sandbox(dir);
  sandbox.runGit(['init', '-q']);
  File('${dir.path}/tracked.txt').writeAsStringSync('a\n');
  sandbox.runGit(['add', 'tracked.txt']);
  sandbox.runGit(['commit', '-q', '-m', 'init']);
  File('${dir.path}/notes.md').writeAsStringSync('working change\n');
  File('${dir.path}/.gitignore')
      .writeAsStringSync(File('.gitignore').readAsStringSync());

  final dmtools = Directory('${dir.path}/.dmtools')..createSync();
  if (withCopilotSessions) {
    Directory('${dmtools.path}/copilot-sessions').createSync();
    File('${dmtools.path}/copilot-sessions/c.txt').writeAsStringSync('x');
  }
  Directory('${dmtools.path}/fa-sessions').createSync();
  File('${dmtools.path}/fa-sessions/s.txt').writeAsStringSync('x');
  File('${dmtools.path}/fa-trace.log').writeAsStringSync('trace');

  // fa-session.sh writes these on every runner session.
  File('${dir.path}/.git/info/exclude').writeAsStringSync(
    '.dmtools/fa-sessions/\n.dmtools/fa-sessions/**\n',
    mode: FileMode.append,
  );
  return sandbox;
}

class _Sandbox {
  _Sandbox(this.dir);

  final Directory dir;

  ProcessResult runGit(List<String> args) => Process.runSync(
        'git',
        args,
        workingDirectory: dir.path,
        environment: {
          ...Platform.environment,
          'GIT_CONFIG_GLOBAL': '/dev/null',
          'GIT_CONFIG_SYSTEM': '/dev/null',
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_AUTHOR_NAME': 'test',
          'GIT_AUTHOR_EMAIL': 'test@example.com',
          'GIT_COMMITTER_NAME': 'test',
          'GIT_COMMITTER_EMAIL': 'test@example.com',
        },
      );

  List<String> stagedPaths() {
    final result = runGit(['diff', '--cached', '--name-only']);
    expect(result.exitCode, 0, reason: result.stderr);
    return (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
