part of 'tool_bridge.dart';

// ── Console bridge ──────────────────────────────────────────────────────

/// JS bootstrap that builds the `console` object over the private host
/// functions registered by [_registerConsole].
///
/// Arguments are formatted in JS (strings as-is, other values via
/// `JSON.stringify`) and joined with spaces, matching the console
/// convention used by testRunner.js and agent scripts.
const String _consoleBootstrap = '''
(function() {
    function __joinArgs(args) {
        var parts = [];
        for (var i = 0; i < args.length; i++) {
            var a = args[i];
            if (typeof a === 'string') {
                parts.push(a);
            } else if (a instanceof Error) {
                // gh-403: JSON.stringify(new Error(m)) === '{}' (message
                // and stack are non-enumerable) — log the human-readable
                // `String(e)` form ("Error: message") so agent scripts
                // surface the error text.
                parts.push(String(a));
            } else {
                var s;
                try { s = JSON.stringify(a); } catch (e) { s = null; }
                parts.push(s === undefined || s === null ? String(a) : s);
            }
        }
        return parts.join(' ');
    }
    globalThis.console = {
        log:   function() { return __consoleLog(__joinArgs(arguments)); },
        info:  function() { return __consoleLog(__joinArgs(arguments)); },
        debug: function() { return __consoleLog(__joinArgs(arguments)); },
        warn:  function() { return __consoleWarn(__joinArgs(arguments)); },
        error: function() { return __consoleError(__joinArgs(arguments)); }
    };
})();
''';

/// Registers the `console` object on [runtime].
///
/// Host functions print synchronously to Dart's stdout/stderr and return
/// JS `undefined`, so `console.log(...)` calls chain as no-ops.
void _registerConsole(QuickjsRuntime runtime, String? prefix) {
  runtime.registerHostFunction(
      '__consoleLog', (argsJson) => _printTo(stdout, argsJson, prefix));
  runtime.registerHostFunction(
      '__consoleWarn', (argsJson) => _printTo(stderr, argsJson, prefix));
  runtime.registerHostFunction(
      '__consoleError', (argsJson) => _printTo(stderr, argsJson, prefix));
  runtime.eval(_consoleBootstrap, filename: '<console>');
}

/// Hard cap on a single `console.*` line.
///
/// The agents suite contains failure-path fixtures that print ~500 KB
/// strings (`test_setupCommands.js`: `'X'.repeat(500000)`); GitHub
/// Actions' log ingester stalls for ~6 minutes per such line while the
/// blocked stdio pipe freezes every isolate in the process (measured
/// 2026-10-01, runs 36891377431/36895373638/36898332667: ~25 s of real
/// suite work plus 2×6 min of log stalls was the entire "12-minute
/// suite"). No legitimate script output approaches this size.
const int _consoleLineLimit = 8192;

/// Prints one console line and signals JS `undefined` (Dart `null`).
String? _printTo(IOSink sink, String argsJson, String? prefix) {
  final line = _consoleArg(argsJson);
  final capped = line.length <= _consoleLineLimit
      ? line
      : '${line.substring(0, _consoleLineLimit)}'
          ' …[truncated ${line.length - _consoleLineLimit} chars]';
  sink.writeln(prefix == null ? capped : '$prefix$capped');
  return null;
}

/// Decodes the JSON-marshaled console argument back to a display string.
String _consoleArg(String argsJson) {
  try {
    final decoded = jsonDecode(argsJson);
    return decoded is String ? decoded : argsJson;
  } catch (_) {
    return argsJson;
  }
}
