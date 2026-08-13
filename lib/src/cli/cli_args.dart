/// CLI argument pre-scan — Dart port of the shell-layer pre-scan from
/// `dmtools.sh`.
///
/// Separates global flags (`--data`, `--file`, `--verbose`, ...) from the
/// command and its positional arguments before the command-specific
/// processor runs.
library;

/// Parsed CLI arguments after the shell-layer pre-scan.
///
/// Immutable snapshot produced by [ParsedCliArgs.parse].
class ParsedCliArgs {
  /// The first non-flag token (e.g. `run`, `list`, `doctor`).
  final String command;

  /// Remaining non-flag tokens after [command].
  final List<String> positional;

  /// Value of `--data <value>`.
  final String? data;

  /// Value of `--file <value>`.
  final String? file;

  /// Output format from `--output`, `--toon`, or `--mini`.
  final String? outputFormat;

  final _VerbosityFlags _verbosity;

  /// True when `--verbose` or `--debug` was passed.
  bool get verbose => _verbosity.verbose;

  /// True when `--debug` was passed.
  bool get debug => _verbosity.debug;

  /// True when `--quiet` was passed.
  bool get quiet => _verbosity.quiet;

  /// Creates parsed CLI args from the [parse] factory.
  const ParsedCliArgs._({
    required this.command,
    required this.positional,
    required this.data,
    required this.file,
    required this.outputFormat,
    required _VerbosityFlags verbosity,
  }) : _verbosity = verbosity;

  /// Parses raw CLI args into structured form.
  ///
  /// Walks the token list once, consuming value-flags (`--data foo`,
  /// `--output=bar`) and boolean flags (`--verbose`, `--quiet`), and
  /// collecting the first non-flag token as [command] and the rest as
  /// [positional].
  factory ParsedCliArgs.parse(List<String> args) {
    return _ArgScanner(args).scan();
  }
}

/// Immutable group of verbosity/level boolean flags.
class _VerbosityFlags {
  const _VerbosityFlags({
    this.verbose = false,
    this.debug = false,
    this.quiet = false,
  });

  final bool verbose;
  final bool debug;
  final bool quiet;
}

/// Private single-pass scanner that walks the raw arg list.
class _ArgScanner {
  _ArgScanner(this._args);

  final List<String> _args;

  String? _data;
  String? _file;
  bool _verbose = false;
  bool _debug = false;
  bool _quiet = false;
  String? _outputFormat;
  final List<String> _nonFlags = <String>[];

  /// Runs the scan and returns the parsed result.
  ParsedCliArgs scan() {
    var i = 0;
    while (i < _args.length) {
      i = _processArg(i);
    }
    return _buildResult();
  }

  /// Processes the arg at index [i], returning the next index to visit.
  int _processArg(int i) {
    final arg = _args[i];
    if (_tryInlineValue(arg)) return i + 1;
    final consumed = _trySeparateValue(i);
    if (consumed > 0) return i + consumed;
    _applyBooleanOrPositional(arg);
    return i + 1;
  }

  /// Handles `--flag=value` form. Returns `true` when the flag was consumed.
  bool _tryInlineValue(String arg) {
    if (!arg.startsWith('--') || !arg.contains('=')) return false;
    final eq = arg.indexOf('=');
    final flag = arg.substring(0, eq);
    final value = arg.substring(eq + 1);
    return _applyValueFlag(flag, value);
  }

  /// Handles `--flag value` form. Returns args consumed (0 if not handled).
  int _trySeparateValue(int i) {
    final arg = _args[i];
    if (!arg.startsWith('--') || arg.contains('=')) return 0;
    if (!_isValueFlag(arg)) return 0;
    final value = i + 1 < _args.length ? _args[i + 1] : '';
    _applyValueFlag(arg, value);
    return 2;
  }

  /// Applies a boolean flag or collects a non-flag positional token.
  void _applyBooleanOrPositional(String arg) {
    switch (arg) {
      case '--verbose':
        _verbose = true;
      case '--debug':
        _verbose = true;
        _debug = true;
      case '--quiet':
        _quiet = true;
      case '--toon':
        _outputFormat = 'toon';
      case '--mini':
        _outputFormat = 'mini';
      default:
        if (!arg.startsWith('--')) {
          _nonFlags.add(arg);
        }
    }
  }

  /// Returns `true` when [flag] expects a value argument.
  bool _isValueFlag(String flag) =>
      flag == '--data' || flag == '--file' || flag == '--output';

  /// Sets the appropriate field for a value-flag. Returns `true` if recognised.
  bool _applyValueFlag(String flag, String value) {
    switch (flag) {
      case '--data':
        _data = value;
        return true;
      case '--file':
        _file = value;
        return true;
      case '--output':
        _outputFormat = value;
        return true;
      default:
        return false;
    }
  }

  /// Builds the immutable [ParsedCliArgs] from accumulated state.
  ParsedCliArgs _buildResult() {
    final command = _nonFlags.isNotEmpty ? _nonFlags.first : '';
    final positional = _nonFlags.skip(1).toList(growable: false);
    return ParsedCliArgs._(
      command: command,
      positional: positional,
      data: _data,
      file: _file,
      outputFormat: _outputFormat,
      verbosity: _VerbosityFlags(
        verbose: _verbose,
        debug: _debug,
        quiet: _quiet,
      ),
    );
  }
}
