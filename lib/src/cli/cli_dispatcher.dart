/// Command-line dispatcher — Dart port of the Java `JobRunner` CLI surface.
///
/// Version, help, job listing, `doctor`, `run`, `list`, and direct tool
/// invocation are live. `run` resolves a job config via
/// [RunCommandProcessor], then dispatches to [AgentFactory] (for `cliagent`)
/// or [JsJobRunner] (for `jsrunner`/`.js` scripts) and prints the result.
/// Direct tool invocation (`dmtools <tool> [args...]`) dispatches through
/// [ToolBridge]. Interactive mode remains a stub pending Phase 4.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/agent_factory.dart';
import '../agents/cli_agent.dart';
import '../agents/teammate_job.dart';
import '../compile/agent_pack_compiler.dart';
import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';
import '../js/async_job_pool.dart';
import '../js/job_runner.dart';
import '../js/tool_bridge.dart';
import '../mcp/default_tool_registry.dart';
import '../mcp/tool_param.dart';
import '../mcp/tool_registry.dart';
import '../version.dart';
import 'doctor_command.dart';
import 'run_command_processor.dart';
import 'job_registry.dart';

/// Parses CLI arguments, dispatches commands and reports exit codes.
class CliDispatcher {
  /// Creates a dispatcher.
  ///
  /// [writer] receives every output line (defaults to `print`) and
  /// [propertyReader] backs the `doctor` command and the alias-resolution
  /// default reads (`DEFAULT_TRACKER` / `DEFAULT_SOURCE_CODE` resolve
  /// through the standard property chain — overrides, config.properties,
  /// `dmtools.env`, then the process environment — like the tracker-hub
  /// routing rule; defaults to a CWD-rooted reader). [isTty] decides the
  /// no-argument behaviour (interactive stub on a terminal, help
  /// otherwise). [asyncPool] is the engine-worker pool booted lazily for
  /// `runAsync` jobs (defaults to [AsyncJobPool.instance]); a test seam
  /// mirroring [JsRunConfig.pool]. [errorWriter] receives diagnostics that
  /// must stay off the machine-parsed stdout (defaults to
  /// `stderr.writeln`); a test seam like [writer].
  CliDispatcher({
    void Function(String line)? writer,
    void Function(String line)? errorWriter,
    PropertyReader? propertyReader,
    bool Function()? isTty,
    AsyncJobPool? asyncPool,
  })  : _writer = writer ?? print,
        _errorWriter = errorWriter ?? stderr.writeln,
        _reader = propertyReader ?? PropertyReader(),
        _isTty = isTty ?? _stdoutIsTty,
        _asyncPool = asyncPool;

  final void Function(String line) _writer;
  final void Function(String line) _errorWriter;
  final PropertyReader _reader;
  final bool Function() _isTty;

  /// Engine-worker pool booted lazily for `runAsync` jobs; `null` selects
  /// [AsyncJobPool.instance]. Test seam, mirroring [JsRunConfig.pool].
  final AsyncJobPool? _asyncPool;

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
    if (handler == null)
      return _toolDispatch(args.first, args.skip(1).toList());
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
    'compile': _runCompile,
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

  /// Builds a versioned agent pack (zip + manifest + sha256) — dm.ai #595.
  ///
  /// Mirrors the Java `CompileCommand`: parses `entry.json` plus
  /// `--agent-root` / `--version` / `--versions-file` / `--out` /
  /// `--source-commit` and delegates to [AgentPackCompiler].
  int _runCompile(List<String> rest) {
    final guardExit = _compileGuardExit(rest);
    if (guardExit != null) return guardExit;
    final agentName = _stripJsonExtension(_basename(rest.first));
    final agentRoot =
        _optionValue(rest, '--agent-root') ?? _dirname(rest.first);
    final version = _resolveCompileVersion(rest, agentName);
    if (version == null) {
      _writer(
          'Error: --version <semver> or --versions-file versions.json is required');
      return 1;
    }
    try {
      final result = AgentPackCompiler(agentRoot).compile(
          File(rest.first),
          version,
          _optionValue(rest, '--source-commit') ??
              _detectSourceCommit(agentRoot),
          Directory(_optionValue(rest, '--out') ?? 'dist'));
      _printCompileResult(agentName, version, result);
      return 0;
    } on AgentPackException catch (e) {
      _writer('Error: ${e.message}');
      return 1;
    }
  }

