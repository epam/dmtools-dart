import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_tools/confluence_sync_tools.dart';

Future<void> main() async {
  PropertyReader.testIsolation = true;
  final server = await Process.start('python3', [
    '${Directory.current.path}/test/js/test_echo_server.py', '0'
  ]);
  final port = int.parse(await server.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first);
  print('echo on $port');
  PropertyReader.setOverrides({
    'CONFLUENCE_BASE_PATH': 'http://127.0.0.1:$port',
    'CONFLUENCE_LOGIN_PASS_TOKEN': 'conf-token',
    'CONFLUENCE_AUTH_TYPE': 'Basic',
    'CONFLUENCE_DEFAULT_SPACE': 'ENG',
  });
  final tools = ConfluenceSyncTools(PropertyReader());
  print('pool ready before boot: ${confluenceSyncWorkerPool.ready}');
  await confluenceSyncWorkerPool.boot();
  print('pool ready after boot: ${confluenceSyncWorkerPool.ready}');
  final out = Directory.systemTemp.createTempSync('dmtools_dbg_');
  final result = tools.dispatch('confluence_download_pages', {
    'urlStrings': ['http://127.0.0.1:$port/wiki/spaces/ENG/pages/777/Hi'],
    'outputPath': out.path,
    'depth': 1,
  });
  print('result: $result');
  print('files: ${out.listSync(recursive: true).map((e) => e.path).join('\n  ')}');
  server.kill();
}
