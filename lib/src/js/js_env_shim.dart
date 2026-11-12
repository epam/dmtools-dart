/// `java.lang.System.getenv(name)` shim for agent scripts — Java
/// `JsEnvironmentShim` parity (epam/dm.ai#730).
///
/// Agent scripts (`js/common/trackers.js`) read non-secret selectors such
/// as `DEFAULT_TRACKER` through `java.lang.System.getenv`. The shim answers
/// only for [jsReadableEnvNames] and returns `null` for every other name —
/// the same result a script sees for an unset variable — so credentials can
/// never leak into JS. Values resolve through [PropertyReader] (overrides,
/// `dmtools.env`, process env), not the raw OS environment.
library;

import 'dart:convert';

import '../config/property_reader.dart';

/// Configuration names a script may read. Never add a credential here.
const Set<String> jsReadableEnvNames = {
  'DEFAULT_TRACKER',
  'ADO_PROJECT',
  'JIRA_BASE_PATH',
  'GITHUB_SERVER_URL',
  'GITHUB_REPOSITORY',
  'GITHUB_RUN_ID',
  'CHECKOUT_REF',
};

/// Resolves [name] when allow-listed; `null` otherwise. [lookup] defaults
/// to a fresh [PropertyReader] per call (Java `new PropertyReader()` parity).
String? jsGetenv(Object? name, {String? Function(String name)? lookup}) {
  if (name is! String || !jsReadableEnvNames.contains(name)) return null;
  return (lookup ?? (n) => PropertyReader().getValue(n))(name);
}

/// Host-function adapter: decodes the marshaled argument payload (a bare
/// value for one argument, an array for several) and returns the JSON
/// result the QuickJS bridge parses back into a JS value.
String jsGetenvHost(String argsJson, {String? Function(String name)? lookup}) {
  Object? parsed;
  try {
    parsed = jsonDecode(argsJson);
  } on FormatException {
    return 'null';
  }
  final name = parsed is List ? (parsed.isEmpty ? null : parsed.first) : parsed;
  final value = jsGetenv(name, lookup: lookup);
  return value == null ? 'null' : jsonEncode(value);
}

/// Installs `globalThis.java.lang.System.getenv` over `__jsGetenvHost`
/// unless a real `java` global already exists (never clobbers it).
const String jsEnvShimBootstrap = '''
(function() {
    var host = globalThis.__jsGetenvHost;
    try { delete globalThis.__jsGetenvHost; } catch (e) {}
    if (typeof globalThis.java !== 'undefined') return;
    var getenv = function(name) {
        if (typeof name !== 'string') return null;
        var v = host(name);
        return v === undefined ? null : v;
    };
    globalThis.java = { lang: { System: { getenv: getenv } } };
})();
''';