  /// Handles the help/usage and missing-entry guard cases; returns the exit
  /// code to short-circuit with, or `null` to proceed with the build.
  int? _compileGuardExit(List<String> rest) {
    if (rest.isEmpty || rest.first == '--help' || rest.first == '-h') {
      _writer(_compileUsage);
      return rest.isEmpty ? 1 : 0;
    }
    if (!File(rest.first).existsSync()) {
      _writer('Error: entry config not found: ${rest.first}');
      return 1;
    }
    return null;
  }

  /// Version precedence: explicit `--version`, else the agent's versions.json entry.
  String? _resolveCompileVersion(List<String> rest, String agentName) =>
      _optionValue(rest, '--version') ??
      _versionFromFile(_optionValue(rest, '--versions-file'), agentName);

  /// Prints the successful compile summary.
  void _printCompileResult(
      String agentName, String version, PackResult result) {
    _writer('Agent pack built successfully:');
    _writer('  agent:    $agentName');
    _writer('  version:  $version');
    _writer('  files:    ${result.fileCount}');
    _writer('  zip:      ${result.zipFile.path}');
    _writer('  manifest: ${result.manifestFile.path}');
    _writer('  sha256:   ${result.shaFile.path}');
  }

  static const String _compileUsage = '''
Usage: dmtools compile <entry.json> [options]

Build a versioned, self-contained agent pack (zip + manifest + sha256).

Options:
  --agent-root <dir>             Agents checkout root (default: entry.json's directory)
  --version <semver>             Pack version (required unless --versions-file)
  --versions-file versions.json  Per-agent versions map
  --out <dir>                    Output directory (default: ./dist)
  --source-commit <sha>          Source commit (default: git rev-parse HEAD)
''';

  /// Reads the agent's version from a `versions.json` map; `null` when absent.
  String? _versionFromFile(String? versionsFile, String agentName) {
    if (versionsFile == null) return null;
    final file = File(versionsFile);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        final version = decoded[agentName];
        return version is String ? version : null;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Best-effort source commit: `git rev-parse HEAD` in the agent root.
  String _detectSourceCommit(String agentRoot) {
    try {
      final result = Process.runSync('git', ['rev-parse', 'HEAD'],
          workingDirectory: agentRoot);
      final out = (result.stdout as String).trim();
      if (result.exitCode == 0 && out.isNotEmpty) return out;
    } on Object {
      // fall through — git unavailable or not a repo
    }
    return 'unknown';
  }

  String? _optionValue(List<String> args, String flag) {
    for (var i = 0; i < args.length - 1; i++) {
      if (args[i] == flag) return args[i + 1];
    }
    return null;
  }

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

  String _dirname(String path) {
    final idx = path.replaceAll('\\', '/').lastIndexOf('/');
    return idx >= 0 ? path.substring(0, idx) : '.';
  }

  String _stripJsonExtension(String fileName) => fileName.endsWith('.json')
      ? fileName.substring(0, fileName.length - '.json'.length)
      : fileName;

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
    if (agent is TeammateJob) {
      final result = await agent.run();
      _writer(jsonEncode(result));
      return result['success'] == true ? 0 : 1;
    }
    _writer('Error: job "$name" is not executable (unsupported agent type)');
    return 1;
  }

  /// Runs a jsrunner job via [JsJobRunner] with `jsPath` and `jobParams`.
  ///
  /// Boots the engine-worker pool first when the job enables `runAsync`
  /// (`jobParams.parallelWorkers >= 2`) — gh-241: lazily, so only parallel
  /// jobs pay for the isolates, and while the event loop is still alive:
  /// spawning must complete before the QuickJS host callbacks block this
  /// isolate in FFI.
  Future<int> _executeJsRunner(Map<String, dynamic> params) async {
    final jsPath = params['jsPath'] as String?;
    if (jsPath == null) {
      _writer('Error: jsrunner requires a jsPath in params');
      return 1;
    }
    final jobParams = params['jobParams'] as Map<String, dynamic>? ?? const {};
    final pool = await _prepareAsyncPool(jobParams);
    final result = const JsJobRunner().runScript(
      scriptPath: jsPath,
      jobParams: jobParams,
      config: pool == null ? null : JsRunConfig(pool: pool),
    );
    _writer(result ?? 'undefined');
    return 0;
  }

