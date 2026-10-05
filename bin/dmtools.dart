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
  // The engine-worker pool (runAsync) and the Confluence parallel pool
  // (gh-348) boot lazily in CliDispatcher, just before a command that can
  // reach them — the same event-loop-alive guarantee, zero cost for every
  // other command (epam/dmtools-dart#241, gh-348 rework). Tests boot
  // private pools instead (JsRunConfig.pool); unbooted pools fall back to
  // the documented inline/sequential execution rather than failing
  // engine wiring.
  exit(await CliDispatcher().dispatch(args));
}
