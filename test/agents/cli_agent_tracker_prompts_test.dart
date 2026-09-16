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

void main() => lifecycleTrackerPromptsTests();

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
