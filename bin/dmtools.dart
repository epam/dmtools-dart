import 'dart:io';

import 'package:dmtools/dmtools.dart';

/// CLI entry point (`dmtools`).
///
/// Thin argv shell per AGENTS.md: all logic lives in `lib/`; this file only
/// delegates to [CliDispatcher] and exits with the returned code. The full
/// JobRunner-compatible command surface lands across Phases 2–4.
Future<void> main(List<String> args) async {
  exit(await CliDispatcher().dispatch(args));
}
