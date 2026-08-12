import 'package:dmtools/dmtools.dart';

/// CLI entry point (`dmtools`).
///
/// Phase 0 stub: supports only `--version`/`-v` and `--help`/`-h`.
/// The full JobRunner-compatible command surface is Phase 2 (see GOAL.md).
Future<void> main(List<String> args) async {
  final first = args.isEmpty ? '' : args.first;
  switch (first) {
    case '--version':
    case '-v':
      print(versionLine());
    case '--help':
    case '-h':
    case '':
      print('${versionLine()} — Dart port (Phase 0 skeleton).');
      print('Usage: dmtools [--version] [--help]');
      print('Full CLI surface arrives in Phase 2; see GOAL.md.');
    default:
      print(
          'Unknown command: $first (Phase 0 skeleton supports --version/--help)');
  }
}
