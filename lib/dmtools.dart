/// Pure Dart port of DMTools — enterprise dark-factory orchestrator.
///
/// See GOAL.md for the mission, constraints and phases.
library;

export 'src/cli/cli_args.dart';
export 'src/cli/cli_dispatcher.dart';
export 'src/cli/config_merger.dart';
export 'src/cli/doctor_command.dart';
export 'src/cli/encoding_detector.dart';
export 'src/cli/job_registry.dart';
export 'src/cli/run_command_processor.dart';
export 'src/config/property_reader.dart';
export 'src/config/property_reader_ai_getters.dart';
export 'src/config/property_reader_getters.dart';
export 'src/integrations/jira/jira_client.dart';
export 'src/integrations/jira/jira_http_client.dart';
export 'src/integrations/jira/jira_tools.dart';
export 'src/mcp/tool_definition.dart';
export 'src/mcp/tool_param.dart';
export 'src/mcp/tool_registry.dart';
export 'src/version.dart';
