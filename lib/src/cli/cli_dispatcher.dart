/// Command-line dispatcher — Dart port of the Java `JobRunner` CLI surface.
///
/// Phase 2 scaffolding: version, help, job listing and `doctor` are live.
/// Job execution, the MCP tool catalog, interactive mode and direct tool
/// invocation print stub messages and exit non-zero until Phases 3–4.
library;

import 'dart:convert';
import 'dart:io';

import '../config/property_reader.dart';
import '../version.dart';
import 'doctor_command.dart';
import 'run_command_processor.dart';
import 'job_registry.dart';

/// Parses CLI arguments, dispatches commands and reports exit codes.
class CliDispatcher {
  /// Creates a dispatcher.
  ///
  /// [writer] receives every output line (defaults to `print`),
  /// [propertyReader] backs the `doctor` command, and [isTty] decides the
  /// no-argument behaviour (interactive stub on a terminal, help otherwise).
  CliDispatcher({
    void Function(String line)? writer,
    PropertyReader? propertyReader,
    bool Function()? isTty,
  })  : _writer = writer ?? print,
        _reader = propertyReader ?? PropertyReader(),
        _isTty = isTty ?? _stdoutIsTty;

  final void Function(String line) _writer;
  final PropertyReader _reader;
  final bool Function() _isTty;

  static bool _stdoutIsTty() => stdout.hasTerminal;

  /// Dispatches [args], writing command output, and returns the exit code
  /// (`0` on success, `1` on error or an as-yet-unimplemented command).
  int dispatch(List<String> args) {
    if (args.isEmpty) {
      return _isTty() ? _interactiveStub() : _printHelp();
    }
    final handler = _handlers[args.first];
    if (handler == null) return _toolStub();
    return handler(args.skip(1).toList());
  }

  late final Map<String, int Function(List<String> rest)> _handlers = {
    '--version': (_) => _printVersion(),
    '-v': (_) => _printVersion(),
    '--help': (_) => _printHelp(),
    '-h': (_) => _printHelp(),
    'help': (_) => _printHelp(),
    '--list-jobs': (_) => _printJobs(),
    'doctor': (_) => _runDoctor(),
    'run': _runJob,
    'list': _listTools,
    'interactive': (_) => _interactiveStub(),
    'i': (_) => _interactiveStub(),
  };

  int _printVersion() {
    _writer('DMTools $dmtoolsVersion');
    _writer('A comprehensive development management toolkit');
    return 0;
  }

  int _printHelp() {
    _writer(helpText);
    return 0;
  }

  int _printJobs() {
    _writer('Available Jobs:');
    _writer('===============');
    for (final job in JobRegistry.displayJobs) {
      _writer('- $job');
    }
    _writer('Total: ${JobRegistry.displayJobs.length} jobs available');
    return 0;
  }

  int _runDoctor() {
    _writer(DoctorCommand(reader: _reader).run());
    return 0;
  }

  int _runJob(List<String> rest) {
    if (rest.isEmpty) {
      _writer('Error: run requires a job name or a JSON config file.');
      _writer('Usage: dmtools run <json-file> [encoded] [--key value ...]');
      return 1;
    }
    try {
      final resolved = RunCommandProcessor().process(['run', ...rest]);
      final name = _extractJobName(resolved);
      _writer(
        'Config resolved for job: $name (execution requires Phase 3+ '
        'integrations)',
      );
      return 1;
    } on ArgumentError catch (e) {
      _writer('Error: ${e.message}');
      return 1;
    } on FormatException catch (e) {
      _writer('Error: invalid config JSON — ${e.message}');
      return 1;
    } on FileSystemException catch (e) {
      _writer('Error: ${e.message}');
      return 1;
    }
  }

  /// Extracts the job name from a resolved config JSON string.
  String _extractJobName(String configJson) {
    final decoded = jsonDecode(configJson);
    if (decoded is Map<String, dynamic> && decoded['name'] is String) {
      return decoded['name'] as String;
    }
    return '<unnamed>';
  }

  int _listTools(List<String> _) {
    _writer('MCP tool catalog requires Phase 3');
    return 1;
  }

  int _interactiveStub() {
    _writer('Interactive mode requires Phase 4 (terminal picker)');
    return 1;
  }

  int _toolStub() {
    _writer('Tool execution requires Phase 3 MCP registry');
    return 1;
  }

  /// Help text, byte-identical to the Java `JobRunner.printHelp()` output.
  static const String helpText = '''
DMTools CLI Wrapper

Usage:
  dmtools list                           # List available MCP tools
  dmtools doctor                         # Check current directory configuration
  dmtools run <json-file>                # Execute job with JSON config file
  dmtools run <job-name> [--key value]   # Execute a registered job without a config file
  dmtools run <json-file> <encoded>      # Execute job with file + encoded overrides
  dmtools <tool> [args...]              # Execute MCP tool with args
  dmtools <tool> --data '{"json"}'      # Execute with inline JSON
  dmtools <tool> --file params.json     # Execute with JSON file
  dmtools <tool> --verbose              # Execute with verbose output
  dmtools <tool> --debug                # Execute with debug output and error messages
  dmtools <tool> <<EOF                  # Execute with heredoc
  {"json": "data"}
  EOF

Examples:
  dmtools list
  dmtools doctor
  dmtools run job-config.json
  dmtools run codegenerator --param1 test
  dmtools jira_get_ticket DMC-479 summary,description
  dmtools jira_get_ticket --data '{"key": "DMC-479", "fields": ["summary"]}'

Environment Variables:
  DMTOOLS_INTEGRATIONS    Comma-separated list of integrations (jira,confluence,figma)

Environment Files:
  The tool automatically loads environment variables from dmtools.env and
  dmtools-local.env in the current working directory.

  Common variables:
  - JIRA_BASE_PATH, JIRA_EMAIL, JIRA_API_TOKEN
  - CONFLUENCE_BASE_PATH, CONFLUENCE_API_TOKEN
  - FIGMA_API_KEY
  - GEMINI_API_KEY, OPENAI_API_KEY
  - SOURCE_GITHUB_TOKEN, GITLAB_TOKEN, BITBUCKET_TOKEN''';
}
