/// Host function behind the require() loader's module-source read.
///
/// Java `JobJavaScriptBridge.loadModule` parity (gh-369): the loader is a
/// HOST primitive reading via `loadJavaScriptCode` — direct host IO that
/// never consults the `FileTools` sandbox (that governs agent tool calls).
/// The loader only reads paths it resolved itself from the current script
/// directory / module spec, so it is host-trusted machinery: pack modules
/// under `~/.dmtools/packs` load regardless of the working-dir containment
/// or `DMTOOLS_FILE_READ_ALLOWED_PATHS` (live: v0.1.41 broke every
/// pack-internal require otherwise — the 21:49Z SM tick died on
/// `sm_github-0.1.36/js/configLoader.js`).
///
/// Returns the file content as a plain JSON string (the C bridge unmarshals
/// it back to a JS string), or JS `null` when the file cannot be read —
/// the same contract the `file_read` host gives, so the require prelude's
/// 'JavaScript file not found' path is unchanged. No call logging: this is
/// not a tool call (nothing agent-visible happens here); the subsequent
/// module eval is the observable event.
library;

import 'dart:convert';
import 'dart:io';

/// Handles `__loaderFileRead(path)` calls from the require prelude.
///
/// The argument arrives JSON-marshaled through the FFI bridge: a single
/// string argument as the JSON string itself, an object as `{"path": …}`
/// (mirroring how [ToolBridge] decodes `file_read` calls).
String loaderReadHost(String argsJson) {
  dynamic parsed;
  try {
    parsed = jsonDecode(argsJson);
  } on FormatException {
    parsed = null;
  }
  String? path;
  if (parsed is String) path = parsed;
  if (parsed is Map) path = parsed['path'] as String?;
  if (path == null) return 'null';
  try {
    return jsonEncode(File(path).readAsStringSync());
  } catch (_) {
    return 'null';
  }
}

/// The JS bootstrap wiring the public host-function globals.
const String hostFunctionsBootstrap = '''
(function() {
    function __unwrapHostError(result) {
        if (result !== null && result !== undefined &&
                typeof result === 'object' &&
                result.__jsError !== undefined) {
            throw new Error(result.__jsError);
        }
        return result;
    }
    globalThis.executeToolViaJava = function() {
        return __unwrapHostError(
            __executeToolViaJavaHost.apply(null, arguments));
    };
    globalThis.file_read = function() {
        return __unwrapHostError(__fileReadHost.apply(null, arguments));
    };
    // NOTE: `__loaderReadHost` is deliberately NOT wrapped/published here.
    // The require() loader captures it into its closure on install and
    // deletes the global (gh-369 review: leaving it reachable would let
    // any agent script bypass the gh-365 containment in one call).
    globalThis.set_env_variable = function() {
        return __unwrapHostError(
            __setEnvVariableHost.apply(null, arguments));
    };
})();
''';
