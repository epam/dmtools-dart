part of 'confluence_markdown.dart';

/// Confluence storage resolvers: excerpt-include materialization and user
/// mention resolution, ported 1:1 from the Java `ConfluenceExcerptInliner`
/// and `ConfluenceMentionResolver` (dm.ai 932e0db0 / bb1b51e9, gh-347).
/// Both classes work against [ConfluenceResolverClient] callbacks so they
/// unit-test without a live Confluence instance; the sync bridge injects
/// an HTTP-backed client (see `confluence_sync_resolvers.dart`).

/// Client callbacks the storage resolvers need (the subset of the Java
/// `Confluence` client the resolvers call).
abstract class ConfluenceResolverClient {
  /// First content matching [title] in [spaceKey] — or in any space when
  /// [spaceKey] is `null` (Java `Confluence.findContent` variants).
  Map<String, dynamic>? findContent(String title, {String? spaceKey});

  /// Raw JSON profile of the user [accountId] (Java `Confluence.profile`);
  /// `null` (or a throw) when the lookup fails.
  String? userProfile(String accountId);
}

/// Space key of a Confluence content object (Java `Content.getSpaceKey`):
/// read from the expanded `space` object or, when only a link is
/// available, from the last segment of `_expandable.space`; `null` when
/// unknown.
String? confluenceSpaceKeyOf(Map<String, dynamic> content) {
  final space = content['space'];
  if (space is Map && _nonBlank(space['key'])) return space['key'] as String;
  final expandable = content['_expandable'];
  if (expandable is Map && _nonBlank(expandable['space'])) {
    final link = expandable['space'] as String;
    return link.split('/').last;
  }
  return null;
}

/// Whether [value] is a non-blank string (local helper, mirrors Java
/// `String.isBlank` negation).
bool _nonBlank(dynamic value) => value is String && value.trim().isNotEmpty;

/// Materializes `excerpt-include` and `table-excerpt-include` macros in
/// Confluence storage format (Java `ConfluenceExcerptInliner`).
///
/// Both macros only store configuration (target page and excerpt name);
/// the transcluded content lives on the target page inside `excerpt` /
/// `table-excerpt` macros. [inline] replaces every resolvable include
/// macro with the body of the matching excerpt so the subsequent Markdown
/// conversion contains the real content.
///
/// Lookup rules (Java parity):
/// - the target page is resolved in the `ri:space-key` of its link,
///   otherwise in the space of the page containing the macro, otherwise
///   via the default lookup,
/// - excerpt names are compared case-insensitively with whitespace and
///   `&nbsp;` normalized,
/// - a blank name selects the unnamed excerpts of the target page, or all
///   excerpts of the matching kind when none is unnamed,
/// - nested includes are resolved up to [maxDepth] levels with cycle
///   protection,
/// - an include that cannot be resolved is left unchanged.
class ConfluenceExcerptInliner {
  /// Maximum nesting depth for include resolution (Java `MAX_DEPTH`).
  static const int maxDepth = 3;

  final ConfluenceResolverClient _client;

  /// Creates an inliner resolving pages through [client].
  ConfluenceExcerptInliner(this._client);

  final Map<String, Map<String, dynamic>?> _pageCache = {};

  /// Returns [storageHtml] with every resolvable include macro replaced by
  /// excerpt content; [pageSpaceKey] is the space key of the page being
  /// converted (`null` when unknown).
  String inline(String storageHtml, String? pageSpaceKey) {
    if (!storageHtml.contains('excerpt-include')) return storageHtml;
    return _inlineNested(storageHtml, pageSpaceKey, 0, <String>{});
  }

  /// Depth-limited include resolution over [html] (Java private `inline`).
  String _inlineNested(
    String html,
    String? spaceKey,
    int level,
    Set<String> path,
  ) {
    if (level >= maxDepth || !html.contains('excerpt-include')) return html;
    final result = StringBuffer();
    var last = 0;
    for (final m in _includeMacroPattern.allMatches(html)) {
      result.write(html.substring(last, m.start));
      result.write(_resolveGuarded(m.group(0)!, spaceKey, level, path));
      last = m.end;
    }
    result.write(html.substring(last));
    return result.toString();
  }

  /// Resolves one include macro, keeping it verbatim on any failure
  /// (Java: warn + keep the macro).
  String _resolveGuarded(
    String macro,
    String? spaceKey,
    int level,
    Set<String> path,
  ) {
    try {
      return _resolveInclude(macro, spaceKey, level, path) ?? macro;
    } catch (_) {
      return macro;
    }
  }

