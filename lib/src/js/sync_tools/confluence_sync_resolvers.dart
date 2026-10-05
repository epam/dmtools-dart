part of 'confluence_sync_tools.dart';

/// HTTP-backed [ConfluenceResolverClient] for the sync path: page lookups
/// by title (optionally in a space) and user-profile fetches, used by the
/// excerpt-include inliner and the mention resolver of the page downloader
/// (Java `Confluence.findContent` / `Confluence.profile`, dm.ai 932e0db0 /
/// bb1b51e9 parity).
class _SyncConfluenceResolverClient implements ConfluenceResolverClient {
  final _Conf _config;

  /// Creates a client resolving against [config]'s REST base URL.
  _SyncConfluenceResolverClient(this._config);

  @override
  Map<String, dynamic>? findContent(String title, {String? spaceKey}) {
    final list = _contentList(
      _titleAndSpaceResponse(_config, title, spaceKey ?? ''),
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