  /// The pool to hand to [JsJobRunner] for a run with [jobParams]: `null`
  /// when the job keeps the `runAsync` surface off (`parallelWorkers < 2`,
  /// the default). Otherwise the injected test pool or
  /// [AsyncJobPool.instance], booted before the JS run.
  ///
  /// A boot failure degrades to a stderr warning: the command proceeds
  /// with the unbooted pool and `runAsync` surfaces the documented clear
  /// JS error on first use — the constrained-environment failure must not
  /// brick the whole run (gh-241).
  Future<AsyncJobPool?> _prepareAsyncPool(
      Map<String, dynamic> jobParams) async {
    if (!JsJobRunner.needsAsyncPool(jobParams)) return null;
    final pool = _asyncPool ?? AsyncJobPool.instance;
    try {
      await pool.boot();
    } catch (e) {
      _errorWriter('dmtools: engine-worker pool boot failed '
          '(runAsync will report an error on first use): $e');
    }
    return pool;
  }

  int _listTools(List<String> rest) {
    final registry = createDefaultToolRegistry();
    final integrations = _resolveIntegrations();
    var response = registry.generateToolsListResponse(integrations);
    if (rest.isNotEmpty) {
      // gh-136: help/list resolution mirrors invocation resolution — an
      // alias filter (tracker_get_ticket) resolves to its carrier so
      // `dmtools <alias> --help` shows the backend tool's schema instead
      // of an empty list. Candidates narrow to DMTOOLS_INTEGRATIONS so the
      // fallback picks a carrier the filtered list actually shows.
      // Unknown text (partial names, free text) stays a raw substring
      // filter.
      final resolved = _resolveToolName(rest.first,
          registry: registry, integrations: integrations);
      response = registry.filterToolsList(response, resolved ?? rest.first);
    }
    _writer(const JsonEncoder.withIndent('  ').convert(response));
    return 0;
  }

  /// Resolves a tool name with the CLI's configured alias defaults — the
  /// single resolution shared by the invocation and help/list paths, so
  /// the Java `McpCliHandler.resolveToolAlias` contract (a canonical name
  /// passes through; an alias resolves to its carrier via DEFAULT_TRACKER
  /// / DEFAULT_SOURCE_CODE) cannot diverge between the two. Both defaults
  /// resolve through the standard property chain (overrides →
  /// config.properties → dmtools.env → OS env) so a `dmtools.env` value
  /// routes the alias too — not just the process environment.
  ///
  /// [integrations] (help/list only — invocation runs on the unfiltered
  /// registry) narrows alias candidates to carriers visible under
  /// `DMTOOLS_INTEGRATIONS` before routing, so the fallback picks a
  /// carrier the filtered tools list shows rather than an empty one.
  String? _resolveToolName(
    String name, {
    String? keyHint,
    ToolRegistry? registry,
    Set<String>? integrations,
  }) =>
      (registry ?? createDefaultToolRegistry()).resolveToolAlias(
        name,
        keyHint: keyHint,
        defaultTracker: _reader.getDefaultTracker(),
        defaultSourceCode: _reader.getDefaultSourceCode(),
        integrations: integrations,
      );

  /// Extracts a ticket/issue key hint from raw CLI arguments — Java
  /// `McpCliHandler.extractKeyHint` parity (dm.ai #577): the first
  /// `key=`/`ticketKey=`/`ticket=`/`issueKey=` pair wins, then the
  /// `--data`/`--stdin-data` JSON payload, then the first positional
  /// argument.
  String? _extractKeyHint(List<String> args) {
    String? firstPositional;
    for (var i = 0; i < args.length; i++) {
      final payload = _dataFlagPayload(args, i);
      if (payload != null) {
        final hint = _keyFromJson(payload);
        if (hint != null) return hint;
        i++; // consume the payload argument
        continue;
      }
      final currentArg = args[i];
      final pair = _keyPairValue(currentArg);
      if (pair != null) return pair;
      if (_isPositionalArg(currentArg) && firstPositional == null) {
        firstPositional = currentArg;
      }
    }
    // The Dart CLI carries the tool's JSON payload as the positional
    // argument (Java's equivalent arrives via --data), so a positional is
    // first probed as a JSON payload before being used as a bare key.
    if (firstPositional == null) return null;
    return _keyFromJson(firstPositional) ?? firstPositional;
  }

