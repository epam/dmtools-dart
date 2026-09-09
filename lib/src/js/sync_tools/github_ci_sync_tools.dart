/// CI-status, PR-activity, and release-asset sync executors — the Java
/// `GitHub.java` tools the sync surface was missing (dm.ai #543 review).
///
/// Part of the `github_sync_tools.dart` library so the handlers share the
/// sync config/HTTP helpers.
part of 'github_sync_tools.dart';

/// Synchronous executors for the CI/PR-activity tools.
class GitHubCiSyncTools {
  /// Creates the CI/PR-activity sync tooling.
  const GitHubCiSyncTools();

  /// Executors, keyed by tool name.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'github_create_check_run': (args) => _run(_createCheckRun, args),
        'github_update_check_run': (args) => _run(_updateCheckRun, args),
        'github_create_commit_status': (args) =>
            _run(_createCommitStatus, args),
        'github_get_workflow_run': (args) => _run(_getWorkflowRun, args),
        'github_repository_dispatch': (args) =>
            _run(_repositoryDispatch, args),
        'github_update_pr_comment': (args) => _run(_updatePrComment, args),
        'github_delete_pr_comment': (args) => _run(_deletePrComment, args),
        'github_get_pr_activities': (args) => _run(_getPrActivities, args),
        'github_list_prs_filtered': (args) => _run(_listPrsFiltered, args),
        'github_list_release_assets': (args) =>
            _run(_listReleaseAssets, args),
        'github_delete_release_asset': (args) =>
            _run(_deleteReleaseAsset, args),
        'github_get_commits_from_branches': (args) =>
            _run(_getCommitsFromBranches, args),
      };

  /// `github_create_check_run` — POST `repos/{w}/{r}/check-runs`.
  String _createCheckRun(GhSyncConfig c, Map<String, dynamic> a) {
    final body = <String, dynamic>{
      'name': syncAsStr(a['name']),
      'head_sha': syncAsStr(a['headSha']),
    };
    _putIfNotBlank(body, 'status', a['status']);
    _putIfNotBlank(body, 'external_id', a['externalId']);
    final title = a['title'];
    final summary = a['summary'];
    if (title != null || summary != null) {
      body['output'] = {
        'title': title != null ? syncAsStr(title) : syncAsStr(a['name']),
        'summary': summary != null ? syncAsStr(summary) : '',
        if (!syncIsBlank(a['text'])) 'text': syncAsStr(a['text']),
      };
    }
    return _postJson(
      c,
      '${c.baseUrl}/${_repoSeg(a)}/check-runs',
      body,
    );
  }

  /// `github_update_check_run` — PATCH `repos/{w}/{r}/check-runs/{id}`.
  String _updateCheckRun(GhSyncConfig c, Map<String, dynamic> a) {
    final body = <String, dynamic>{'status': syncAsStr(a['status'])};
    _putIfNotBlank(body, 'conclusion', a['conclusion']);
    final title = a['title'];
    final summary = a['summary'];
    if (title != null || summary != null) {
      body['output'] = {
        if (title != null) 'title': syncAsStr(title),
        if (summary != null) 'summary': syncAsStr(summary),
        if (syncIsBlank(a['text'])) 'text': syncAsStr(a['text']),
      };
    }
    return _putJson(
      c,
      '${c.baseUrl}/${_repoSeg(a)}'
      '/check-runs/${syncAsStr(a['checkRunId'])}',
      body,
    );
  }

  /// `github_create_commit_status` — POST
  /// `repos/{w}/{r}/statuses/{sha}`.
  String _createCommitStatus(GhSyncConfig c, Map<String, dynamic> a) {
    final body = <String, dynamic>{'state': syncAsStr(a['state'])};
    _putIfNotBlank(body, 'description', a['description']);
    _putIfNotBlank(body, 'context', a['context']);
    _putIfNotBlank(body, 'target_url', a['targetUrl']);
    return _postJson(
      c,
      '${c.baseUrl}/${_repoSeg(a)}/statuses/${syncAsStr(a['sha'])}',
      body,
    );
  }

  /// `github_get_workflow_run` — GET `repos/{w}/{r}/actions/runs/{id}`.
  String _getWorkflowRun(GhSyncConfig c, Map<String, dynamic> a) =>
      _getRepoPath(c, a, 'actions/runs/${syncAsStr(a['runId'])}');

  /// `github_repository_dispatch` — POST `repos/{w}/{r}/dispatches`.
  ///
  /// The optional `clientPayload` JSON string is parsed eagerly (Java
  /// `new JSONObject(clientPayload)`); a parse failure surfaces the same
  /// error contract as the other invalid-input tools.
  String _repositoryDispatch(GhSyncConfig c, Map<String, dynamic> a) {
    final body = <String, dynamic>{'event_type': syncAsStr(a['eventType'])};
    final payload = syncAsStr(a['clientPayload']).trim();
    if (payload.isNotEmpty) {
      try {
        body['client_payload'] = jsonDecode(payload);
      } on FormatException {
        return syncErr("Invalid clientPayload JSON: '$payload'");
      }
    }
    return _postJson(c, '${c.baseUrl}/${_repoSeg(a)}/dispatches', body);
  }

  /// `github_update_pr_comment` — PATCH
  /// `repos/{w}/{r}/issues/comments/{id}` with `{"body": text}`.
  String _updatePrComment(GhSyncConfig c, Map<String, dynamic> a) =>
      _putJson(
        c,
        '${c.baseUrl}/${_repoSeg(a)}'
        '/issues/comments/${syncAsStr(a['commentId'])}',
        {'body': syncAsStr(a['text'])},
      );

  /// `github_delete_pr_comment` — DELETE
  /// `repos/{w}/{r}/issues/comments/{id}` (Java: void).
  String _deletePrComment(GhSyncConfig c, Map<String, dynamic> a) =>
      syncBodyOrError(SyncHttpClient.delete(
        '${c.baseUrl}/${_repoSeg(a)}'
        '/issues/comments/${syncAsStr(a['commentId'])}',
        headers: c.headers,
      ));

  /// `github_get_pr_activities` — reviews + inline comments + discussion
  /// comments in Java's aggregation order; comments wrapped as
  /// `{"action": "COMMENTED", "comment": {...}}`.
  String _getPrActivities(GhSyncConfig c, Map<String, dynamic> a) {
    final activities = <dynamic>[];
    activities.addAll(_fetchPages(c, '${_prUrl(c, a)}/reviews'));
    final inline = SyncHttpClient.get(
      '${_prUrl(c, a)}/comments?per_page=100',
      headers: c.headers,
    );
    if (inline.isOk) {
      final decoded = syncTryDecode(inline.body);
      if (decoded is List) {
        for (final comment in decoded) {
          activities.add({'action': 'COMMENTED', 'comment': comment});
        }
      }
    }
    final issue = SyncHttpClient.get(
      '${c.baseUrl}/${_repoSeg(a)}/issues/${_prId(a)}/comments'
      '?per_page=100',
      headers: c.headers,
    );
    if (issue.isOk) {
      final decoded = syncTryDecode(issue.body);
      if (decoded is List) {
        for (final comment in decoded) {
          activities.add({'action': 'COMMENTED', 'comment': comment});
        }
      }
    }
    return jsonEncode(activities);
  }

  /// `github_list_prs_filtered` — all pages, state synonyms normalized,
  /// `merged` keeps only merged PRs, titles matched with [titleRegex].
  String _listPrsFiltered(GhSyncConfig c, Map<String, dynamic> a) {
    final requested = syncAsStr(a['state']).trim().toLowerCase();
    final normalized = switch (requested) {
      'opened' => 'open',
      'declined' => 'closed',
      _ => requested,
    };
    final pattern = RegExp(syncAsStr(a['titleRegex']));
    final out = <Map<String, dynamic>>[];
    for (var page = 1;; page++) {
      final url =
          '${c.baseUrl}/${_repoSeg(a)}/pulls'
          '?state=$normalized&sort=updated&direction=desc'
          '&per_page=100&page=$page';
      final resp = SyncHttpClient.get(url, headers: c.headers);
      if (!resp.isOk) break;
      final decoded = syncTryDecode(resp.body);
      if (decoded is! List || decoded.isEmpty) break;
      for (final pr in decoded) {
        if (pr is! Map) continue;
        if (requested == 'merged' && pr['merged_at'] == null) continue;
        final title = syncAsStr(pr['title']);
        if (pattern.hasMatch(title)) {
          out.add(pr.cast<String, dynamic>());
        }
      }
      if (decoded.length < 100) break;
    }
    return jsonEncode(out);
  }

  /// `github_list_release_assets` — GET
  /// `repos/{w}/{r}/releases/{releaseId}/assets`.
  String _listReleaseAssets(GhSyncConfig c, Map<String, dynamic> a) =>
      _getRepoPath(c, a, 'releases/${syncAsStr(a['releaseId'])}/assets');

  /// `github_delete_release_asset` — DELETE
  /// `repos/{w}/{r}/releases/assets/{assetId}` (Java: void).
  String _deleteReleaseAsset(GhSyncConfig c, Map<String, dynamic> a) =>
      syncBodyOrError(SyncHttpClient.delete(
        '${c.baseUrl}/${_repoSeg(a)}'
        '/releases/assets/${syncAsStr(a['assetId'])}',
        headers: c.headers,
      ));

  /// `github_get_commits_from_branches` — commits from every branch whose
  /// name matches `branchNameRegex`, de-duplicated by SHA.
  String _getCommitsFromBranches(GhSyncConfig c, Map<String, dynamic> a) {
    final pattern = RegExp(syncAsStr(a['branchNameRegex']));
    final since = syncAsStr(a['since']).trim();
    final seenShas = <String>{};
    final out = <dynamic>[];
    for (final branch in _fetchPages(c, '${_repoSeg(a)}/branches')) {
      final name = syncAsStr(branch['name']);
      if (name.isEmpty || !pattern.hasMatch(name)) continue;
      for (final commit in _branchCommits(c, name, since)) {
        final sha = commit['sha'];
        final key = sha == null ? '' : syncAsStr(sha);
        if (key.isEmpty || !seenShas.add(key)) continue;
        out.add(commit);
      }
    }
    return jsonEncode(out);
  }

  /// All pages of one branch's commit list (Java `getCommitsFromBranch`).
  List<dynamic> _branchCommits(GhSyncConfig c, String branch, String since) {
    final out = <dynamic>[];
    final query = 'sha=${Uri.encodeQueryComponent(branch)}'
        '${since.isEmpty ? '' : '&since=$since T00:00:00Z'.trim()}'
        '&per_page=100';
    for (var page = 1;; page++) {
      final resp = SyncHttpClient.get(
        '${c.baseUrl}/${_repoSeg(c.args)}/commits?$query&page=$page',
        headers: c.headers,
      );
      if (!resp.isOk) break;
      final decoded = syncTryDecode(resp.body);
      if (decoded is! List || decoded.isEmpty) break;
      out.addAll(decoded);
      if (decoded.length < 100) break;
    }
    return out;
  }
}
