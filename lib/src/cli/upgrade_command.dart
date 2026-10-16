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
    } finally {
      client.close(force: true);
    }
  }

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
  }
}
