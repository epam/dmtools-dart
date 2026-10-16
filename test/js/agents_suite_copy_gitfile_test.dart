import 'dart:io';

import 'package:dmtools/src/js/agents_suite.dart';
import 'package:test/test.dart';

/// The suite's per-chunk copy re-points `.git` at the ORIGINAL git dir by
/// absolute path so the read-only `git ls-files` calls in
/// test_agentDocsCoverage/test_agentValidator answer from the source index.
///
/// Regression (2026-10-15, live full-suite run): when the source tree's
/// `.git` is a REAL DIRECTORY (the fetch-from-main policy clones
/// dmtools-agents directly — no submodule gitfile) AND the caller passes a
/// RELATIVE tree path (production passes `agents`), `_writeGitFileRef`
/// joined the RELATIVE entity path (`agents/.git`) onto the absolute parent,
/// producing `gitdir: .../agents/agents/.git` — `fatal: not a git
/// repository` in every chunk that ran agentDocsCoverage.
void main() {
  final fixtureRoot = 'test/.tmp_agents_rel_fixture';

  setUp(() {
    Directory(fixtureRoot).createSync(recursive: true);
  });

  tearDown(() {
    final d = Directory(fixtureRoot);
    if (d.existsSync()) d.deleteSync(recursive: true);
  });

  test(
      'copyAgentTree: a real-directory .git yields a working gitfile '
      '(relative source, the production shape)', () {
    final src = Directory('$fixtureRoot/src_tree')..createSync(recursive: true);
    final init = Process.runSync(
        'git', ['init', '-q', '--initial-branch=main', src.path]);
    expect(init.exitCode, 0, reason: 'git init failed in the fixture');
    File('${src.path}/hello.json').writeAsStringSync('{}');
    Process.runSync('git', ['add', 'hello.json'], workingDirectory: src.path);

    // RELATIVE paths — exactly what the suite runner passes in production
    // (`agents`). The multi-segment relative path triggers the join bug.
    final srcRel = '$fixtureRoot/src_tree';
    final dstRel = '$fixtureRoot/dst_tree';
    // Production creates the chunk root before copying (bin runner does);
    // the copier itself only recurses.
    Directory(dstRel).createSync(recursive: true);
    copyAgentTree(srcRel, dstRel);

    final gitfile = File('$dstRel/.git').readAsStringSync().trim();
    final match = RegExp(r'gitdir: (.+)').firstMatch(gitfile);
    expect(match, isNotNull, reason: 'the copy must carry a .git gitfile');
    final target = match!.group(1)!;
    expect(target, startsWith('/'),
        reason: 'the gitdir must be absolute — the copy lives elsewhere');
    expect(Directory(target).existsSync(), isTrue,
        reason: 'gitdir target must exist (doubled path = not a repository); '
            'got $gitfile');

    final ls = Process.runSync('git', ['ls-files', '*.json'],
        workingDirectory: dstRel);
    expect(ls.exitCode, 0, reason: 'stderr: ${ls.stderr}');
    expect(ls.stdout as String, contains('hello.json'));
  });
}
