import 'dart:convert';
import 'dart:io';

/// Manages the Python echo-server subprocess lifecycle for sync-HTTP tests.
///
/// Dart's [HttpServer] runs on the event loop, which is frozen during
/// `Process.runSync('curl', …)` — a separate process is required to serve
/// requests while the isolate is blocked.
class EchoServer {
  Process? _process;

  /// The bound port (valid after [start]).
  int port = 0;

  /// Starts the echo server on an ephemeral port.
  Future<void> start() async {
    final script = '${Directory.current.path}/test/js/test_echo_server.py';
    _process = await Process.start('python3', [script, '0']);
    final firstLine = await _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    port = int.parse(firstLine.trim());
  }

  /// Kills the server process.
  void stop() => _process?.kill();
}

/// Whether `python3` is available on this system.
bool hasPython3() {
  try {
    return Process.runSync('which', ['python3']).exitCode == 0;
  } catch (_) {
    return false;
  }
}