  /// The payload after a `--data`/`--stdin-data` flag at position [i], or
  /// `null` when there is no such flag with a following argument.
  String? _dataFlagPayload(List<String> args, int i) {
    final flag = args[i];
    final isDataFlag = flag == '--data' || flag == '--stdin-data';
    return isDataFlag && i + 1 < args.length ? args[i + 1] : null;
  }

  /// The value of a `key=`/`ticketKey=`/`ticket=`/`issueKey=` pair
  /// argument, or `null` when [arg] is not such a pair.
  String? _keyPairValue(String arg) =>
      RegExp(r'^(?:key|ticketKey|ticket|issueKey)=(.*)$')
          .firstMatch(arg)
          ?.group(1);

  /// Whether [arg] can serve as a positional argument (no `--` flag
  /// prefix, no `=` pair form).
  bool _isPositionalArg(String arg) =>
      !arg.startsWith('--') && !arg.contains('=');

  /// The key fields of a `--data` JSON payload, in the same field order as
  /// the JS bridge's `extractKeyHint` (`key`, `ticketKey`, `ticket`,
  /// `issueKey`, `id`).
  String? _keyFromJson(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        for (final field in const [
          'key',
          'ticketKey',
          'ticket',
          'issueKey',
          'id'
        ]) {
          final value = decoded[field];
          if (value != null) return value.toString();
        }
      }
    } on FormatException {
      // Not a JSON payload — keep scanning the remaining arguments.
    }
    return null;
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

  /// Dispatches a direct tool invocation: `dmtools <tool> [args...]`.
  ///
  /// Java `processMcpCommand` order: output-format flags are stripped from
  /// the tool args first, a `--help`/`-h` among them shows the tool's
  /// schema (the tools list filtered by tool name), otherwise the tool
  /// executes with arguments built Java-style (see [_buildToolArgs]) and
  /// the JSON result is printed. Returns `0` on success, `1` when the
  /// tool is unknown or the result is an error.
  Future<int> _toolDispatch(String toolName, List<String> rest) async {
    final cleaned = _extractFormatFlags(rest);
    final registry = createDefaultToolRegistry();
    if (cleaned.any(_isHelpFlag)) {
      // gh-136 review: an unresolvable name on the help path answers like
      // the invocation path instead of printing an empty tools list;
      // `dmtools list <free-text>` keeps its exit-0 search semantics.
      if (!registry.hasTool(toolName)) {
        _writer('Error: unknown tool: $toolName');
        _writer('Run "dmtools list" for available tools');
        return 1;
      }
      return _listTools([toolName]);
    }
    // Java McpCliHandler parity (dm.ai #577): the alias resolves with a
    // key hint extracted from the raw arguments, so `gh-123` /
    // `owner/repo#123` keys route tracker_* aliases to GitHub regardless
    // of DEFAULT_TRACKER.
    final resolvedTool = _resolveToolName(toolName,
        registry: registry, keyHint: _extractKeyHint(cleaned));
    if (resolvedTool == null) {
      _writer('Error: unknown tool: $toolName');
      _writer('Run "dmtools list" for available tools');
      return 1;
    }
    try {
      final params =
          registry.getTool(resolvedTool)?.params ?? const <ToolParam>[];
      final args = _buildToolArgs(params, cleaned);
      final result = ToolBridge(registry: registry).execute(resolvedTool, args);
      _writer(result);
      return _isToolError(result) ? 1 : 0;
    } catch (e) {
      _writer('Error: $e');
      return 1;
    }
  }

  /// Builds the tool arguments map, Java `parseToolArguments`-style:
  /// tokens are processed in order (`--data`/`--stdin-data` JSON merge
  /// with a failure falling back to `data`, `--format`, `--md`, ignored
  /// shell flags, `--key value`/`--key=value`, bare `key=value`), then
  /// positional arguments are mapped onto the tool's [params] LAST so
  /// they override same-named earlier keys.
  Map<String, dynamic> _buildToolArgs(
      List<ToolParam> params, List<String> tokens) {
    final arguments = <String, dynamic>{};
    final positional = _parseToolArguments(tokens, arguments);
    if (positional.isNotEmpty) {
      _mapPositionalArguments(arguments, params, positional);
    }
    return arguments;
  }

  /// Parses tool-argument [tokens] into [arguments] in token order,
  /// collecting positional arguments (mapped onto the schema later).
  ///
  /// Ports the Java `parseToolArguments` token loop: `--data`/`--stdin-data`
  /// merge a JSON object (a parse failure stores the raw string under
  /// `data`), `--format`/`--md` set `format`, shell-level flags
  /// (`--verbose`, `--debug`) are ignored, any other `--key value` /
  /// `--key=value` names an argument (there is no `--file` special case —
  /// Java has none), and a bare `key=value` token with a valid identifier
  /// before `=` names an argument too. Everything else is positional.
  static List<String> _parseToolArguments(
      List<String> tokens, Map<String, dynamic> arguments) {
    final positional = <String>[];
    var i = 0;
    while (i < tokens.length) {
      final arg = tokens[i++];
      if (_isValueFlag(arg)) {
        i = _consumeValueFlag(arg, tokens, i, arguments);
      } else if (arg == '--md') {
        arguments['format'] = 'md';
      } else if (_shellFlags.contains(arg)) {
        // Shell-level flags handled by the wrapper script; ignored.
      } else {
        i = _consumeFlagOrPositional(arg, tokens, i, arguments, positional);
      }
    }
    return positional;
  }

  /// Dispatches one non-value token: a generic `--key` flag, a bare
  /// `key=value` named token, or a positional. Returns the next [i].
  static int _consumeFlagOrPositional(String arg, List<String> tokens, int i,
      Map<String, dynamic> arguments, List<String> positional) {
    if (arg.startsWith('--')) {
      return _consumeNamedFlag(arguments, arg, tokens, i);
    }
    if (_namedTokenPattern.hasMatch(arg)) {
      _consumeNamedToken(arguments, arg);
    } else {
      positional.add(arg);
    }
    return i;
  }

  /// Whether [arg] is a flag whose next token is its value.
  static bool _isValueFlag(String arg) =>
      arg == '--data' || arg == '--stdin-data' || arg == '--format';

  /// Consumes the value token of a `--data`/`--stdin-data`/`--format`
  /// flag ([i] already points past the flag token); a valueless trailing
  /// flag is ignored — the Java loop skips it the same way.
  static int _consumeValueFlag(
      String arg, List<String> tokens, int i, Map<String, dynamic> arguments) {
    if (i >= tokens.length) return i;
    final value = tokens[i++];
    if (arg == '--format') {
      arguments['format'] = value;
    } else {
      _parseJsonIntoArguments(value, arguments);
    }
    return i;
  }

  /// Stores a bare `key=value` token as a named argument.
  static void _consumeNamedToken(Map<String, dynamic> arguments, String arg) {
    final eq = arg.indexOf('=');
    arguments[arg.substring(0, eq)] = arg.substring(eq + 1);
  }

  /// Parses [json] and merges its keys into [arguments]; anything that is
  /// not a JSON object (a parse failure included) stores the raw string
  /// under `data` (Java `parseJsonIntoArguments` — never an error).
  static void _parseJsonIntoArguments(
      String json, Map<String, dynamic> arguments) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        arguments.addAll(decoded);
        return;
      }
    } on FormatException {
      // fall through to the raw-string fallback
    }
    arguments['data'] = json;
  }

  /// Strips output-format flags from tool args, Java `extractFormatFlag`
  /// (:219-253): `--toon`, `--mini`, `--output <v>` (consuming the value),
  /// and `--output=<v>` never reach the tool arguments. Every position
  /// counts — these sit after the tool name, i.e. Java positions ≥ 2.
  ///
  /// The captured format selects Java's output formatter, which this port
  /// lacks, so it is dropped; only the stripping is observable. A
  /// trailing `--output` without a value stays (Java keeps it, and the
  /// valueless flag is then ignored).
  static List<String> _extractFormatFlags(List<String> rest) {
    final cleaned = <String>[];
    for (var i = 0; i < rest.length; i++) {
      final arg = rest[i];
      if (arg == '--toon' || arg == '--mini' || arg.startsWith('--output=')) {
        continue;
      }
      if (arg == '--output' && i + 1 < rest.length) {
        i++; // skip the consumed format value
        continue;
      }
      cleaned.add(arg);
    }
    return cleaned;
  }

  /// Whether [arg] requests a tool's schema instead of execution.
  static bool _isHelpFlag(String arg) => arg == '--help' || arg == '-h';

  /// Maps positionals onto the schema [params] in declaration order,
  /// mirroring Java `mapPositionalArguments` (which runs AFTER token
  /// parsing, so mapped values override same-named earlier keys): a
  /// trailing array param collects every remaining positional; a mid-list
  /// array param reserves one positional per trailing param; regular
  /// params take one value each; extra positionals are ignored. Tools
  /// without params fall back to `arg0`, `arg1`, …
  static void _mapPositionalArguments(
      Map<String, dynamic> args, List<ToolParam> params, List<String> pos) {
    if (params.isEmpty) {
      for (var i = 0; i < pos.length; i++) {
        args['arg$i'] = pos[i];
      }
      return;
    }
    var argIndex = 0;
    for (var i = 0; i < params.length && argIndex < pos.length; i++) {
      final param = params[i];
      if (param.type != 'array') {
        args[param.name] = pos[argIndex++];
      } else if (i == params.length - 1) {
        args[param.name] = pos.sublist(argIndex); // trailing array: the rest
        return;
      } else {
        argIndex =
            _assignMidArray(args, param, params.length - i - 1, pos, argIndex);
      }
    }
  }

  /// Assigns a mid-list array [param], reserving one positional per
  /// [trailing] param; returns the next unmapped positional index.
  static int _assignMidArray(Map<String, dynamic> args, ToolParam param,
      int trailing, List<String> pos, int argIndex) {
    var arrayEnd = pos.length - trailing;
    if (arrayEnd < argIndex) arrayEnd = argIndex;
    args[param.name] = pos.sublist(argIndex, arrayEnd);
    return arrayEnd;
  }

  /// Consumes a `--key value` / `--key=value` flag into [arguments].
  ///
  /// A trailing flag without a value is ignored. Returns the next
  /// unconsumed token index.
  static int _consumeNamedFlag(
      Map<String, dynamic> arguments, String arg, List<String> tokens, int i) {
    final key = arg.substring(2);
    final eq = key.indexOf('=');
    if (eq >= 0) {
      arguments[key.substring(0, eq)] = key.substring(eq + 1);
    } else if (i < tokens.length) {
      arguments[key] = tokens[i++]; // the next token was consumed as the value
    }
    return i;
  }

  /// Shell-level flags handled elsewhere and never treated as named args.
  static const _shellFlags = {'--verbose', '--debug'};

  /// Bare `key=value` positional tokens that name an argument.
  static final _namedTokenPattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*=.*');

  /// Returns `true` when [result] is a JSON object containing an `error` key.
  static bool _isToolError(String result) {
    try {
      final decoded = jsonDecode(result);
      return decoded is Map && decoded.containsKey('error');
    } catch (_) {
      return false;
    }
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
  The tool automatically loads environment variables from dmtools.env
  (project root first, then the current working directory).

  Common variables:
  - JIRA_BASE_PATH, JIRA_EMAIL, JIRA_API_TOKEN
  - CONFLUENCE_BASE_PATH, CONFLUENCE_API_TOKEN
  - FIGMA_API_KEY
  - GEMINI_API_KEY, OPENAI_API_KEY
  - SOURCE_GITHUB_TOKEN, GITLAB_TOKEN, BITBUCKET_TOKEN''';
}
