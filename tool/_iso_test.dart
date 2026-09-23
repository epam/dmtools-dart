import 'dart:convert';
import 'dart:io';
import 'package:dmtools/src/js/sync_http_client.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    await utf8.decoder.bind(req).join();
    req.response.write(jsonEncode({'pong': true}));
    await req.response.close();
  });
  print('server on ${server.port}');
  final sw = Stopwatch()..start();
  final resp = SyncHttpClient.dispatch(
      'POST', 'http://127.0.0.1:${server.port}/x',
      headers: {'x-a': 'b'}, body: 'ping');
  print('resp ${resp.statusCode} ${resp.body} in ${sw.elapsedMilliseconds}ms');
  await server.close(force: true);
}
