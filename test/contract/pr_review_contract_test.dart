/// L2 contract tests for the formal PR-review tools (gh-129) — replays
/// recorded Java tool invocations through the **JS bridge**.
///
/// The fixtures live in `test/fixtures/contract/` (framework in
/// [runContractCases]); unlike the Jira contract test, which drives the
/// async Dio client, this replay exercises the full agent-script path:
///
/// QuickJS global `github_submit_pr_review({...})` (the generated
/// snake_case wrapper, the same surface `agents/js/common/scm.js` calls)
/// → `executeToolViaJava` → `SyncToolDispatcher` → curl → fixture server.
///
/// Each fixture's `mock_status`/`mock_response_body` is served by
/// `pr_review_fixture_server.py` (a Python subprocess — Dart's event loop
/// is blocked during the synchronous curl call), the recorded upstream
/// request is asserted against `java_api_endpoint` / `java_http_method` /
/// `java_request_body` (the Java request shapes), and the JS-visible
/// result (or caught JS error message) is compared with
/// `expected_response`.
///
/// Skip-or-fail policy: no live calls — everything is localhost; the
/// suite skips silently when `python3` is unavailable (same as the sync
/// tools tests).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

import '../js/echo_server_helper.dart';
import 'contract_test_helper.dart';

/// The review tools under contract: the GitHub formal review submit and
/// the GitLab approve/unapprove pair the (upstream) scm.js gitlab
/// `submitReview` mapping drives.
const _reviewTools = {
  'github_submit_pr_review',
  'gitlab_approve_mr',
  'gitlab_unapprove_mr',
};

/// The shared canned-response fixture subprocess (see
/// `pr_review_fixture_server.py`); started once in [main].
_PrReviewFixtureServer? _server;

void main() {
  setUpAll(() async {
    PropertyReader.testIsolation = true;
    if (hasPython3()) _server = await _PrReviewFixtureServer.start();
  });
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
    _server?.stop();
  });
  if (hasPython3()) {
    runContractCases(
      'test/fixtures/contract',
      _reviewTools,
      _replayThroughJsBridge,
    );
  }
}

/// Replays one fixture through the JS bridge and asserts the Java request
/// shape reached the wire.
///
/// Returns the JS-visible result (the tool output decoded, or the caught
/// JS error message under `caught`) for comparison with the fixture's
/// `expected_response`.
Future<Object?> _replayThroughJsBridge(ContractFixture f) async {
  _server!.serve(status: f.mockStatus, body: f.mockBody);
  PropertyReader.setOverrides(
    f.toolName.startsWith('github_')
        ? {
            'SOURCE_GITHUB_TOKEN': 'ghp_testtoken',
            'SOURCE_GITHUB_BASE_PATH': 'http://127.0.0.1:${_server!.port}',
          }
        : {
            'GITLAB_BASE_PATH': 'http://127.0.0.1:${_server!.port}',
            'GITLAB_TOKEN': 'glpat_testtoken',
          },
  );
  final dir = Directory.systemTemp.createTempSync('dmtools_pr_contract_');
  addTearDown(() => dir.deleteSync(recursive: true));
  // The agent-script calling convention: the snake_case global — exactly
  // how scm.js providers invoke the review tools — wrapped in the
  // try/catch shape applyFormalGithubReview uses so an upstream rejection
  // surfaces as a caught JS error, never as a silent pass-through.
  final script = File('${dir.path}/contract_replay.js')..writeAsStringSync('''
var out;
try {
  out = ${f.toolName}(${jsonEncode(f.requestArgs)});
} catch (e) {
  out = {caught: String(e.message)};
}
function action(params) { return out; }
''');
  final result = const JsJobRunner().runScript(
    scriptPath: script.path,
    jobParams: {},
  );

  // The Java request shape must have reached the wire unchanged.
  final sent = _server!.lastRequest!;
  expect(sent['method'], f.javaHttpMethod, reason: f.toolName);
  expect(sent['path'], f.javaApiEndpoint, reason: f.toolName);
  if (f.javaRequestBody != null) {
    expect(jsonDecode(sent['body'] as String), f.javaRequestBody,
        reason: f.toolName);
  }
  return jsonDecode(result!);
}

/// Manages the canned-response fixture subprocess lifecycle.
class _PrReviewFixtureServer {
  _PrReviewFixtureServer._(this._process, this._control);

  /// Starts the server on an ephemeral port; awaits the port line.
  static Future<_PrReviewFixtureServer> start() async {
    final dir = Directory.systemTemp.createTempSync('dmtools_pr_server_');
    final control = File('${dir.path}/control.json');
    final logPath = '${dir.path}/r.log';
    final process = await Process.start('python3', [
      '${Directory.current.path}/test/contract/pr_review_fixture_server.py',
      '0',
      control.path,
      logPath,
    ]);
    final port = int.parse(await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first);
    return _PrReviewFixtureServer._(process, control)
      ..port = port
      .._lastFile = File('$logPath.last.json');
  }

  final Process _process;
  final File _control;
  File? _lastFile;

  /// The bound port (valid after [start]).
  int port = 0;

  /// Serves [status] + [body] for the next request.
  void serve({required int status, String body = ''}) =>
      _control.writeAsStringSync(jsonEncode({'status': status, 'body': body}));

  /// The last recorded request (`{method, path, headers, body}`), or null
  /// before the first request arrives.
  Map<String, dynamic>? get lastRequest {
    final file = _lastFile;
    if (file == null || !file.existsSync()) return null;
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Kills the server process.
  void stop() => _process.kill();
}
