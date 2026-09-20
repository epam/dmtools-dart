/// Figma design-URL parsing helpers — Java `FigmaClient` parity.
///
/// Pure functions porting the protected/static URL helpers of the Java
/// integration client: file-key extraction from a design URL, query
/// parameter extraction, and team/project ID coercion (raw numeric ID or
/// URL containing `/team/<id>` / `/project/<id>`).
library;

/// Returns the Figma file key from a design [url] — the third path
/// segment (`https://www.figma.com/file/<key>/…`).
///
/// Java `parseFileId`: `path.split("/")` index 2. Throws [StateError]
/// when the URL cannot be parsed.
String figmaParseFileId(String url) {
  // Java `URI.getPath()` keeps the leading empty segment, so the file key
  // sits at split index 2 — mirror that exactly.
  final path = Uri.parse(url).path;
  final segments = path.split('/');
  if (segments.length < 3) {
    throw StateError('Invalid Figma url: $url');
  }
  return segments[2];
}

/// Extracts query parameter [paramName] from [url].
///
/// Java `extractValueByParameter`: splits the raw query on `&`/`=` and
/// returns the first exact key match. Throws [StateError] (`Invalid url`)
/// when the parameter is absent — callers that treat a missing parameter
/// as optional (e.g. `node-id`) catch this.
String figmaExtractQueryParam(String url, String paramName) {
  final query = Uri.parse(url).query;
  if (query.isNotEmpty) {
    for (final param in query.split('&')) {
      final keyValue = param.split('=');
      if (keyValue.length == 2 && keyValue[0] == paramName) {
        return keyValue[1];
      }
    }
  }
  throw StateError('Invalid url: missing $paramName in $url');
}

/// Extracts a numeric Figma team ID from either a raw ID or a URL
/// containing a `/team/<teamId>` path segment.
///
/// Java `extractTeamId`.
String figmaExtractTeamId(String teamIdOrUrl) {
  return _extractId(teamIdOrUrl, 'team');
}

/// Extracts a numeric Figma project ID from either a raw ID or a URL
/// containing a `/project/<projectId>` path segment.
///
/// Java `extractProjectId`.
String figmaExtractProjectId(String projectIdOrUrl) {
  return _extractId(projectIdOrUrl, 'project');
}

/// Shared raw-ID-or-URL coercion for [kind] (`team` / `project`).
String _extractId(String idOrUrl, String kind) {
  final trimmed = idOrUrl.trim();
  if (trimmed.isEmpty) {
    throw StateError('Invalid url');
  }
  if (RegExp(r'^\d+$').hasMatch(trimmed)) {
    return trimmed;
  }
  final match = RegExp('$kind/(\\d+)').firstMatch(trimmed);
  if (match != null) {
    return match.group(1)!;
  }
  throw StateError(
    'Invalid url: could not extract a Figma $kind ID. Provide either a '
    'numeric $kind ID or a URL containing /$kind/<id>.',
  );
}

/// Normalizes a `node-id` query value (`1-2` → `1:2`).
///
/// Figma API responses key nodes by colon-separated IDs while design URLs
/// carry dash-separated ones (Java `nodeId.replace("-", ":")`).
String figmaColonNodeId(String nodeId) => nodeId.replaceAll('-', ':');

/// Unescapes HTML-escaped ampersands in a design URL.
///
/// Java `href.replaceAll("&amp;", "&")` — hrefs copied from rendered HTML
/// carry the escaped form.
String figmaCleanHref(String href) => href.replaceAll('&amp;', '&');
