<<<<<<< HEAD
/// `dmtools upgrade [version]` — Dart port of the Java runtime upgrade
/// (dm.ai #701 parity, gh-395).
///
/// Reachable both as the launcher command `upgrade` and inside the runtime
/// as `mcp upgrade` / `upgrade`, so installs with an OLD launcher (which
/// forwards unknown commands to the runtime) can still upgrade.
///
/// Flow: validate the version (`1.2.3` / `v1.2.3`) before anything is
/// downloaded → download the release `install.sh` (failed download runs
/// nothing) → run it with the version, returning its exit code. The
/// installer replaces both runtime and launcher.
///
/// `DMTOOLS_UPGRADE_DRY_RUN=true` prints the plan and changes nothing.
library;

import 'dart:typed_data';
import 'dart:io';

/// Repository hosting the release artifacts and `install.sh`.
const String upgradeRepo = 'epam/dmtools-dart';

/// Strict semantic version: `1.2.3` or `v1.2.3`.
final RegExp upgradeVersionPattern = RegExp(r'^v?\d+\.\d+\.\d+$');

/// Downloads the installer script bytes for [url]; throws on failure.
typedef UpgradeDownloader = Future<List<int>> Function(Uri url);

/// Runs the installer script at [scriptPath] with [args]; returns its exit code.
typedef UpgradeInstallerRunner = Future<int> Function(
  String scriptPath,
  List<String> args,
);

/// Implements the upgrade command.
class UpgradeCommand {
  /// Creates the command. [dryRun] comes from `DMTOOLS_UPGRADE_DRY_RUN`.
  /// [download] and [runInstaller] are test seams.
  UpgradeCommand({
    required void Function(String line) writer,
    required void Function(String line) errorWriter,
    this.dryRun = false,
    UpgradeDownloader? download,
    UpgradeInstallerRunner? runInstaller,
  })  : _writer = writer,
        _errorWriter = errorWriter,
        _download = download ?? _defaultDownload,
        _runInstaller = runInstaller ?? _defaultRunInstaller;

  final void Function(String line) _writer;
  final void Function(String line) _errorWriter;
  final UpgradeDownloader _download;
  final UpgradeInstallerRunner _runInstaller;

  /// When true, nothing is downloaded or executed.
  final bool dryRun;

  /// Runs the upgrade for [args] (optional version as the first argument).
  /// Returns the exit code.
  Future<int> run(List<String> args) async {
    final version = args.isEmpty ? null : args.first.trim();
    if (version != null && !upgradeVersionPattern.hasMatch(version)) {
      _errorWriter(
        'Error: invalid version "$version" — expected 1.2.3 or v1.2.3',
      );
      return 1;
    }
    final tag = version == null
        ? null
        : (version.startsWith('v') ? version : 'v$version');
    final url = tag == null
        ? Uri.parse(
            'https://github.com/$upgradeRepo/releases/latest/download/install.sh',
          )
        : Uri.parse(
            'https://github.com/$upgradeRepo/releases/download/$tag/install.sh',
          );
    final target = tag ?? 'latest';

    if (dryRun) {
      _writer('Dry run: would download $url and upgrade to $target');
      return 0;
    }

    final List<int> bytes;
    try {
      bytes = await _download(url);
    } on Object catch (e) {
      _errorWriter('Error: failed to download installer from $url: $e');
      return 1;
    }

    final temp = await Directory.systemTemp.createTemp('dmtools_upgrade_');
    try {
      final script = File('${temp.path}/install.sh');
      await script.writeAsBytes(bytes);
      _writer('Upgrading dmtools to $target...');
      final installerArgs = tag == null ? const <String>[] : [tag];
      final code = await _runInstaller(script.path, installerArgs);
      if (code != 0) {
        _errorWriter('Error: installer exited with code $code');
      }
      return code;
    } finally {
      await temp.delete(recursive: true);
    }
  }

