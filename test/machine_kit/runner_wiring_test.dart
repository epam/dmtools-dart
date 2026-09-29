/// Runner-wiring contract tests for the machine loop (gh-146 edition).
///
/// The per-leg runner configs live in `.dmtools/runners/` and are selected
/// by the factory guard via `.dmtools/config.js` `sm.runners`. Their
/// `parent` and prompt paths resolve at run time in the factory checkout
/// (`factory-agents/` — dmtools-agents cloned beside the target repo by the
/// factory workflow), which does not exist in this repository. Runner-level
/// wiring is therefore pinned on the raw runner JSON here, and the parent
/// side on the same content in the pinned `agents/` submodule.
///
/// Covered contracts:
/// - the review runner opts in to the formal GitHub review (gh-129) with
///   approve-with-suggestions, while the parent's own customParams survive
///   the deepMerge;
/// - the review runner extends the parent prompts with the verdict rules
///   (gh-71 machine protocol) and the rules file exists;
/// - the rework runner keeps its pack parent and the fa provider pin;
/// - the factory workflow invokes review-verdict.sh and defines the cap.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dmtools/src/cli/run_command_processor.dart';
import 'package:dmtools/src/compile/agent_pack_compiler.dart'
    hide AgentPackException;
import 'package:dmtools/src/pack/agent_pack_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../pack/pack_fixtures.dart';

Map<String, dynamic> _runnerJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// The verdict-rules prompt exactly as the review runner references it
/// (a `pack:` ref resolved against the unpacked parent pack at run time).
const _verdictRulesRunnerPath =
    'pack:instructions/pr_review/review_verdict_rules.md';

/// In-repo copy of the verdict-rules instruction (agents/ submodule).
const _verdictRulesFile =
    'agents/instructions/pr_review/review_verdict_rules.md';

void main() {
  formalReviewWiringTests();
  wiringTests();
  resolutionTests();
  faProviderPreconfigTests();
}

/// gh-129: the review runner must opt in to the formal GitHub review
/// (real APPROVE / REQUEST_CHANGES reviews, not just the pr_approved
/// label) while the parent's own customParams survive the deepMerge.
void formalReviewWiringTests() {
  group('machine wiring: formal review', () {
    test(
        'review runner turns on formalGithubReview '
        '(real approvals, not just labels)', () {
      final customParams =
          (_runnerJson('.dmtools/runners/fa-review.json')['params']) as Map;
      final runnerCustomParams = customParams['customParams'] as Map;
      expect(runnerCustomParams['formalGithubReview'], true);
      expect(runnerCustomParams['allowApproveWithSuggestions'], true);
      // deepMerge keeps the parent's own customParams alongside the flags
      // at run time — pinned here on the parent's in-repo copy.
      final parentCustomParams =
          (_runnerJson('agents/pr_review.json')['params'])['customParams']
              as Map;
      expect(parentCustomParams['removeLabel'], 'sm_story_review_triggered');
      expect(parentCustomParams['checkOpenPR'], true);
    });
  });
}

/// Contract tests: the runners + workflow must stay wired to the script and
/// the verdict-rules instruction file.
void wiringTests() {
  group('machine wiring', () {
    test('review runner extends parent prompts with the verdict rules', () {
      final runner = _runnerJson('.dmtools/runners/fa-review.json');
      final params = runner['params'] as Map;
      final prompts = (params['cliPrompts'] as List).cast<String>();
      expect(prompts, contains(_verdictRulesRunnerPath));
      // Parent prompts survive the merge (merge: ["params.cliPrompts"]).
      expect(runner['merge'], contains('params.cliPrompts'));
      final parentPrompts = ((_runnerJson('agents/pr_review.json')['params'])
          as Map)['cliPrompts'] as List;
      expect(parentPrompts.cast<String>(),
          contains('./agents/instructions/pr_review/general_guidelines.md'));
      expect(
        (params['customParams'] as Map)['allowApproveWithSuggestions'],
        true,
      );
    });

    test('verdict-rules instruction file exists', () {
      expect(File(_verdictRulesFile).existsSync(), isTrue);
    });

    test('rework runner still resolves against its pack parent', () {
      final runner = _runnerJson('.dmtools/runners/fa-rework.json');
      expect((runner['parent'] as Map)['path'], 'pr_rework@latest');
      expect(
          ((runner['params'] as Map)['envVariables']
              as Map)['AI_AGENT_PROVIDER'],
          'fa');
    });

    test('workflow invokes the script and defines the cap', () {
      final yml = File('agents/.github/workflows/factory-teammate.yml')
          .readAsStringSync();
      expect(yml, contains('review-verdict.sh'));
      expect(yml, contains('MAX_AUTO_REWORK_ROUNDS'));
      expect(yml, contains('needs-human'));
    });
  });
}

