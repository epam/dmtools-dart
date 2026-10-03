/// Shared fixture for the `ScmCiSyncTools` suites: fake provider handlers
/// plus GitHub/GitLab-side subjects with the scm+ci routing preconfigured.
library;

import 'dart:convert';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/scm_ci_sync_tools.dart';
import 'package:test/test.dart';

/// One translated tool executor.
typedef Handler = String Function(Map<String, dynamic> args);

/// Opens/closes the PropertyReader test environment around the suite.
void withScmCiEnv(void Function() body) {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() => PropertyReader.setOverrides(const {}));
  tearDown(PropertyReader.clearOverrides);
  body();
}

/// Fake provider handlers: a tool missing from the map fails the test —
/// the alias must only call what the translation table declares.
Map<String, Handler> fake(Map<String, Handler> handlers) => handlers;

Map<String, dynamic> decode(String raw) {
  final v = jsonDecode(raw);
  return v is Map<String, dynamic> ? v : {'value': v};
}

/// GitHub-side test subject with a configured scm+ci routing.
ScmCiSyncTools ghSubject(Map<String, Handler> gh, {Map<String, Handler>? gl}) =>
    ScmCiSyncTools(
      scmProvider: 'github',
      ciProvider: 'github',
      githubHandlers: fake(gh),
      gitlabHandlers: fake(gl ?? const {}),
    );

/// GitLab-side test subject.
ScmCiSyncTools glSubject(Map<String, Handler> gl, {Map<String, Handler>? gh}) =>
    ScmCiSyncTools(
      scmProvider: 'gitlab',
      ciProvider: 'gitlab',
      githubHandlers: fake(gh ?? const {}),
      gitlabHandlers: fake(gl),
    );
