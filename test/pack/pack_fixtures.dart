/// Shared fixtures for the [AgentPackResolver] tests: a synthetic agent
/// tree ([agentRoot] + [write]), real and hostile pack zips
/// ([buildPack], [buildMalicious], [buildZipWithManifest], [sha256Of]),
/// and a loopback HTTP server for URL-pack downloads ([startPackServer]).
///
/// Extracted from `agent_pack_resolver_test.dart` so the suite file stays
/// under the `loc` gate (crap4dart.yaml: max 800 lines per file); test code
/// only — never imported from `lib/`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dmtools/src/compile/agent_pack_compiler.dart'
    hide AgentPackException;

/// Root of the synthetic agent tree; assigned (and deleted) by the suite's
/// setUp/tearDown.
late Directory agentRoot;

/// Writes [content] to [relativePath] under the agent root; returns the file.
File write(String relativePath, String content) {
  final file = File('${agentRoot.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file;
}

/// Builds a real pack zip via [AgentPackCompiler]; returns the zip file.
File buildPack(String agentName, String version) {
  write('js/common/util.js', '// util\n');
  write('js/main.js', "var u = require('./common/util.js');\n");
  write('instructions/common/guide.md', '# Guide\n');
  final entry = write(
    '$agentName.json',
    jsonEncode({
      'name': 'TestAgent',
      'params': {
        'jsPath': 'agents/js/main.js',
        'cliPrompts': ['agents/instructions/common/guide.md'],
      },
    }),
  );
  final outDir = Directory.systemTemp.createTempSync('dist_');
  return AgentPackCompiler(agentRoot.path)
      .compile(entry, version, 'abc123', outDir)
      .zipFile;
}

/// SHA-256 hex digest of [content] (manifest inventory helper).
String sha256Of(String content) =>
    sha256.convert(utf8.encode(content)).toString();

/// Builds a zip with a hostile entry for zip-slip tests.
File buildMalicious(String evilEntry) {
  final manifest = {
    'agent': 'evil',
    'version': '1.0.0',
    'defaultEntry': 'evil.json',
    'files': <dynamic>[],
  };
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes))
    ..addFile(ArchiveFile(evilEntry, 3, utf8.encode('bad')));
  final zip = File(
    '${Directory.systemTemp.createTempSync('evil_').path}/evil.zip',
  );
  zip.writeAsBytesSync(ZipEncoder().encode(archive)!);
  return zip;
}

/// Builds a zip from [manifest] plus [extraFiles] (name → bytes); [modes]
/// overrides the unix mode of individual entries.
File buildZipWithManifest(
  Map<String, dynamic> manifest,
  Map<String, List<int>> extraFiles, {
  Map<String, int> modes = const {},
}) {
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final archive = Archive()
    ..addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
  for (final entry in extraFiles.entries) {
    final file = ArchiveFile(entry.key, entry.value.length, entry.value);
    final mode = modes[entry.key];
    if (mode != null) file.mode = mode;
    archive.addFile(file);
  }
  final zip = File(
    '${Directory.systemTemp.createTempSync('zip_').path}/pack.zip',
  );
  zip.writeAsBytesSync(ZipEncoder().encode(archive)!);
  return zip;
}

/// Loopback pack server entry point. Runs in its own isolate because
/// [SyncHttpClient] blocks the caller isolate (curl subprocess) — an
/// in-isolate server could never answer. Serves [sha256Body] for `.sha256`
/// (404 when null), the pack bytes otherwise, and reports the zip request's
/// Authorization header.
void packServerEntry(List<Object?> init) {
  final readyPort = init[0] as SendPort;
  final authPort = init[1] as SendPort;
  final zipBytes = init[2] as List<int>;
  final sha256Body = init[3] as String?;
  HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    readyPort.send(server.port);
    server.listen((request) {
      if (request.uri.path.endsWith('.sha256')) {
        if (sha256Body == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.write(sha256Body);
        }
      } else {
        authPort.send(request.headers.value('authorization'));
        request.response.add(zipBytes);
      }
      request.response.close();
    });
  });
}

/// Starts the loopback pack server in a separate isolate.
Future<({int port, ReceivePort authInbox, Isolate isolate})> startPackServer(
  List<int> zipBytes, {
  String? sha256Body,
}) async {
  final readyInbox = ReceivePort();
  final authInbox = ReceivePort();
  final isolate = await Isolate.spawn(packServerEntry, [
    readyInbox.sendPort,
    authInbox.sendPort,
    zipBytes,
    sha256Body,
  ]);
  final port = await readyInbox.first as int;
  readyInbox.close();
  return (port: port, authInbox: authInbox, isolate: isolate);
}