/// gh-146 review thread 4 — the raw pins above cannot execute the
/// parent-chain deepMerge `dmtools run` performs: a typo in a `merge`
/// directive or a parent-shape change passes raw-pin tests and breaks the
/// leg at run time. This group builds the real zip flow end to end: the
/// four parent pipelines are compiled into agent packs from the pinned
/// `agents/` submodule, served from a loopback registry under
/// `<pipeline>@latest`, and each runner under `<tmp>/.dmtools/runners/`
/// (a bare target repo — no `factory-agents/` checkout anywhere) is
/// resolved through [RunCommandProcessor] with an [AgentPackResolver]
/// pointed at that registry. The parent's own paths and the runner's
/// `pack:` prompt refs must land in the pack cache for the legs to work.
void resolutionTests() {
  group(
      'machine wiring: runner resolution through RunCommandProcessor '
      '(pack registry flow)', () {
    late Directory tmp;
    late Directory packsRoot;
    ({int port, Isolate isolate})? server;

    setUpAll(() async {
      tmp = Directory.systemTemp.createTempSync('fa_runner_pack_resolution');
      packsRoot = Directory('${tmp.path}/packs')..createSync();
      final staging = Directory('${tmp.path}/agents-root')..createSync();
      final dist = Directory('${tmp.path}/dist')..createSync();
      // Staging mirrors a dmtools-agents checkout root: the pipeline
      // configs at the root, the subtrees their closures reference.
      for (final name in _packAgents) {
        File('agents/$name').copySync('${staging.path}/$name');
      }
      for (final dir in _packAgentsSubtrees) {
        _copyTree(Directory('agents/$dir'), Directory('${staging.path}/$dir'));
      }
      final files = <String, List<int>>{};
      final catalog = <String, String>{};
      for (final name in _packAgents) {
        final agent = name.replaceAll('.json', '');
        final zip = AgentPackCompiler(staging.path).compile(
            File('${staging.path}/$name'), '1.0.0', 'deadbeef', dist,
            extraDirs: ['instructions', 'prompts']).zipFile;
        final bytes = zip.readAsBytesSync();
        files['/$agent-1.0.0.zip'] = bytes;
        files['/$agent-1.0.0.zip.sha256'] = utf8.encode(
          '${sha256.convert(bytes)}  $agent-1.0.0.zip',
        );
        catalog[agent] = '1.0.0';
      }
      files['/catalog.json'] = utf8.encode(jsonEncode(catalog));
      server = await startRegistryServer(files);
      Directory('${tmp.path}/.dmtools/runners').createSync(recursive: true);
      for (final runner in _runners) {
        File('.dmtools/runners/$runner')
            .copySync('${tmp.path}/.dmtools/runners/$runner');
      }
    });

    tearDownAll(() {
      server?.isolate.kill();
      tmp.deleteSync(recursive: true);
    });

    Map<String, dynamic> resolved(String runner) => jsonDecode(
          RunCommandProcessor(
            packResolver: AgentPackResolver(
              packsRoot: packsRoot,
              registryBaseUrl: 'http://127.0.0.1:${server!.port}',
            ),
          ).process(['run', '${tmp.path}/.dmtools/runners/$runner']),
        ) as Map<String, dynamic>;

    test('all four runners resolve their parent chain and keep the fa pin', () {
      for (final runner in _runners) {
        final env = (resolved(runner)['params'] as Map)['envVariables'] as Map;
        expect(env['AI_AGENT_PROVIDER'], 'fa',
            reason: '$runner must keep the fa provider pin after the '
                'parent-chain deepMerge');
      }
    });

    test(
        'review runner deep-merges gh-129 custom params '
        'alongside the parent\'s own', () {
      final custom =
          (resolved('fa-review.json')['params'] as Map)['customParams'] as Map;
      expect(custom['formalGithubReview'], isTrue);
      expect(custom['allowApproveWithSuggestions'], isTrue);
      expect(custom['checkOpenPR'], isTrue,
          reason: "the parent's own customParams must survive the "
              'deepMerge alongside the runner overrides');
      expect(custom['removeLabel'], 'sm_story_review_triggered',
          reason: "the parent's own removeLabel must survive too");
    });

    test('merge directive appends the pack-resolved verdict rules', () {
      final params = resolved('fa-review.json')['params'] as Map;
      final parentPrompts = (_runnerJson('agents/pr_review.json')['params']
          as Map)['cliPrompts'] as List;
      final prompts = (params['cliPrompts'] as List).cast<String>();
      expect(prompts, hasLength(parentPrompts.length + 1),
          reason: 'a missing/typoed "merge": ["params.cliPrompts"] would '
              'replace the parent prompts instead of appending');
      final verdictRules = prompts.last;
      expect(verdictRules, startsWith(packsRoot.path),
          reason: 'the pack: ref must resolve into the pack cache');
      expect(verdictRules,
          endsWith('instructions/pr_review/review_verdict_rules.md'));
      expect(File(verdictRules).existsSync(), isTrue);
      // The parent's own prompts are rewritten into the cache as well;
      // literal prompt text (no file behind it) passes through untouched.
      for (final prompt in prompts.take(parentPrompts.length)) {
        if (prompt.startsWith(packsRoot.path)) {
          expect(File(prompt).existsSync(), isTrue, reason: prompt);
        }
      }
    });

    test('parent pack paths rewrite into the cache (js/actions/scripts)', () {
      final params = resolved('fa-bug-dev.json')['params'] as Map;
      final post = params['postJSAction'] as String;
      expect(post, startsWith(packsRoot.path));
      expect(post, endsWith('js/developBugAndCreatePR.js'));
      expect(File(post).existsSync(), isTrue);
      final commands = (params['cliCommands'] as List).cast<String>();
      expect(commands.single, startsWith(packsRoot.path));
      expect(commands.single, endsWith('scripts/run-agent.sh'));
      expect(File(commands.single).existsSync(), isTrue);
    });
  });
}

