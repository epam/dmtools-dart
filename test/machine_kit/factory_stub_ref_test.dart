/// Factory-stub ref guards for the machine loop (gh-146 review threads
/// 1, 2 and 7).
///
/// The `agents` submodule pin makes the factory part of the reviewed merge
/// tree, but a reusable-workflow `uses:` ref is resolved at run start — a
/// branch ref executes whatever sits at the branch head, which has already
/// diverged (upstream moved the reusable workflows from `factory/<name>.yml`
/// to the workflows root). The gates stayed green because the tests pin the
/// *submodule copy* while the runtime resolved the *branch head*: the
/// tested and executed surfaces had drifted apart.
///
/// Covered contracts:
/// - both stubs pin `dmtools-agents` to the exact immutable SHA the `agents`
///   submodule pins (one bump, enforced in lockstep — a partial bump fails);
/// - the `factory/<name>.yml` path the stubs call exists at that commit
///   (checked out in-tree), so the run-start resolution cannot miss;
/// - `secrets: inherit` is the callee's documented contract until the
///   factory declares named secret inputs — GitHub rejects explicit
///   mapping for secrets the callee does not declare, so a half-mapping
///   must fail here instead of at run start.
library;

import 'dart:io';

import 'package:test/test.dart';

/// The two stub→factory calls: workflow file and the called factory path.
const _stubs = {
  '.github/workflows/ai-teammate.yml': '.github/workflows/factory-teammate.yml',
  '.github/workflows/machine-sm.yml': '.github/workflows/factory-sm.yml',
};

/// SHA-pin extraction from a `uses:` line.
final _usesRe = RegExp(r'uses:\s*IstiN/dmtools-agents/(\S+)@(\S+)');

void main() {
  group('factory stub refs execute the reviewed submodule commit', () {
    test('every stub pins uses: to the agents submodule SHA', () {
      final sha = _submodulePin();
      expect(sha, matches(RegExp(r'^[0-9a-f]{40}$')),
          reason: 'gitlink must be a full SHA');
      for (final entry in _stubs.entries) {
        final ref = _stubUsesRef(entry.key);
        expect(ref.path, entry.value,
            reason: '${entry.key} must call the documented factory path');
        expect(ref.version, sha,
            reason: '${entry.key} must pin the immutable SHA the agents '
                'submodule pins (got ${ref.version})');
      }
    });

    test('the called factory workflow exists at the pinned commit', () {
      for (final path in _stubs.values) {
        expect(File('agents/$path').existsSync(), isTrue,
            reason: 'agents/ is the submodule checkout of the pinned '
                'commit — $path must exist there');
      }
    });

    test('secrets stay on the callee-documented inherit contract', () {
      for (final stub in _stubs.keys) {
        final yml = File(stub).readAsStringSync();
        expect(yml, contains('secrets: inherit'),
            reason: '$stub must keep the factory\'s documented '
                'secrets contract');
        expect(yml, isNot(contains('SOURCE_GITHUB_TOKEN:')),
            reason: 'GitHub rejects explicit mapping for secrets the '
                'callee does not declare — a half-mapping must not '
                'sneak in');
      }
    });
  });
}

/// Resolves the `agents` gitlink at HEAD (the reviewed factory commit).
String _submodulePin() {
  final result = Process.runSync('git', ['ls-tree', 'HEAD', 'agents']);
  expect(result.exitCode, 0, reason: 'git ls-tree failed inside the repo');
  final parts = result.stdout.toString().trim().split(RegExp(r'\s+'));
  expect(parts, hasLength(greaterThanOrEqualTo(3)));
  expect(parts[1], 'commit', reason: 'agents must stay a submodule');
  return parts[2];
}

/// Extracts the called path and ref from a stub's `uses:` line.
({String path, String version}) _stubUsesRef(String stubPath) {
  final yml = File(stubPath).readAsStringSync();
  final match = _usesRe.firstMatch(yml);
  expect(match, isNotNull,
      reason: '$stubPath must contain a dmtools-agents uses: call');
  return (path: match!.group(1)!, version: match.group(2)!);
}
