// Debris-proof SM quality-gate waiter tests: drives the REAL run block
// from .github/workflows/quality-gate.yml through a stubbed `gh` + real
// `jq`, so the assertions pin the shipped script, not a copy.
//
// Bodies live in [WaiterHarness] methods — crap4dart method_size caps
// main() at 60 lines (gate is law; the first cut of this file shipped a
// 172-line main and red main, 2026-09-22).
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final h = WaiterHarness();

  setUpAll(h.loadWorkflow);
  setUp(h.makeTempDir);
  tearDown(h.cleanup);

  test('verdict matrix: green/red decide, debris never does', () {
    void chk(String want, List<String> polls) {
      final v = h.verdict(polls);
      expect(v.code, 0, reason: 'mirrors carry the verdict');
      expect(v.conclusion, want, reason: 'selected verdict');
    }

    chk('success', [
      h.doc([h.green])
    ]);
    chk('failure', [
      h.doc([h.red])
    ]);
    chk('success', [
      h.doc([h.cancelled, h.green]),
      h.doc([h.green])
    ]);
    chk('failure', [
      h.doc([h.cancelled, h.red]),
      h.doc([h.red])
    ]);
    chk('failure', [
      h.doc([h.inFlight, h.green]),
      h.doc([h.red])
    ]);
    chk('success', [
      h.doc([h.queued, h.green]),
      h.doc([h.green])
    ]);
  });
  test('no dispatched run -> deadline error (exit 1)', () {
    final (code, conclusion, _) =
        h.runWaiter(['{"total_count":0,"workflow_runs":[]}']);
    expect(code, 1, reason: 'SM broken / never dispatched = human signal');
    expect(conclusion, isEmpty, reason: 'no verdict must be latched');
  });
  test('mirror jobs skip cancelled/skipped waiter', () {
    for (final jobName in ['static', 'gate', 'agents-suite']) {
      final cond = h.job(jobName)['if'] as String;
      expect(cond, contains("needs.sm-validation.result == 'success'"));
      expect(cond, contains("needs.sm-validation.result == 'failure'"));
      expect(cond, isNot(contains('did not run')));
    }
  });
  test('waiter window 85m, page 30 (debris-tolerant)', () {
    expect(h.runScript, contains('GATE_WAIT_SECONDS:-5100'));
    expect(h.waiterJob['timeout-minutes'], 90);
    expect(h.runScript, contains('per_page=30'));
    expect(h.runScript, isNot(contains('per_page=1')));
  });
}

/// Loads the shipped waiter block and drives it against stubbed fixtures.
class WaiterHarness {
  late final String _runScript;
  late final Map _waiterJob;
  late final Map<String, Map> _jobs;
  Directory? _shimDir;

  // GitHub-shaped run fixtures.
  final green = {'status': 'completed', 'conclusion': 'success'};
  final red = {'status': 'completed', 'conclusion': 'failure'};
  final cancelled = {'status': 'completed', 'conclusion': 'cancelled'};
  final inFlight = {'status': 'in_progress', 'conclusion': null};
  final queued = {'status': 'queued', 'conclusion': null};

  void loadWorkflow() {
    final wf =
        File('${Directory.current.path}/.github/workflows/quality-gate.yml');
    final doc = loadYaml(wf.readAsStringSync());
    _jobs = (doc['jobs'] as Map).cast<String, Map>();
    _waiterJob = _jobs['sm-validation']!;
    final steps = (_waiterJob['steps'] as List).cast<Map>();
    _runScript = steps.firstWhere((s) => s['id'] == 'wait')['run'] as String;
  }

  void makeTempDir() {
    _shimDir = Directory.systemTemp.createTempSync('gate-waiter-');
  }

  void cleanup() {
    _shimDir?.deleteSync(recursive: true);
  }

  /// Encodes one `gh api /actions/runs` poll response.
  String doc(List<Map> runs) => jsonEncode({
        'total_count': runs.length,
        'workflow_runs': [
          for (final r in runs)
            {'id': 1, ...r.map((k, v) => MapEntry(k.toString(), v))},
        ],
      });

  /// Runs the real waiter script; [responses] are the JSON documents the
  /// stubbed `gh api` returns, one per poll (last one repeats).
  /// Returns (exitCode, conclusionOutput, stdout).
  (int, String, String) runWaiter(List<String> responses) {
    final dir = _shimDir!.path;
    File('$dir/responses.txt').writeAsStringSync('${responses.join('\n')}\n');
    // Behaves like `gh api <url> --jq <expr>`: the current fixture line is
    // piped through the REAL jq with the expression the script passed.
    final shim = '''
#!/bin/sh
d="\$(dirname "\$0")"
i="\$(cat "\$d/cursor" 2>/dev/null || echo 0)"
n=\$((i+1)); echo "\$n" > "\$d/cursor"
line="\$(awk -v n="\$i" 'NR==n' "\$d/responses.txt")"
[ -n "\$line" ] || line="\$(tail -1 "\$d/responses.txt")"
expr=""
while [ \$# -gt 1 ]; do
  if [ "\$2" = "--jq" ] && [ \$# -ge 3 ]; then expr="\$3"; fi
  shift
done
if [ -n "\$expr" ]; then printf '%s' "\$line" | jq -r "\$expr"; else printf '%s' "\$line"; fi
''';
    File('$dir/gh').writeAsStringSync(shim);
    Process.runSync('chmod', ['+x', '$dir/gh']);
    final out = File('$dir/github_output');
    final r = Process.runSync('bash', [
      '-c',
      'export PATH="$dir:\$PATH" GITHUB_REPOSITORY=a/b SHA=deadbeef '
          'GITHUB_OUTPUT="${out.path}" GATE_WAIT_SECONDS=6 GATE_POLL_SECONDS=1\n'
          'SECONDS=0\n'
          '$_runScript'
    ]);
    final conclusion = _readConclusion(out);
    return (r.exitCode, conclusion, r.stdout.toString());
  }

  String _readConclusion(File out) => out.existsSync()
      ? (out.readAsStringSync().trim().isEmpty
          ? ''
          : out
              .readAsStringSync()
              .split('conclusion=')
              .last
              .split('\n')
              .first
              .trim())
      : '';

  /// Drives one waiter scenario; [polls] feed the stubbed gh (last repeats).
  /// Async shape keeps the call sites one line inside each test closure.
  ({int code, String conclusion}) verdict(List<String> polls) {
    final (code, conclusion, _) = runWaiter(polls);
    return (code: code, conclusion: conclusion);
  }

  Map job(String name) => _jobs[name]!;
  String get runScript => _runScript;
  Map get waiterJob => _waiterJob;
}
