/// AI response parsing utilities — Dart port of Java `AIResponseParser`.
///
/// Extracts structured values (booleans with optional explanations, plain
/// booleans, JSON arrays/objects, and fenced code blocks) from raw LLM text
/// responses. Boolean parsers strip Markdown wrappers (`**false**`, `*true*`,
/// `__false__`, `` `true` ``, `"false"`, `false.`, fenced blocks) and log a
/// warning + return `false` when no valid boolean token is present.
library;

import 'dart:convert';
import 'dart:io';

/// Parsed boolean value and optional explanation from an AI response.
///
/// Mirrors Java `AIResponseParser.BooleanWithExplanation`: [explanation] is
/// populated only when [value] is `true` and trailing explanation text is
/// present.
class BooleanWithExplanation {
  /// Creates a [BooleanWithExplanation] pair.
  const BooleanWithExplanation(this.value, [this.explanation]);

  /// Parsed boolean value (`false` when the response could not be parsed).
  final bool value;

  /// Optional explanation text when [value] is `true`, otherwise `null`.
  final String? explanation;
}

/// Parses structured values from LLM text responses (Java `AIResponseParser`
/// parity).
class AIResponseParser {
  AIResponseParser._();

  static final RegExp _booleanWithExplanationPattern = RegExp(
    r'''^\s*[*_`"'\[(\>\-\s]*(true|false)(?![a-zA-Z0-9])[*_`"'\]\)\s.]*(?:[:,\-\s]\s*(.*))?$''',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _booleanTokenPattern = RegExp(
    r'(?<![a-zA-Z0-9])(true|false)(?![a-zA-Z0-9])',
    caseSensitive: false,
  );

  static final RegExp _leadingPunctuation = RegExp(r'''^[*_`"'\]\)\s.,:\-]+''');
  static final RegExp _leadingWrap = RegExp(r'''^[*_`"'\\s]+''');
  static final RegExp _trailingWrap = RegExp(r'''[*_`"'\\s]+$''');
  static final RegExp _codeBlockPattern = RegExp(
    r'```(?:\w*\s*)?\n?(.*?)\n?```',
    dotAll: true,
  );
  static final RegExp _leadingFence = RegExp(r'^```\w*\s*');
  static final RegExp _trailingFence = RegExp(r'```\s*$');

  /// Parses a boolean value and optional explanation from [response].
  ///
  /// Strips Markdown formatting (`**false**`, `*true*`, `__false__`,
  /// `` `true` ``, `"false"`, `false.`, fenced code blocks) before matching.
  /// If no valid boolean token is found, logs a warning via [warnWriter]
  /// (defaults to `stderr.writeln`) and returns
  /// `BooleanWithExplanation(false, null)`.
  static BooleanWithExplanation parseBooleanWithExplanation(
    String? response, {
    void Function(String message)? warnWriter,
  }) {
    final trimmed = _stripCodeFence(response);
    if (trimmed.isEmpty) {
      _warn(
        warnWriter,
        'WARN: No valid boolean value found in empty/null AI response; '
        'returning false.',
      );
      return const BooleanWithExplanation(false);
    }
    final direct = _matchDirectBoolean(trimmed);
    if (direct != null) return direct;

    final fallback = _matchFallbackBoolean(trimmed);
    if (fallback != null) return fallback;

    _warn(
      warnWriter,
      "WARN: No valid boolean value found in the AI response '$trimmed'; "
      'returning false.',
    );
    return const BooleanWithExplanation(false);
  }

  /// Parses a boolean value from [response].
  ///
  /// Strips Markdown formatting and returns the first `true`/`false` token.
  /// If no valid boolean value is found, logs a warning via [warnWriter]
  /// (defaults to `stderr.writeln`) and returns `false`.
  static bool parseBooleanResponse(
    String? response, {
    void Function(String message)? warnWriter,
  }) {
    final trimmed = _stripCodeFence(response);
    if (trimmed.isEmpty) {
      _warn(
        warnWriter,
        'WARN: No valid boolean value found in empty/null AI response; '
        'returning false.',
      );
      return false;
    }
    final match = _booleanTokenPattern.firstMatch(trimmed);
    if (match != null) {
      return (match.group(1) ?? '').toLowerCase() == 'true';
    }
    final substringMatch = _matchSubstringBoolean(trimmed.toLowerCase());
    if (substringMatch != null) return substringMatch;

    _warn(
      warnWriter,
      "WARN: No valid boolean value found in the AI response '$trimmed'; "
      'returning false.',
    );
    return false;
  }

  /// Extracts a JSON array (`[...]`) from [response].
  ///
  /// Throws [FormatException] when [response] is null or contains no valid
  /// JSON array.
  static List<dynamic> parseResponseAsJSONArray(String? response) {
    if (response == null) {
      throw const FormatException('Response cannot be null');
    }
    final startIndex = response.indexOf('[');
    final endIndex = response.lastIndexOf(']');
    if (startIndex != -1 && endIndex > startIndex) {
      final decoded = jsonDecode(response.substring(startIndex, endIndex + 1));
      if (decoded is List<dynamic>) return decoded;
    }
    throw const FormatException('No valid JSON array found in the response.');
  }

  /// Extracts a JSON object (`{...}`) from [response].
  ///
  /// Throws [FormatException] when [response] is null or contains no valid
  /// JSON object.
  static Map<String, dynamic> parseResponseAsJSONObject(String? response) {
    if (response == null) {
      throw const FormatException('Response cannot be null');
    }
    final startIndex = response.indexOf('{');
    final endIndex = response.lastIndexOf('}');
    if (startIndex != -1 && endIndex > startIndex) {
      final decoded = jsonDecode(response.substring(startIndex, endIndex + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    }
    throw const FormatException('No valid JSON object found in the response.');
  }

  /// Extracts the first fenced code block from [response], or returns
  /// `response.trim()` when no code block fence is present.
  ///
  /// Throws [ArgumentError] when [response] is null or empty.
  static String parseCodeResponse(String? response) {
    if (response == null || response.isEmpty) {
      throw ArgumentError('Response text cannot be null or empty.');
    }
    final match = _codeBlockPattern.firstMatch(response);
    if (match != null) {
      return (match.group(1) ?? '').trim();
    }
    return response.trim();
  }

  static BooleanWithExplanation? _matchDirectBoolean(String trimmed) {
    final match = _booleanWithExplanationPattern.firstMatch(trimmed);
    if (match == null) return null;
    final isTrue = (match.group(1) ?? '').toLowerCase() == 'true';
    if (!isTrue) return const BooleanWithExplanation(false);
    return BooleanWithExplanation(true, _cleanExplanation(match.group(2)));
  }

  static BooleanWithExplanation? _matchFallbackBoolean(String trimmed) {
    final match = _booleanTokenPattern.firstMatch(trimmed);
    if (match == null) return null;
    final isTrue = (match.group(1) ?? '').toLowerCase() == 'true';
    if (!isTrue) return const BooleanWithExplanation(false);
    final remainder =
        trimmed.substring(match.end).replaceFirst(_leadingPunctuation, '');
    return BooleanWithExplanation(true, _cleanExplanation(remainder));
  }

  static bool? _matchSubstringBoolean(String lower) {
    final trueIndex = lower.indexOf('true');
    final falseIndex = lower.indexOf('false');
    if (trueIndex != -1 && (falseIndex == -1 || trueIndex < falseIndex)) {
      return true;
    }
    if (falseIndex != -1) return false;
    return null;
  }

  static String _stripCodeFence(String? response) {
    if (response == null) return '';
    var trimmed = response.trim();
    if (trimmed.startsWith('```') && trimmed.endsWith('```')) {
      trimmed = trimmed
          .replaceFirst(_leadingFence, '')
          .replaceFirst(_trailingFence, '')
          .trim();
    }
    return trimmed;
  }

  static String? _cleanExplanation(String? rawExplanation) {
    if (rawExplanation == null) return null;
    final cleaned = rawExplanation
        .trim()
        .replaceFirst(_leadingWrap, '')
        .replaceFirst(_trailingWrap, '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static void _warn(void Function(String message)? warnWriter, String message) {
    (warnWriter ?? stderr.writeln)(message);
  }
}
