/// Length-preserving JS scrub for [AgentPackCompiler]'s closure scan
/// (gh-371) — see `AgentPackCompiler.scrubForScan` for the contract.
library;

/// Character codes used by the scrubber (named for the magic-constants
/// gate — the comparisons read as chars, not numbers).
const int _slash = 0x2f;
const int _star = 0x2a;
const int _quote = 0x27;
const int _dquote = 0x22;
const int _backtick = 0x60;
const int _backslash = 0x5c;
const int _dollar = 0x24;
const int _openBrace = 0x7b;
const int _closeBrace = 0x7d;
const int _newline = 0x0a;
const int _cr = 0x0d;
const int _tab = 0x09;
const int _space = 0x20;
const int _openClass = 0x5b;
const int _closeClass = 0x5d;
const int _underscore = 0x5f;
const int _dot = 0x2e;
const int _lowerA = 0x61;
const int _lowerZ = 0x7a;
const int _upperA = 0x41;
const int _upperZ = 0x5a;
const int _digit0 = 0x30;
const int _digit9 = 0x39;

/// Blanks the CONTENTS of comments, string/template literals, and regex
/// literals while preserving every byte count (structure chars — quotes,
/// newlines — stay), so `require('./x.js')` survives as
/// `require('       ')` at identical offsets and real code is
/// distinguishable from embedded worker-source strings.
String scrubJsForScan(String src) => _Scrubber(src).run();

class _Scrubber {
  _Scrubber(String src) : chars = src.codeUnits.toList();

  final List<int> chars;
  int i = 0;

  /// Last significant code char (0 = none yet) — drives regex-vs-division.
  int _prevSig = 0;
  String _lastWord = '';
  bool _inWord = false;

  /// Brace balance per open `${` interpolation (nested `{}` inside the
  /// interpolation code must not close it early).
  final List<int> _interpBraces = [];

  /// Punctuation after which a `/` opens a regex (expression position).
  static final _regexStarterChars = RegExp(r'[(\[,;=!?:&|+\-%<>^~]');

  /// Keywords after which a `/` opens a regex literal — division can
  /// never directly follow these.
  static const _regexPositionKeywords = {
    'return',
    'typeof',
    'instanceof',
    'in',
    'of',
    'new',
    'delete',
    'void',
    'case',
    'do',
    'else',
    'yield',
    'await',
    'throw',
  };

  String run() {
    while (i < chars.length) {
      _dispatch(chars[i]);
    }
    return String.fromCharCodes(chars);
  }

  /// One state-machine step for the char at [i].
  void _dispatch(int c) {
    if (_isWhitespace(c)) {
      i++;
    } else if (c == _closeBrace && _closesInterpolation()) {
      // Handled inside _closesInterpolation (resumes the template).
    } else if (c == _slash && _tryConsumeSlash()) {
      // Consumed as comment or regex literal.
    } else if (_isQuoteCode(c) && _tryConsumeLiteral()) {
      // Consumed a string/template literal.
    } else {
      _trackCode(c);
    }
  }

  static bool _isWhitespace(int c) =>
      c == _newline || c == _cr || c == _tab || c == _space;

  static bool _isQuoteCode(int c) =>
      c == _quote || c == _dquote || c == _backtick;

  static bool _isWordChar(int c) =>
      (c >= _lowerA && c <= _lowerZ) ||
      (c >= _upperA && c <= _upperZ) ||
      (c >= _digit0 && c <= _digit9) ||
      c == _underscore ||
      c == _dollar;

  void _blank(int at) => chars[at] = _space;

  bool _regexAllowed() =>
      _prevSig == 0 ||
      String.fromCharCode(_prevSig).contains(_regexStarterChars) ||
      _regexPositionKeywords.contains(_lastWord);

  /// True when [c] ends the current token for context tracking (escapes
  /// and regex bodies are opaque to word tracking).
  void _resetToken(int sig) {
    _prevSig = sig;
    _lastWord = '';
    _inWord = false;
  }

  /// A `}` closing an interpolation: pops one `${` level and resumes the
  /// surrounding template literal. Returns true when handled.
  bool _closesInterpolation() {
    if (_interpBraces.isEmpty) return false;
    if (_interpBraces.last > 0) {
      _interpBraces[_interpBraces.length - 1]--;
      _trackCode(_closeBrace);
      return true;
    }
    _interpBraces.removeLast();
    i++;
    _consumeLiteral(_backtick);
    _resetToken(_backtick);
    return true;
  }