  static Future<List<int>> _defaultDownload(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
=======
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

/// Accepted version shapes: `1.2.3`, optional `v`, optional pre-release tag.
/// Anything else would change the installer URL or reach `install.sh` raw.
final RegExp _versionPattern = RegExp(r'^v?\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$');

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
    final help = _helpExit(args);
    if (help != null) return help;
    final version = _resolveRequestedVersion(args);
    if (version.isNotEmpty && !_versionPattern.hasMatch(version)) {
      _writer('Invalid version "$version". Expected e.g. 0.1.60 or v0.1.60.');
      return 2;
    }
    final url = _resolveUrl(version);
    final before = dmtoolsVersion;

    _writer('Installed version: $before');
    _writer('Installer: $url');

    return _executeInstaller(version, url, before);
  }

  /// Runs the fetched installer (or reports the dry run) — extracted from
  /// [run] to keep its cyclomatic complexity under the CRAP gate.
  Future<int> _executeInstaller(
    String version,
    String url,
    String before,
  ) async {
    if (_env['DMTOOLS_UPGRADE_DRY_RUN'] == 'true') {
      _writer(
        'Dry run: would run the installer above'
        '${version.isEmpty ? '' : ' for $version'}. No changes made.',
      );
      return 0;
    }

    final script = await _fetch(url);
    if (script == null) {
      _reportDownloadFailed(url);
      return 1;
    }
    final env = Map<String, String>.from(_env);
    if (version.isNotEmpty) env['DMTOOLS_VERSION'] = version;
    final code = await _run(script, env);
    if (code != 0) {
      _reportInstallFailed(code);
      return code;
    }
    _writer(
      'Installer finished (requested: ${_displayVersion(version)}; '
      'was $before). Run `dmtools --version` to confirm the installed version.',
    );
    return 0;
  }

  /// The version to upgrade to: the positional arg wins, else
  /// `DMTOOLS_VERSION`, else latest (empty string).
  String _resolveRequestedVersion(List<String> args) {
    final positional = args.where((a) => !a.startsWith('-')).toList();
    final requested = positional.isEmpty ? null : positional.first.trim();
    if (requested == null || requested.isEmpty) {
      return _env['DMTOOLS_VERSION'] ?? '';
    }
    return requested;
  }

  /// Prints the usage line for `--help`/`-h`; null when args are real work.
  int? _helpExit(List<String> args) {
    if (args.any((a) => a == '--help' || a == '-h')) {
      _writer('Usage: dmtools upgrade [version]   (alias: update)');
      return 0;
    }
    return null;
  }

  /// Reports a failed download; the installation is left untouched.
  void _reportDownloadFailed(String url) {
    _writer(
      'Upgrade failed: could not download $url. '
      'The existing installation was left untouched.',
    );
  }

  /// Reports a failed installer run; the installation is left untouched.
  void _reportInstallFailed(int code) {
    _writer(
      'Upgrade failed: installer exited with code $code. '
      'The existing installation was left untouched.',
    );
  }

  /// The human-facing version label: `latest` or the requested one, `v`-less.
  String _displayVersion(String version) =>
      version.isEmpty ? 'latest' : version.replaceFirst(RegExp(r'^v'), '');

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
      final dir = await Directory.systemTemp.createTemp('dmtools-install-');
      final file = File('${dir.path}/install.sh');
      await file.writeAsString(body, flush: true);
      return file.path;
    } catch (_) {
      return null;
>>>>>>> origin/main
    } finally {
      client.close(force: true);
    }
  }

<<<<<<< HEAD
  static Future<int> _defaultRunInstaller(
    String path,
    List<String> args,
  ) async {
    final process = await Process.start(
        'sh',
        [
          path,
          ...args,
        ],
        mode: ProcessStartMode.inheritStdio);
    return process.exitCode;
=======
  static Future<int> _defaultRun(
    String scriptPath,
    Map<String, String> env,
  ) async {
    final result = await Process.run('sh', [scriptPath], environment: env);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    return result.exitCode;
>>>>>>> origin/main
  }
}
