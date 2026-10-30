part of 'confluence_sync_tools.dart';

/// HTTP-backed [ConfluenceResolverClient] for the sync path: page lookups
/// by title (optionally in a space) and user-profile fetches, used by the
/// excerpt-include inliner and the mention resolver of the page downloader
/// (Java `Confluence.findContent` / `Confluence.profile`, dm.ai 932e0db0 /
/// bb1b51e9 parity).
class _SyncConfluenceResolverClient implements ConfluenceResolverClient {
  final _Conf _config;
  final String? _defaultSpace;

  /// Creates a client resolving against [_config]'s REST base URL, falling
  /// back to [_defaultSpace] when no explicit space key is passed.
  _SyncConfluenceResolverClient(this._config, [this._defaultSpace]);

  @override
  Map<String, dynamic>? findContent(String title, {String? spaceKey}) {
    final effectiveSpace = (spaceKey != null && spaceKey.trim().isNotEmpty)
        ? spaceKey.trim()
        : (_defaultSpace?.trim() ?? '');
    final list = _contentList(
      _titleAndSpaceResponse(_config, title, effectiveSpace),
    );
    return list.isEmpty ? null : list.first;
  }

  @override
  String? userProfile(String accountId) {
    final resp = SyncHttpClient.get(
      '${_config.baseUrl}/user?accountId='
      '${Uri.encodeQueryComponent(accountId)}',
      headers: _config.headers,
    );
    return resp.isOk ? resp.body : null;
  }
}