  /// One include macro's replacement, or `null` when unresolvable.
  String? _resolveInclude(
    String macro,
    String? spaceKey,
    int level,
    Set<String> path,
  ) {
    final target = _includeTarget(macro, spaceKey);
    if (target == null) return null;
    final (:title, :targetSpace, :name) = target;
    final page = _findPage(title, targetSpace);
    final storage = _storageValueOf(page);
    if (page == null || storage == null) return null;

    final kind = _macroNameOf(macro)!.toLowerCase() == 'table-excerpt-include'
        ? 'table-excerpt'
        : 'excerpt';
    final visitKey = '${page['id']}|${_normalizeExcerptName(name)}|$kind';
    if (!path.add(visitKey)) return null; // cycle
    try {
      final bodies = _excerptBodies(storage, kind, name);
      if (bodies.isEmpty) return null;
      final targetPageSpace = confluenceSpaceKeyOf(page) ?? targetSpace;
      final sb = StringBuffer();
      for (final body in bodies) {
        sb.write(_inlineNested(body, targetPageSpace, level + 1, path));
      }
      return sb.toString();
    } finally {
      path.remove(visitKey);
    }
  }

  /// The include macro's target title, space, and excerpt name; `null`
  /// when the macro carries no usable page reference.
  ({String title, String? targetSpace, String name})? _includeTarget(
    String macro,
    String? spaceKey,
  ) {
    final pageTag = _firstOpenTag(macro, 'ri:page');
    var title = pageTag == null ? null : _attrOf(pageTag, 'ri:content-title');
    var targetSpace = pageTag == null ? null : _attrOf(pageTag, 'ri:space-key');
    title = _nonBlank(title) ? title : _macroParamText(macro, 'page-title');
    if (!_nonBlank(title)) return null;
    if (!_nonBlank(targetSpace)) targetSpace = spaceKey;
    return (title: title!, targetSpace: targetSpace, name: _macroParamText(macro, 'name'));
  }

  /// Cached page lookup: the space-specific search first, then the
  /// default lookup (Java `findPage`).
  Map<String, dynamic>? _findPage(String title, String? spaceKey) {
    final cacheKey = '${spaceKey ?? ''}|$title';
    if (_pageCache.containsKey(cacheKey)) return _pageCache[cacheKey];
    Map<String, dynamic>? page;
    if (_nonBlank(spaceKey)) {
      page = _client.findContent(title, spaceKey: spaceKey);
    }
    page ??= _client.findContent(title);
    return _pageCache[cacheKey] = page;
  }
}

/// The `body.storage.value` of a content object; `null` when absent.
String? _storageValueOf(Map<String, dynamic>? page) {
  final body = page?['body'];
  if (body is! Map) return null;
  final storage = body['storage'];
  if (storage is! Map || storage['value'] is! String) return null;
  return storage['value'] as String;
}

/// Excerpt bodies of [storageHtml] for macros of [kind], mirroring Java
/// `extractExcerptBodies`: a non-empty [requestedName] selects named
/// excerpts; a blank one selects the unnamed excerpts, or all excerpts of
/// the kind when none is unnamed.
List<String> _excerptBodies(
  String storageHtml,
  String kind,
  String requestedName,
) {
  final named = <String>[];
  final unnamed = <String>[];
  final all = <String>[];
  final wanted = _normalizeExcerptName(requestedName);
  for (final macro in _rawMacrosOfKind(storageHtml, kind)) {
    final body = _firstTagInner(macro, 'ac:rich-text-body');
    if (body == null) continue;
    final name = _normalizeExcerptName(_macroParamText(macro, 'name'));
    all.add(body);
    if (name.isEmpty) unnamed.add(body);
    if (wanted.isNotEmpty && name == wanted) named.add(body);
  }
  if (wanted.isNotEmpty) return named;
  return unnamed.isEmpty ? all : unnamed;
}

