import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/job_runner.dart';
import 'package:dmtools/src/js/js_env_shim.dart';
import 'package:test/test.dart';

/// `java.lang.System.getenv` shim — Java `JsEnvironmentShim` parity
/// (epam/dm.ai#730): installed by default in every bridge-wired engine,
/// strict allow-list, values via [PropertyReader].
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);

  group('jsGetenv', () {
    test('allow-list matches the Java contract', () {
      expect(jsReadableEnvNames, {
        'DEFAULT_TRACKER',
        'ADO_PROJECT',
        'JIRA_BASE_PATH',
        'GITHUB_SERVER_URL',
        'GITHUB_REPOSITORY',
        'GITHUB_RUN_ID',
        'CHECKOUT_REF',
      });
    });

    test('resolves allow-listed names through the lookup', () {
      expect(jsGetenv('DEFAULT_TRACKER', lookup: (_) => 'github'), 'github');
    });

    test('returns null for non-listed names and non-strings', () {
      String? lookup(String n) => 'secret';
      expect(jsGetenv('SOURCE_GITHUB_TOKEN', lookup: lookup), isNull);
      expect(jsGetenv(null, lookup: lookup), isNull);
      expect(jsGetenv(42, lookup: lookup), isNull);
    });

    test('host adapter decodes bare and array payloads', () {
      String? lookup(String n) => 'v';
      expect(jsGetenvHost('"ADO_PROJECT"', lookup: lookup), '"v"');
      expect(jsGetenvHost('["ADO_PROJECT"]', lookup: lookup), '"v"');
      expect(jsGetenvHost('"JIRA_TOKEN"', lookup: lookup), 'null');
      expect(jsGetenvHost('{', lookup: lookup), 'null');
    });
  });

  group('JS global', () {
    String? run(String body) => const JsJobRunner().runScript(
          scriptPath: 'function action(params) { $body }',
          jobParams: {},
        );

    test('is installed by default and detectable', () {
      expect(
        run("return String(typeof java !== 'undefined' && java.lang && "
            "java.lang.System && "
            "typeof java.lang.System.getenv === 'function');"),
        contains('true'),
      );
    });

    test('reads allow-listed values via PropertyReader overrides', () {
      PropertyReader.setOverrides({
        'DEFAULT_TRACKER': 'github',
        'SOURCE_GITHUB_TOKEN': 'ghp_secret',
      });
      expect(run("return java.lang.System.getenv('DEFAULT_TRACKER');"),
          contains('github'));
      expect(
        run("return String(java.lang.System.getenv('SOURCE_GITHUB_TOKEN') === null);"),
        allOf(contains('true'), isNot(contains('ghp_secret'))),
      );
      expect(run("return String(java.lang.System.getenv('CHECKOUT_REF') === null);"),
          contains('true'));
    });

    test('host function is not left reachable', () {
      expect(run('return typeof __jsGetenvHost;'), contains('undefined'));
    });
  });
}
