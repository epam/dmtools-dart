/// Machine wiring tests for gh-125 — machine comments on GitHub issues must
/// be GitHub-flavored Markdown, not Jira wiki markup.
///
/// gh-122 posted `{code}` blocks and `h3.` headers to a GitHub issue because:
/// 1. no `github` entry existed in any `cliPromptsByTracker` map, and
/// 2. the dev/rework runners never engaged the mechanism at all.
///
/// These tests pin both halves: the Markdown format instruction file must
/// exist and prescribe GitHub-native constructs (fenced code blocks, `#`
/// headings, `[text](url)` links, GFM tables) while banning Jira prefixes,
/// and the dev + rework runners must select it via
/// `params.cliPromptsByTracker.github` (resolved through the parent chain,
/// the same resolution `dmtools run` performs) with `DEFAULT_TRACKER=github`
/// pinned so the CliAgent's tracker lookup resolves the `github` key.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  formatFileTests();
  devRunnerWiringTests();
  reworkRunnerWiringTests();
  defaultTrackerWiringTests();
}

/// The markdown format instruction shipped machine-kit side (upstream
/// dmtools-agents gains its shared copy later).
const _formatFile =
    './machine-kit/teammate-install/instructions/github_comment_format.md';

/// Runners whose comments land on GitHub issues (dev + rework; the review
/// runner posts structured PR-review output and stays upstream-scoped).
const _githubRunners = [
  'machine-kit/teammate-install/runners/fa-bug-dev.json',
  'machine-kit/teammate-install/runners/fa-story-dev.json',
  'machine-kit/teammate-install/runners/fa-rework-zai.json',
];

/// Resolves a runner config through its parent chain — identical to what
/// `dmtools run` executes.
Map<String, dynamic> _resolveRunner(String runner) {
  final json = jsonDecode(
    const RunCommandProcessor().process(['run', runner]),
  ) as Map;
  return json.cast<String, dynamic>();
}

void formatFileTests() {
  test('github_comment_format.md exists and prescribes Markdown', () {
    final file = File(_formatFile.substring(2));
    expect(file.existsSync(), isTrue, reason: '$_formatFile is missing');
    final content = file.readAsStringSync();
    // Prescribes the GitHub-native constructs the comments must use.
    expect(content, contains('```'), reason: 'fenced code blocks');
    expect(content, contains('##'), reason: 'ATX headings');
    expect(content, contains('[text](url)'), reason: 'inline links');
    expect(content, contains('|---|'), reason: 'GFM tables');
    // Bans the Jira wiki markup that leaked into gh-122's comment.
    expect(content, contains('{code}'), reason: 'bans {code} blocks');
    expect(content, contains('{panel}'), reason: 'bans {panel} macros');
    expect(content, contains('h3.'), reason: 'bans h1./h2./h3. prefixes');
  });
}

void devRunnerWiringTests() {
  for (final runner in _githubRunners) {
    test('$runner selects the github tracker prompts', () {
      final params = _resolveRunner(runner)['params'] as Map;
      final byTracker = params['cliPromptsByTracker'];
      expect(byTracker, isA<Map>(),
          reason: 'cliPromptsByTracker missing — the Jira-markup bug '
              '(gh-122) comes back');
      final github = (byTracker['github'] as List?)?.cast<String>();
      expect(github, isNotNull,
          reason: 'no "github" key — the format rules never engage');
      expect(github, contains(_formatFile));
    });
  }

  test('parents stay untouched (the wiring is machine-kit local)', () {
    for (final parent in const [
      'agents/bug_development.json',
      'agents/story_development.json',
      'agents/pr_rework.json',
    ]) {
      final json = jsonDecode(File(parent).readAsStringSync()) as Map;
      final params = json['params'] as Map?;
      expect(params?['cliPromptsByTracker'], isNull,
          reason: '$parent must stay tracker-agnostic — the github key is '
              'this deployment\'s override (upstream gets it later)');
    }
  });
}

void reworkRunnerWiringTests() {
  test('rework runner parent chain still resolves (sanity)', () {
    final json = _resolveRunner(
        'machine-kit/teammate-install/runners/fa-rework-zai.json');
    expect(
      (json['params']['envVariables'] as Map)['AI_AGENT_PROVIDER'],
      'fa',
    );
  });
}

void defaultTrackerWiringTests() {
  for (final runner in _githubRunners) {
    test('$runner pins DEFAULT_TRACKER=github (the active tracker)', () {
      final params = _resolveRunner(runner)['params'] as Map;
      final env = params['envVariables'] as Map;
      expect(env['DEFAULT_TRACKER'], 'github',
          reason: 'CliCommandBuilder resolves tracker prompts via '
              'DEFAULT_TRACKER (Java: configuration.getDefaultTracker()) — '
              'without the pin it falls back to "ado" and the github key '
              'never engages');
    });
  }
}
