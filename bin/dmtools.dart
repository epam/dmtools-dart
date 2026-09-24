import 'dart:io';

import 'package:dmtools/dmtools.dart';

/// CLI entry point (`dmtools`).
///
/// Thin argv shell per AGENTS.md: all logic lives in `lib/`; this file only
/// delegates to [CliDispatcher] and exits with the returned code. The full
/// JobRunner-compatible command surface lands across Phases 2–4.
Future<void> main(List<String> args) async {
  // Must complete while the event loop is alive: once a QuickJS host
  // callback blocks the main isolate, Isolate.spawn can no longer progress.
  await SyncHttpBridge.shared.boot();
  // runAsync engine workers (epam/dmtools-dart#224). Tests boot private
  // pools instead (JsRunConfig.pool); an unbooted pool surfaces a clear
  // JS error from runAsync rather than failing engine wiring.
  await AsyncJobPool.instance.boot();
  exit(await CliDispatcher().dispatch(args));
}
