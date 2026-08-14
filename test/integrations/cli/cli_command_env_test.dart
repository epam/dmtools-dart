import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the `cli_execute_command_with_env` tool in [CliToolExecutor]
/// and [cliTools].
void main() {
  tearDown(PropertyReader.clearOverrides);
  catalogTests();
  executeCommandWithEnvTests();
  dispatchTests();
}

/// Catalog checks for `cli_execute_command_with_env`.
void catalogTests() {
  group('cliTools catalog: cli_execute_command_with_env', () {
    final tools = cliTools();

    test('registers three tools', () {
      expect(tools, hasLength(3));
    });

    test('cli_execute_command_with_env has correct metadata', () {
      final tool = tools.firstWhere(
        (t) => t.name == 'cli_execute_command_with_env',
      );
      expect(tool.integration, 'cli');
      expect(tool.category, 'system');
    });

    test('declares command, optional args, and optional env_vars', () {
      final tool = tools.firstWhere(
        (t) => t.name == 'cli_execute_command_with_env',
      );
      expect(
        tool.params.map((p) => p.name),
        ['command', 'args', 'env_vars'],
      );
      expect(
        tool.params.firstWhere((p) => p.name == 'command').required,
        isTrue,
      );
      final argsParam = tool.params.firstWhere((p) => p.name == 'args');
      expect(argsParam.required, isFalse);
      expect(argsParam.type, 'array');
      final envParam = tool.params.firstWhere((p) => p.name == 'env_vars');
      expect(envParam.required, isFalse);
      expect(envParam.type, 'object');
    });
  });
}

/// [CliToolExecutor.executeCommandWithEnv] via `Process.run`.
void executeCommandWithEnvTests() {
  group('CliToolExecutor.executeCommandWithEnv', () {
    test('runs with extra env vars visible to the process', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'printenv'});
      final executor = CliToolExecutor(PropertyReader());
      final env = {...Platform.environment, 'DMTOOLS_TEST_VAR': 'hello-env'};
      final result = await executor.executeCommandWithEnv(
        'printenv',
        ['DMTOOLS_TEST_VAR'],
        env,
      );
      expect(result['stdout'].trim(), 'hello-env');
      expect(result['exitCode'], 0);
    });

    test('runs without env vars when none are given', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'true'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.executeCommandWithEnv('true');
      expect(result['exitCode'], 0);
    });

    test('throws ArgumentError for a non-whitelisted command', () {
      final executor = CliToolExecutor();
      expect(
        () => executor.executeCommandWithEnv('curl', const [], {'X': '1'}),
        throwsArgumentError,
      );
    });
  });
}

/// [CliToolExecutor.execute] dispatch routing for `cli_execute_command_with_env`.
void dispatchTests() {
  group('execute dispatch: cli_execute_command_with_env', () {
    test('routes cli_execute_command_with_env with env vars', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'printenv'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.execute('cli_execute_command_with_env', {
        'command': 'printenv',
        'args': ['DMTOOLS_TEST_VAR'],
        'env_vars': {
          ...Platform.environment,
          'DMTOOLS_TEST_VAR': 'dispatched',
        },
      });
      expect(result['stdout'].trim(), 'dispatched');
      expect(result['exitCode'], 0);
    });

    test('routes cli_execute_command_with_env without env vars', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'true'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.execute('cli_execute_command_with_env', {
        'command': 'true',
      });
      expect(result['exitCode'], 0);
    });

    test('rejects a non-whitelisted command through dispatch', () {
      final executor = CliToolExecutor();
      expect(
        () => executor.execute('cli_execute_command_with_env', {
          'command': 'rm',
          'env_vars': {'X': '1'},
        }),
        throwsArgumentError,
      );
    });
  });
}
