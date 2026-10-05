import 'package:dmtools/src/js/sync_parallel.dart';

Map<String, dynamic>? _runner(String kind, Map<String, dynamic> args) =>
    <String, dynamic>{'echo': args['x']};

Future<void> main() async {
  registerSyncWorkerRunner('dbg', _runner);
  final pool = SyncWorkerPool('dbg', workerCount: 2);
  print('booting...');
  await pool.boot().timeout(Duration(seconds: 10));
  print('booted, running...');
  final r = pool.run([
    SyncParallelJob(index: 0, kind: 'k', args: {'x': 1}),
    SyncParallelJob(index: 1, kind: 'k', args: {'x': 2}),
  ]);
  print('results: $r');
  pool.dispose();
}