/// The parent pipelines, one agent pack each (`<name>@latest` registry
/// refs), served from the loopback registry in [resolutionTests].
const _packAgents = [
  'bug_development.json',
  'story_development.json',
  'pr_review.json',
  'pr_rework.json',
];

/// Subtrees of the `agents/` submodule the pack closures resolve against.
const _packAgentsSubtrees = [
  'js',
  'instructions',
  'scripts',
  'docs',
  'prompts'
];

const _runners = [
  'fa-bug-dev.json',
  'fa-story-dev.json',
  'fa-review.json',
  'fa-rework.json',
];

/// Recursively copies [src] into [dst] (no symlink following).
void _copyTree(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final entity in src.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (entity is Directory) {
      _copyTree(entity, Directory('${dst.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${dst.path}/$name');
    }
  }
}

/// gh-152: `agents/scripts/providers/fa.sh` refuses to boot the fa CLI
/// without the `FA_PROVIDER_TYPE` + `FA_PROVIDER_CONFIG` env preconfig —
/// the wrapper validates it BEFORE anything else, and `FA_PROVIDERS_QUEUE`
/// is a pass-through it never reads. The review runner shipped with only
/// the queue, so EVERY review leg died at boot
/// ("FA_PROVIDER_TYPE environment variable is required for fa provider" —
/// runs 35287528424 / 35290678499), `outputs/pr_review.json` was never
/// written, and the SM ping-ponged review ↔ rework forever. These pins
/// make the boot contract unmissable for every runner config.js selects.
void faProviderPreconfigTests() {
  group('machine wiring: fa provider boot preconfig (fa.sh contract)', () {
    for (final runner in _runners) {
      _faBootPreconfigRunnerTests(runner);
    }
    _reviewQueueHeadPreconfigTests();
    _devQueueFallbackPreconfigTests();
  });
}

