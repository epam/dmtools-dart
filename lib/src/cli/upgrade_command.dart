/// `dmtools upgrade [version]` (alias `update`).
///
/// The Dart distribution ships as an AOT binary plus a QuickJS library, both
/// installed by `install.sh` under `~/.dmtools/bin`. Upgrading therefore reuses
/// that installer (the same mechanism as first install) instead of replacing
/// the running executable in place.
///
/// Flow: resolve the install script URL, download it to a temp file (failure
/// exits non-zero before anything is touched), then run it with `sh`.
library;

import 'dart:io';

import '../version.dart';

/// Default installer location for the latest release.
const String _latestInstallUrl =
    'https://github.com/epam/dmtools-dart/releases/latest/download/install.sh';

/// Upgrade runner. All side effects are injectable for tests.
class UpgradeCommand {
  /// Creates an upgrade runner.
  UpgradeCommand({
    void Function(String line)? writer,
    Map<String, String>? environment,
    Future<String?> Function(String url)? fetchScript,
    Future<int> Function(String scriptPath, Map<String, String> env)? runScript,
  })  : _writer = writer ?? print,
        _env = environment ?? Platform.environment,
        _fetch = fetchScript ?? _defaultFetch,
        _run = runScript ?? _defaultRun;

  final void Function(String line) _writer;
  final Map<String, String> _env;
  final Future<String?> Function(String url) _fetch;
  final Future<int> Function(String scriptPath, Map<String, String> env) _run;

  /// Runs the upgrade. [args] holds the optional version (`upgrade 0.1.60`
  /// or `upgrade v0.1.60`). Returns the process exit code.
  Future<int> run(List<String> args) async {
    final positional = args.where((a) => !a.startsWith('-')).toList();
    final requested = positional.isEmpty ? null : positional.first.trim();
    if (args.any((a) => a == '--help' || a == '-h')) {
      _writer('Usage: dmtools upgrade [version]   (alias: update)');
      return 0;
    }
    final version = (requested == null || requested.isEmpty)
        ? (_env['DMTOOLS_VERSION'] ?? '')
        : requested;
    final url = _resolveUrl(version);
    final before = dmtoolsVersion;

    _writer('Installed version: $before');
    _writer('Installer: $url');

    if (_env['DMTOOLS_UPGRADE_DRY_RUN'] == 'true') {
      _writer(
        'Dry run: would run the installer above'
        '${version.isEmpty ? '' : ' for $version'}. No changes made.',
      );
      return 0;
    }

    final script = await _fetch(url);
    if (script == null) {
      _writer(
        'Upgrade failed: could not download $url. '
        'The existing installation was left untouched.',
      );
      return 1;
    }

    final env = Map<String, String>.from(_env);
    if (version.isNotEmpty) env['DMTOOLS_VERSION'] = version;
    final code = await _run(script, env);
    if (code != 0) {
      _writer(
        'Upgrade failed: installer exited with code $code. '
        'The existing installation was left untouched.',
      );
      return code;
    }
    _writer(
      'Upgraded: $before -> '
      '${version.isEmpty ? 'latest' : version.replaceFirst(RegExp(r'^v'), '')}'
      '. Run `dmtools --version` to confirm.',
    );
    return 0;
  }

  /// Resolves the installer URL. `DMTOOLS_INSTALL_SCRIPT_URL` wins; a
  /// version selects the tagged release asset, otherwise the latest one.
  String _resolveUrl(String version) {
    final override = _env['DMTOOLS_INSTALL_SCRIPT_URL'];
    if (override != null && override.isNotEmpty) return override;
    if (version.isEmpty) return _latestInstallUrl;
    final tag = version.startsWith('v') ? version : 'v$version';
    return 'https://github.com/epam/dmtools-dart/releases/download/$tag/install.sh';
  }

  static Future<String?> _defaultFetch(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(const SystemEncoding().decoder).join();
      final file = await File(
        '${Directory.systemTemp.path}/dmtools-install-${DateTime.now().microsecondsSinceEpoch}.sh',
      ).create();
      await file.writeAsString(body);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<int> _defaultRun(
    String scriptPath,
    Map<String, String> env,
  ) async {
    final result = await Process.run('sh', [scriptPath], environment: env);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    return result.exitCode;
  }
}
