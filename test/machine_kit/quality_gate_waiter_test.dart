import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Quality-gate waiter contract tests — the dmtools-dart sibling of the fa
/// ci-gate fix (flutter_agent_harness#782). The REAL `run:` block is
/// extracted from the parsed workflow YAML and executed against a stubbed
/// `gh` serving GitHub-shaped fixtures. Pins the debris-proof verdict
/// selection: cancelled/skipped/queued runs are never a verdict, the
/// NEWEST non-debris run decides, and an in-flight rerun outranks any
/// older conclusion. The poll loop's test seams (GATE_WAIT_SECONDS /
/// GATE_POLL_SECONDS) keep each case fast.
void main() {
  // ignore: avoid_dynamic; fixtures are GitHub-shaped JSON maps
  final repoRoot = Directory.current.path;
  final wf = File('$repoRoot/.github/workflows/quality-gate.yml');

  late String runScript;
  late Map waiterJob;
  late Map jobs;

  setUpAll(() {
    final doc = loadYaml(wf.readAsStringSync());
    jobs = (doc['jobs'] as Map).cast<String, Map>();
    waiterJob = jobs['sm-validation']!;
    final steps = (waiterJob['steps'] as List).cast<Map>();
    runScript = steps.firstWhere((s) => s['id'] == 'wait')['run'] as String;
  });

  Directory? shimDir;
  setUp(() {
    shimDir = Directory.systemTemp.createTempSync('gate-waiter-');
  });
  tearDown(() {
    shimDir?.deleteSync(recursive: true);
  });

  /// Runs the real waiter script; [responses] are the JSON documents the
  /// stubbed `gh api` returns, one per poll (last one repeats). Returns
  /// (exitCode, conclusionOutput, stdout).
  (int, String, String) runWaiter(List<String> responses) {
    final dir = shimDir!.path;
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
          '$runScript'
    ]);
    final conclusion = out.existsSync()
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
    return (r.exitCode, conclusion, r.stdout.toString());
  }

  String runsDoc(List<Map> runs) => jsonEncode({
        'total_count': runs.length,
        'workflow_runs': [
          for (final r in runs)
            {'id': 1, ...r.map((k, v) => MapEntry(k.toString(), v))},
        ],
      });

  final green = {'status': 'completed', 'conclusion': 'success'};
  final red = {'status': 'completed', 'conclusion': 'failure'};
  final cancelled = {'status': 'completed', 'conclusion': 'cancelled'};
  final inFlight = {'status': 'in_progress', 'conclusion': null};
  final queued = {'status': 'queued', 'conclusion': null};

  test('green dispatched run mirrors success', () {
    final (code, conclusion, _) = runWaiter([
      runsDoc([green])
    ]);
    expect(code, 0, reason: 'green must exit 0');
    expect(conclusion, 'success');
  });

  test('red dispatched run mirrors failure (real verdicts pass through)', () {
    final (code, conclusion, _) = runWaiter([
      runsDoc([red])
    ]);
    expect(code, 0, reason: 'the waiter itself exits 0 — mirrors carry red');
    expect(conclusion, 'failure');
  });

  test(
      'cancelled debris over green is NOT a verdict — keeps waiting, then green',
      () {
    // Poll 1: newest is cancelled debris, older is green -> must wait.
    // Poll 2: debris gone (list pruned) -> green decides.
    final (code, conclusion, _) = runWaiter([
      runsDoc([cancelled, green]),
      runsDoc([green]),
    ]);
    expect(code, 0);
    expect(conclusion, 'success');
  });

  test('cancelled debris over red is NOT a verdict either', () {
    final (code, conclusion, _) = runWaiter([
      runsDoc([cancelled, red]),
      runsDoc([red]),
    ]);
    expect(code, 0);
    expect(conclusion, 'failure');
  });

  test('in-flight rerun outranks older green, then flips red', () {
    final (code, conclusion, _) = runWaiter([
      runsDoc([inFlight, green]), // older green must NOT be read yet
      runsDoc([red]), // rerun concluded red
    ]);
    expect(code, 0);
    expect(conclusion, 'failure');
  });

  test('queued runs are debris — never a verdict', () {
    final (code, conclusion, _) = runWaiter([
      runsDoc([queued, green]),
      runsDoc([green]),
    ]);
    expect(code, 0);
    expect(conclusion, 'success');
  });

  test('no dispatched run at all -> deadline error (exit 1)', () {
    final (code, conclusion, _) =
        runWaiter(['{"total_count":0,"workflow_runs":[]}']);
    expect(code, 1, reason: 'SM broken / never dispatched = human signal');
    expect(conclusion, isEmpty, reason: 'no verdict must be latched');
  });

  test('mirror jobs skip cancelled/skipped waiter (no false red)', () {
    for (final jobName in ['static', 'gate', 'agents-suite']) {
      final job = jobs[jobName]!;
      final cond = job['if'] as String;
      expect(cond, contains("needs.sm-validation.result == 'success'"),
          reason: '$jobName must mirror a real success verdict');
      expect(cond, contains("needs.sm-validation.result == 'failure'"),
          reason: '$jobName must mirror a real failure verdict');
      expect(cond, isNot(contains('did not run')),
          reason: 'guard is structural, not message-level');
    }
  });

  test('waiter window is 85 min with a 90 min job timeout (slow pool)', () {
    expect(runScript, contains('GATE_WAIT_SECONDS:-5100'),
        reason: '85-min poll window, overridable only for tests');
    expect(waiterJob['timeout-minutes'], 90);
  });

  test('poll fetches 30 runs, not per_page=1 (debris-tolerant selection)', () {
    expect(runScript, contains('per_page=30'));
    expect(runScript, isNot(contains('per_page=1')));
  });
}