/// Per-runner boot pins: fa.sh validates FA_PROVIDER_TYPE and
/// FA_PROVIDER_CONFIG before anything else — a runner missing either dies
/// at boot (before fa starts) and the SM loops the ticket forever.
void _faBootPreconfigRunnerTests(String runner) {
  final env =
      (_runnerJson('.dmtools/runners/$runner')['params'])['envVariables']
          as Map;

  test('$runner declares FA_PROVIDER_TYPE (fa.sh refuses to boot without it)',
      () {
    expect(env['AI_AGENT_PROVIDER'], 'fa',
        reason: 'precondition: $runner uses the fa provider');
    expect(
      env['FA_PROVIDER_TYPE'],
      allOf(isA<String>(), isNotEmpty),
      reason: 'agents/scripts/providers/fa.sh fails with "FA_PROVIDER_TYPE '
          'environment variable is required for fa provider" — the leg '
          'dies before fa starts, mandatory outputs are never written, '
          'and the SM loops the ticket (gh-152 review runs 35287528424 / '
          '35290678499)',
    );
  });

  test(
      '$runner declares a parseable FA_PROVIDER_CONFIG with '
      'baseUrl/model/apiKeyEnvVar', () {
    expect(
      env['FA_PROVIDER_CONFIG'],
      allOf(isA<String>(), isNotEmpty),
      reason: 'agents/scripts/providers/fa.sh fails with "FA_PROVIDER_CONFIG '
          'is required for fa provider" — same boot-loop effect as a '
          'missing FA_PROVIDER_TYPE (gh-152 review runs 35287528424 / '
          '35290678499)',
    );
    final config = jsonDecode(env['FA_PROVIDER_CONFIG'] as String) as Map;
    for (final key in ['baseUrl', 'model', 'apiKeyEnvVar']) {
      expect(config[key], allOf(isA<String>(), isNotEmpty),
          reason: 'the fa.sh boot contract makes "$key" mandatory in '
              'FA_PROVIDER_CONFIG (fa never guesses catalog defaults)');
    }
  });
}

/// The review runner must pin its DESIGNED primary (the queue head —
/// zai glm-5.3-flash; parity with the dev legs since 2026-09-22, before
/// that kimi/k3) so the wrapper guard passes, while the queue stays wired
/// for fa builds that consume the failover.
void _reviewQueueHeadPreconfigTests() {
  test(
      'review runner pins its designed primary (queue head: glm-5.3-flash) '
      'and keeps the failover queue', () {
    final env = (_runnerJson(
        '.dmtools/runners/fa-review.json')['params'])['envVariables'] as Map;
    expect(env['FA_PROVIDER_TYPE'], 'openai-completions',
        reason: 'the queue head is glm-5.3-flash via the z.ai OpenAI-'
            'compatible endpoint');
    final config = jsonDecode(env['FA_PROVIDER_CONFIG'] as String) as Map;
    expect(config['baseUrl'], 'https://api.z.ai/api/coding/paas/v4');
    expect(config['model'], 'glm-5.3-flash');
    expect(config['apiKeyEnvVar'], 'ZAI_CODE_KEY',
        reason: 'the factory maps ZAI_CODE_KEY into the job env '
            '(factory-teammate.yml)');
    expect(env.containsKey('FA_PROVIDERS_QUEUE'), isTrue);
  });
}

void _devQueueFallbackPreconfigTests() {
  // GLM weekly-limit 429s killed the dev leg with exit 1 (no fallback) —
  // the dev legs must carry the same queue the review leg has:
  // zai/glm-5.3-flash primary, kimi-for-coding as the cooldown fallback.
  for (final runner in ['fa-bug-dev', 'fa-story-dev', 'fa-rework']) {
    test(
        '$runner declares the fallback queue (glm-5.3-flash → '
        'kimi-for-coding)', () {
      final env = (_runnerJson(
          '.dmtools/runners/$runner.json')['params'])['envVariables'] as Map;
      expect(env.containsKey('FA_PROVIDERS_QUEUE'), isTrue,
          reason: 'single-provider preconfig dies hard on provider 429s');
      final queue =
          jsonDecode(env['FA_PROVIDERS_QUEUE'] as String) as List<dynamic>;
      expect(queue, hasLength(2));
      final head = (queue[0] as Map)['provider_config'] as Map;
      expect(head['model'], 'glm-5.3-flash');
      expect(head['apiKeyEnv'], 'ZAI_CODE_KEY');
      final fallback = (queue[1] as Map)['provider_config'] as Map;
      expect(fallback['model'], 'kimi-for-coding');
      expect(fallback['baseUrl'], 'https://api.kimi.com/coding/v1');
      expect(fallback['apiKeyEnv'], 'KIMI_REVIEW_KEY');
    });
  }
}
