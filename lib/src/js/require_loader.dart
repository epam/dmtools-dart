/// CommonJS `require()` loader — JS bootstrap prelude for [QuickjsRuntime].
///
/// Dart port of the Java `JobJavaScriptBridge` module loader
/// (`RequireProxy` / `loadModule` / `resolveModulePath` /
/// `setCurrentScriptDirectory`, dmtools-core
/// `job/JobJavaScriptBridge.java`).
///
/// The FFI host functions marshal results through JSON, so a host-side
/// `require` could never return module exports containing functions. The
/// loader therefore lives entirely in JS: it reads module sources through
/// the existing `file_read` host function and evaluates them with `eval()`,
/// so real JS objects (functions included) flow between modules.
///
/// Semantics ported 1:1 from Java:
/// - `./x` / `../x` resolve against the current script directory, which is
///   saved/restored around each module eval (`try`/`finally`) and updated to
///   the module's own directory first, so relative requires inside modules
///   resolve correctly.
/// - Module cache is keyed by resolved path; a placeholder object is cached
///   **before** eval so circular requires terminate, and is replaced by the
///   real exports afterwards.
/// - Module code runs wrapped exactly like Java:
///   `(function() { var module = { exports: {} }; var exports =
///   module.exports; <CODE> return module.exports; })()`.
/// - On load failure the cache entry is removed and
///   `Failed to require module: <path>` is thrown; the cause message keeps
///   the Java `JavaScript file not found` substring visible.
/// - `require()` argument validation:
///   `require() expects exactly one argument (module path)`.
///
/// Known deviation: Java's `loadModule` re-enters `loadJavaScriptCode`, so a
/// require argument that is itself a URL fetches remotely; the JS prelude
/// has no synchronous fetch host function and only reads files.
library;

import 'package:quickjs_runtime/quickjs_runtime.dart';

/// Installs `globalThis.require` and `globalThis.__setScriptDirectory` on
/// [runtime].
///
/// Must run before the user script is evaluated; `require` only invokes
/// `file_read` at script runtime, so the host function may be registered
/// later.
void installRequireLoader(QuickjsRuntime runtime) {
  runtime.eval(_requireLoaderBootstrap, filename: '<require_loader>');
}

/// The loader bootstrap evaluated on the runtime.
///
/// State (`currentScriptDirectory`, `moduleCache`) lives in the closure, so
/// repeated installs each get a fresh cache — matching the Java bridge,
/// whose cache is cleared on `close()`.
const String _requireLoaderBootstrap = '''
(function() {
    var currentScriptDirectory = '';
    var moduleCache = {};

    function scriptDirOf(path) {
        if (typeof path !== 'string' || path.indexOf('/') === -1) {
            return '';
        }
        var lastSlash = path.lastIndexOf('/');
        return lastSlash > 0 ? path.substring(0, lastSlash) : '';
    }

    function normalizePath(path) {
        var absolute = path.charAt(0) === '/';
        var segments = path.split('/');
        var out = [];
        for (var i = 0; i < segments.length; i++) {
            var segment = segments[i];
            if (segment === '' || segment === '.') continue;
            if (segment === '..') {
                if (out.length > 0 && out[out.length - 1] !== '..') {
                    out.pop();
                } else if (!absolute) {
                    out.push('..');
                }
                continue;
            }
            out.push(segment);
        }
        var joined = out.join('/');
        return absolute ? '/' + joined : joined;
    }

    function resolveModulePath(modulePath) {
        if (modulePath.indexOf('./') === 0 ||
                modulePath.indexOf('../') === 0) {
            if (currentScriptDirectory) {
                return normalizePath(
                    currentScriptDirectory + '/' + modulePath);
            }
        }
        return modulePath;
    }

    function readModuleCode(resolvedPath) {
        var content = file_read({ path: resolvedPath });
        if (content === null || content === undefined) {
            throw new Error('JavaScript file not found in resources or ' +
                'filesystem: ' + resolvedPath);
        }
        return content;
    }

    function wrapModuleCode(code) {
        return '(function() { var module = { exports: {} }; ' +
            'var exports = module.exports;\\n' + code +
            '\\nreturn module.exports; })()';
    }

    function loadModule(modulePath) {
        var resolvedPath = resolveModulePath(modulePath);
        if (Object.prototype.hasOwnProperty.call(
                moduleCache, resolvedPath)) {
            return moduleCache[resolvedPath];
        }
        var savedScriptDirectory = currentScriptDirectory;
        // Placeholder cached before eval: circular requires get it and
        // terminate instead of recursing (Java loadModule parity).
        var placeholder = {};
        moduleCache[resolvedPath] = placeholder;
        try {
            currentScriptDirectory = scriptDirOf(resolvedPath);
            var moduleExports =
                eval(wrapModuleCode(readModuleCode(resolvedPath)));
            moduleCache[resolvedPath] = moduleExports;
            return moduleExports;
        } catch (e) {
            delete moduleCache[resolvedPath];
            var cause = (e && e.message) ? e.message : String(e);
            throw new Error('Failed to require module: ' + modulePath +
                ' (' + cause + ')');
        } finally {
            currentScriptDirectory = savedScriptDirectory;
        }
    }

    globalThis.require = function(modulePath) {
        if (arguments.length !== 1) {
            throw new Error(
                'require() expects exactly one argument (module path)');
        }
        return loadModule(modulePath);
    };

    globalThis.__setScriptDirectory = function(path) {
        currentScriptDirectory = scriptDirOf(path);
    };
})();
''';
