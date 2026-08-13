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
export 'src/integrations/cli/cli_tools.dart';
export 'src/integrations/ai/ai_http.dart';
export 'src/integrations/base_http_client.dart';
export 'src/integrations/ai/ai_tools.dart';
export 'src/integrations/ai/gemini_client.dart';
export 'src/integrations/ai/ollama_client.dart';
export 'src/integrations/ai/openai_client.dart';
export 'src/integrations/file/file_tools.dart';
export 'src/integrations/github/github_client.dart';
export 'src/integrations/github/github_http_client.dart';
export 'src/integrations/github/github_tools.dart';
export 'src/integrations/confluence/confluence_client.dart';
export 'src/integrations/confluence/confluence_http_client.dart';
export 'src/integrations/confluence/confluence_tools.dart';
export 'src/integrations/gitlab/gitlab_client.dart';
export 'src/integrations/gitlab/gitlab_http_client.dart';
export 'src/integrations/gitlab/gitlab_tools.dart';
export 'src/integrations/jira/jira_client.dart';
export 'src/integrations/jira/jira_http_client.dart';
export 'src/integrations/jira/jira_tools.dart';
export 'src/mcp/tool_definition.dart';
export 'src/mcp/tool_param.dart';
export 'src/mcp/tool_registry.dart';
export 'src/version.dart';
