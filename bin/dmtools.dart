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
  // The engine-worker pool (runAsync) boots lazily in CliDispatcher, just
  // before a job whose resolved config sets parallelWorkers >= 2 — the
  // same event-loop-alive guarantee, zero cost for every other command
  // (epam/dmtools-dart#241). Tests boot private pools instead
  // (JsRunConfig.pool); an unbooted pool surfaces a clear JS error from
  // runAsync rather than failing engine wiring.
  exit(await CliDispatcher().dispatch(args));
}