/// Case/whitespace/`&nbsp;`-insensitive excerpt name key (Java
/// `normalize`).
String _normalizeExcerptName(String name) => unescapeXml(name)
    .replaceAll('\u00a0', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// Every `ac:structured-macro` element of the given `ac:name` [kind] in
/// [html], with raw inner HTML (depth-aware scan — macros nested inside
/// another macro's body are reported like Jsoup's `getElementsByTag`).
List<String> _rawMacrosOfKind(String html, String kind) {
  final found = <String>[];
  final nameStack = <String>[];
  final startStack = <int>[];
  final token = RegExp(
    r'</?ac:structured-macro\b[^>]*>',
    dotAll: true,
    caseSensitive: false,
  );
  for (final m in token.allMatches(html)) {
    final tag = m.group(0)!;
    if (tag.startsWith('</')) {
      if (nameStack.isEmpty) continue;
      final name = nameStack.removeLast();
      final start = startStack.removeLast();
      if (name.toLowerCase() == kind.toLowerCase()) {
        found.add(html.substring(start, m.start));
      }
      continue;
    }
    final name = _macroNameOf(tag);
    if (tag.endsWith('/>')) {
      if (name != null && name.toLowerCase() == kind.toLowerCase()) {
        found.add('');
      }
    } else {
      nameStack.add(name ?? '');
      startStack.add(m.end);
    }
  }
  return found;
}

/// Include macro match: `<ac:structured-macro ac:name="(table-)?excerpt-include"…/>`
/// or with a full body (Java `INCLUDE_MACRO`).
final _includeMacroPattern = RegExp(
  r'<ac:structured-macro\b[^>]*ac:name="(?:excerpt-include|table-excerpt-include)"[^>]*?(?:/>|>.*?</ac:structured-macro\s*>)',
  dotAll: true,
);

/// The `ac:name` attribute of an `ac:structured-macro` open [tag].
String? _macroNameOf(String tag) => _attrOf(tag, 'ac:name');

/// The full text of the first open `<[tag]>` in [html]; `null` when absent.
String? _firstOpenTag(String html, String tag) => RegExp(
      '<$tag\\b[^>]*>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html)?.group(0);

/// The value of attribute [attr] inside a raw [tag]; `null` when absent.
String? _attrOf(String tag, String attr) => RegExp(
      '$attr\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(tag)?.group(1);

/// The raw inner HTML of the first `<[tag]>…</[tag]>` element of [html];
/// `null` when absent.
String? _firstTagInner(String html, String tag) => RegExp(
      '<$tag\\b[^>]*>(.*?)</$tag\\s*>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html)?.group(1);

/// The text of the `ac:parameter` named [paramName] inside a raw macro
/// [macroXml] (Jsoup `parameter()` parity): concatenated parameter text,
/// or `''` when the parameter is absent.
String _macroParamText(String macroXml, String paramName) {
  final paramTag = RegExp(
    r'<ac:parameter\b[^>]*>(.*?)</ac:parameter\s*>',
    dotAll: true,
    caseSensitive: false,
  );
  for (final m in paramTag.allMatches(macroXml)) {
    final open = m.group(0)!.substring(0, m.group(0)!.indexOf('>') + 1);
    if (_attrOf(open, 'ac:name') == paramName) return _plainText(m.group(1)!);
  }
  return '';
}

/// Jsoup `Element.text()` equivalent for a storage fragment: tags
/// stripped, entities unescaped (`&nbsp;` included — Jsoup decodes the
/// full HTML entity set).
String _plainText(String html) =>
    unescapeXml(html.replaceAll(RegExp(r'<[^>]*>'), ''))
        .replaceAll('&nbsp;', ' ');

/// Replaces user mentions (`<ac:link><ri:user ri:account-id="…"/></ac:link>`)
/// in storage format with `@Display Name` (Java `ConfluenceMentionResolver`,
/// dm.ai bb1b51e9). Storage only carries the account id, so without this
/// step mentions end up as an anonymous "link" in the converted text.
/// Unresolvable mentions are left untouched; lookups are cached (including
/// failed ones).
class ConfluenceMentionResolver {
  final ConfluenceResolverClient _client;

  /// Creates a resolver fetching profiles through [client].
  ConfluenceMentionResolver(this._client);

  final Map<String, String?> _nameCache = {};

  /// Returns [storageHtml] with every resolvable mention replaced by the
  /// user's `@Display Name` (XML-escaped).
  String resolve(String storageHtml) {
    if (!storageHtml.contains('ri:user')) return storageHtml;
    final result = StringBuffer();
    var last = 0;
    for (final m in _userMentionPattern.allMatches(storageHtml)) {
      result.write(storageHtml.substring(last, m.start));
      final name = _displayName(m.group(1)!);
      result.write(name != null ? _escapeMention('@$name') : m.group(0));
      last = m.end;
    }
    result.write(storageHtml.substring(last));
    return result.toString();
  }

  /// The cached display name for [accountId]; failed lookups cache `null`
  /// so a broken profile endpoint is hit only once per mention.
  String? _displayName(String accountId) {
    if (_nameCache.containsKey(accountId)) return _nameCache[accountId];
    String? name;
    try {
      final profile = _client.userProfile(accountId);
      if (_nonBlank(profile)) {
        final decoded = jsonDecode(profile!);
        if (decoded is Map) {
          final value = decoded['displayName']?.toString().trim() ?? '';
          if (value.isNotEmpty) name = value;
        }
      }
    } catch (_) {
      // Unresolvable mention — keep it verbatim (Java parity).
    }
    return _nameCache[accountId] = name;
  }
}

/// A user mention link carrying the `ri:account-id` (Java
/// `USER_MENTION`).
final _userMentionPattern = RegExp(
  r'<ac:link[^>]*>\s*<ri:user\b[^>]*?ri:account-id="([^"]+)"[^>]*?/?>\s*(?:</ri:user>)?\s*</ac:link>',
  dotAll: true,
);

/// XML-escapes resolved mention text for re-embedding into storage (Java
/// `escape`: `&`, `<`, `>`).
String _escapeMention(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