  /// Consumes `/`-prefixed tokens (comments, regex literals). Returns true
  /// when the slash was consumed as one of those, false for division
  /// (which falls through to code tracking).
  bool _tryConsumeSlash() {
    if (i + 1 >= chars.length) return false;
    final next = chars[i + 1];
    if (next == _slash) return _consumeLineComment();
    if (next == _star) return _consumeBlockComment();
    if (_regexAllowed()) return _consumeRegexLiteral();
    return false; // division
  }

  bool _consumeLineComment() {
    while (i < chars.length && chars[i] != _newline) {
      _blank(i++);
    }
    return true;
  }

  bool _consumeBlockComment() {
    _blank(i++);
    _blank(i++);
    while (i < chars.length) {
      if (_atBlockCommentEnd()) {
        _blank(i++);
        _blank(i++);
        break;
      }
      if (chars[i] != _newline) _blank(i);
      i++;
    }
    return true;
  }

  bool _atBlockCommentEnd() =>
      chars[i] == _star && i + 1 < chars.length && chars[i + 1] == _slash;

  /// Blanks a regex literal through the closing unescaped `/` (one outside
  /// a `[...]` character class) plus any trailing flag letters. Bail at EOL
  /// for an unterminated regex.
  bool _consumeRegexLiteral() {
    _blank(i++);
    var inClass = false;
    while (i < chars.length) {
      final rc = chars[i];
      if (_tryConsumeEscapePair()) continue;
      if (rc == _openClass) inClass = true;
      if (rc == _closeClass) inClass = false;
      if (rc == _slash && !inClass) {
        _blank(i++);
        _consumeRegexFlags();
        break;
      }
      if (rc == _newline) break;
      _blank(i++);
    }
    _resetToken(_slash);
    return true;
  }

  /// Blanks trailing regex flag letters (`/x/gi` — the `gi`).
  void _consumeRegexFlags() {
    while (i < chars.length && chars[i] >= _lowerA && chars[i] <= _lowerZ) {
      _blank(i++);
    }
  }

  /// Consumes a quote-opened literal when [c] really opens one (an odd
  /// backslash run before it means it is an escaped character instead).
  bool _tryConsumeLiteral() {
    if (_precededByOddBackslashRun()) {
      _blank(i - 1);
      _blank(i++);
      return true;
    }
    _consumeLiteral(chars[i]);
    _resetToken(chars[i]);
    return true;
  }

  bool _precededByOddBackslashRun() {
    var run = 0;
    var bs = i;
    while (bs > 0 && chars[bs - 1] == _backslash) {
      run++;
      bs--;
    }
    return run.isOdd;
  }

  /// Consumes a string/template literal from the opening quote (kept):
  /// blanks contents, keeps the closing quote, ends unterminated
  /// single/double literals at EOL. `${` re-enters code state (tracked by
  /// [_interpBraces]) and the template resumes after the matching `}`.
  void _consumeLiteral(int quote) {
    final isTemplate = quote == _backtick;
    i++;
    while (i < chars.length) {
      final c = chars[i];
      if (_tryConsumeEscapePair()) continue;
      if (isTemplate && _entersInterpolation()) return;
      if (c == quote) {
        i++;
        return;
      }
      if (c == _newline && !isTemplate) return;
      _blank(i++);
    }
  }

  /// On `${`: opens an interpolation level and leaves the main loop in
  /// code state.
  bool _entersInterpolation() {
    if (chars[i] != _dollar || i + 1 >= chars.length) return false;
    if (chars[i + 1] != _openBrace) return false;
    _interpBraces.add(0);
    i += 2;
    return true;
  }

  /// Blanks a `\\x` escape pair (both bytes) when present at [i].
  bool _tryConsumeEscapePair() {
    if (chars[i] != _backslash || i + 1 >= chars.length) return false;
    _blank(i++);
    _blank(i++);
    return true;
  }

  /// Word/punctuation context tracking for regex-vs-division decisions.
  void _trackCode(int c) {
    if (c == _openBrace && _interpBraces.isNotEmpty) {
      _interpBraces[_interpBraces.length - 1]++;
    }
    if (_isWordChar(c)) {
      _trackWord(c);
    } else {
      _trackPunct(c);
    }
    i++;
  }

  void _trackWord(int c) {
    _lastWord =
        _inWord ? _lastWord + String.fromCharCode(c) : String.fromCharCode(c);
    _inWord = true;
    // After a word only the keyword set can put a `/` in expression
    // position — identifiers END expressions (division follows).
    _prevSig = _lowerA;
  }

  void _trackPunct(int c) {
    _inWord = false;
    _lastWord = c == _dot ? _lastWord : '';
    _prevSig = c;
  }
}
