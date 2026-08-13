/// Command-line dispatcher — Dart port of the Java `JobRunner` CLI surface.
///
/// Version, help, job listing, `doctor`, and `run` are live. `run` resolves a
/// job config via [RunCommandProcessor], then dispatches to [AgentFactory]
/// (for `cliagent`) or [JsJobRunner] (for `jsrunner`/`.js` scripts) and prints
/// the result. Interactive mode and direct tool invocation are stubs pending
/// later phases.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/agent_factory.dart';
import '../agents/cli_agent.dart';
import '../config/property_reader.dart';
import '../js/job_runner.dart';
import '../mcp/default_tool_registry.dart';
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
  ///
  /// Async because `run` may execute a [CliAgent] whose lifecycle uses
  /// `Process.run` (await-based). All other handlers are synchronous and
  /// complete immediately.
  Future<int> dispatch(List<String> args) async {
    if (args.isEmpty) {
      return _isTty() ? _interactiveStub() : _printHelp();
    }
    final handler = _handlers[args.first];
    if (handler == null) return _toolStub();
    return handler(args.skip(1).toList());
  }

  late final Map<String, FutureOr<int> Function(List<String> rest)> _handlers =
      {
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

  /// Runs a job: resolve config → parse name/params → execute → print result.
  ///
  /// Returns `0` on success, `1` on any error (bad config, unknown job,
  /// execution failure). The jsrunner branch calls [JsJobRunner] directly;
  /// everything else goes through [AgentFactory].
  Future<int> _runJob(List<String> rest) async {
    if (rest.isEmpty) {
      _writer('Error: run requires a job name or a JSON config file.');
      _writer('Usage: dmtools run <json-file> [encoded] [--key value ...]');
      return 1;
    }
    try {
      final resolved = RunCommandProcessor().process(['run', ...rest]);
      final config = jsonDecode(resolved) as Map<String, dynamic>;
      final name = (config['name'] as String?) ?? '<unnamed>';
      final params = (config['params'] as Map<String, dynamic>?) ?? const {};
      return await _executeJob(name, params);
    } on ArgumentError catch (e) {
      _writer('Error: ${e.message}');
      return 1;
    } on FormatException catch (e) {
      _writer('Error: invalid config JSON — ${e.message}');
      return 1;
    } on FileSystemException catch (e) {
      _writer('Error: ${e.message}');
      return 1;
    } catch (e) {
      _writer('Error: $e');
      return 1;
    }
  }

  /// Executes the resolved job config: jsrunner → [JsJobRunner], otherwise
  /// create the agent via [AgentFactory] and run it.
  Future<int> _executeJob(String name, Map<String, dynamic> params) async {
    if (name.toLowerCase() == 'jsrunner') {
      return _executeJsRunner(params);
    }
    final agent = AgentFactory.create(name, params);
    if (agent is CliAgent) {
      final result = await agent.run();
      _writer(jsonEncode(result));
      return result['success'] == true ? 0 : 1;
    }
    _writer('Error: job "$name" is not executable (unsupported agent type)');
    return 1;
  }

  /// Runs a jsrunner job via [JsJobRunner] with `jsPath` and `jobParams`.
  int _executeJsRunner(Map<String, dynamic> params) {
    final jsPath = params['jsPath'] as String?;
    if (jsPath == null) {
      _writer('Error: jsrunner requires a jsPath in params');
      return 1;
    }
    final jobParams = params['jobParams'] as Map<String, dynamic>? ?? const {};
    final result = const JsJobRunner().runScript(
      scriptPath: jsPath,
      jobParams: jobParams,
    );
    _writer(result ?? 'undefined');
    return 0;
  }

  int _listTools(List<String> rest) {
    final registry = createDefaultToolRegistry();
    final integrations = _resolveIntegrations();
    var response = registry.generateToolsListResponse(integrations);
    if (rest.isNotEmpty) {
      response = registry.filterToolsList(response, rest.first);
    }
    _writer(const JsonEncoder.withIndent('  ').convert(response));
    return 0;
  }

  /// Resolves the `DMTOOLS_INTEGRATIONS` filter into a set of integration
  /// names.
  ///
  /// Returns `null` (meaning "all integrations") when the variable is unset
  /// or empty; otherwise a lower-case set parsed from the comma-separated
  /// value (e.g. `"jira,confluence"` → `{"jira", "confluence"}`).
  Set<String>? _resolveIntegrations() {
    final raw = _reader.getValue('DMTOOLS_INTEGRATIONS');
    if (raw == null || raw.trim().isEmpty) return null;
    final set = raw
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    return set.isEmpty ? null : set;
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
