/// Tracker-specific prompt resolution during the CliAgent CLI phase
/// (gh-125): the command builder must receive the active tracker
/// (`DEFAULT_TRACKER` via PropertyReader — Java
/// `configuration.getDefaultTracker()` parity) so `cliPromptsByTracker`
/// selects the right markup rules for the serving tracker.
///
/// The merged prompt is observed end-to-end by `cat`-ing the appended
/// prompt file — its stdout becomes the command response.
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  lifecycleTrackerPromptsTests();
  conditionalTrackerPromptsTests();
}

void lifecycleTrackerPromptsTests() {
  group('CliAgent tracker prompts', () {
    Future<String> runPrompt(Map<String, String>? envVariables) async {
      final tmp = await Directory.systemTemp.createTemp('cli_tracker_prompt_');
      try {
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['cat']
            ..cliPrompts = ['base-rules']
            ..cliPromptsByTracker = {
              'github': ['github-markdown-rules'],
              'jira': ['jira-wiki-rules'],
              'ado': ['ado-rules'],
            }
            ..envVariables = envVariables
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(result['success'], isTrue, reason: '${result['error']}');
        return result['response'] as String;
      } finally {
        await tmp.delete(recursive: true);
      }
    }

    test('DEFAULT_TRACKER=github merges the github prompts', () async {
      final prompt = await runPrompt({'DEFAULT_TRACKER': 'github'});
      expect(prompt, contains('base-rules'));
      expect(prompt, contains('github-markdown-rules'));
      expect(prompt, isNot(contains('jira-wiki-rules')));
      expect(prompt, isNot(contains('ado-rules')));
    });

    test('DEFAULT_TRACKER=jira merges the jira prompts', () async {
      final prompt = await runPrompt({'DEFAULT_TRACKER': 'jira'});
      expect(prompt, contains('jira-wiki-rules'));
      expect(prompt, isNot(contains('github-markdown-rules')));
    });

    test('blank DEFAULT_TRACKER keeps the ado fallback (Java default)',
        () async {
      final prompt = await runPrompt({'DEFAULT_TRACKER': ''});
      expect(prompt, contains('ado-rules'));
      expect(prompt, isNot(contains('github-markdown-rules')));
    });
  });
}

void conditionalTrackerPromptsTests() {
  group('CliAgent conditional tracker prompts', () {
    test('evaluates conditional section objects inside cliPromptsByTracker',
        () async {
      final tmp =
          await Directory.systemTemp.createTemp('cli_tracker_cond_prompt_');
      try {
        File('${tmp.path}/isScm.js')
            .writeAsStringSync('function action() { return true; }\n');
        File('${tmp.path}/isTracker.js')
            .writeAsStringSync('function action() { return false; }\n');
        final params = _buildConditionalTrackerParams(tmp.path);
        expect(params.cliPromptsByTracker?['jira'], [
          'jira-wiki-comment-format',
          'markdown-output-format',
          'jira-context-rules',
        ]);
        final result = await CliAgent(
          params: params,
          workingDirectory: tmp.path,
        ).run();
        expect(result['success'], isTrue, reason: '${result['error']}');
        final prompt = result['response'] as String;
        expect(prompt, contains('base-rules'));
        expect(prompt, isNot(contains('jira-wiki-comment-format')));
        expect(prompt, contains('markdown-output-format'));
        expect(prompt, contains('jira-context-rules'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('evaluates conditions only for effective tracker key', () {
      final params = _buildConditionalTrackerParams('/tmp');
      final evaluated = <String>[];
      final resolved = params.flattenCliPromptsByTracker(
        trackerType: 'jira',
        conditionEvaluator: (cond) {
          evaluated.add(cond);
          return cond.endsWith('isScm.js');
        },
      );
      expect(evaluated, ['/tmp/isTracker.js', '/tmp/isScm.js']);
      expect(
          resolved?['jira'], ['markdown-output-format', 'jira-context-rules']);
    });
  });
}

CliAgentParams _buildConditionalTrackerParams(String dir) =>
    CliAgentParams.fromJson({
      'cliCommands': ['cat'],
      'cliPrompts': ['base-rules'],
      'cliPromptsByTracker': {
        'jira': [
          {
            'id': 'responseFormatJiraWiki',
            'prompt': 'jira-wiki-comment-format',
            'condition': '$dir/isTracker.js',
          },
          {
            'id': 'responseFormatMarkdown',
            'prompt': 'markdown-output-format',
            'condition': '$dir/isScm.js',
          },
          'jira-context-rules',
        ],
        'github': [
          {
            'id': 'unusedGithubSection',
            'prompt': 'github-cond-format',
            'condition': '$dir/unusedGithubCond.js',
          },
        ],
      },
      'envVariables': {'DEFAULT_TRACKER': 'jira'},
      'cleanupInputFolder': false,
    });
