import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the [cliTools] catalog, whitelist mechanics, and
/// [CliToolExecutor.executeCommand].
void main() {
  tearDown(PropertyReader.clearOverrides);
  toolCatalogTests();
  whitelistTests();
  executeCommandTests();
  executeDispatchTests();
}

/// Catalog shape: tool name, integration, params.
void toolCatalogTests() {
  group('cliTools catalog', () {
    final tools = cliTools();

    test('registers two tools', () {
      expect(tools, hasLength(2));
    });

    test('cli_execute_command has correct metadata', () {
      final tool = tools.first;
      expect(tool.name, 'cli_execute_command');
      expect(tool.integration, 'cli');
      expect(tool.category, 'system');
    });

    test('cli_execute_command declares command and optional args', () {
      final tool = tools.first;
      expect(tool.params.map((p) => p.name), ['command', 'args']);
      expect(
        tool.params.firstWhere((p) => p.name == 'command').required,
        isTrue,
      );
      final argsParam = tool.params.firstWhere((p) => p.name == 'args');
      expect(argsParam.required, isFalse);
      expect(argsParam.type, 'array');
    });
  });
}

/// Default whitelist, `CLI_ALLOWED_COMMANDS` extension, rejection.
void whitelistTests() {
  group('default whitelist', () {
    final executor = CliToolExecutor();

    test('includes all built-in commands', () {
      expect(executor.allowedCommands, containsAll(defaultAllowedCommands));
    });

    test('rejects a non-whitelisted command', () {
      expect(executor.isAllowed('rm'), isFalse);
      expect(executor.isAllowed('curl'), isFalse);
      expect(executor.isAllowed('sudo'), isFalse);
    });

    test('accepts whitelisted commands', () {
      expect(executor.isAllowed('git'), isTrue);
      expect(executor.isAllowed('docker'), isTrue);
      expect(executor.isAllowed('terraform'), isTrue);
    });
  });

  group('CLI_ALLOWED_COMMANDS extension', () {
    test('adds extra commands from the env var', () {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'echo,sed'});
      final executor = CliToolExecutor(PropertyReader());
      expect(executor.isAllowed('echo'), isTrue);
      expect(executor.isAllowed('sed'), isTrue);
      expect(executor.isAllowed('git'), isTrue);
      expect(executor.isAllowed('rm'), isFalse);
    });

    test('still rejects when no property reader is supplied', () {
      final executor = CliToolExecutor();
      expect(executor.isAllowed('echo'), isFalse);
    });

    test('handles blank and whitespace entries', () {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': ' , echo , , '});
      final executor = CliToolExecutor(PropertyReader());
      expect(executor.isAllowed('echo'), isTrue);
      expect(
        executor.allowedCommands.length,
        defaultAllowedCommands.length + 1,
      );
    });
  });
}

/// [CliToolExecutor.executeCommand] via `Process.run`.
void executeCommandTests() {
  group('CliToolExecutor.executeCommand', () {
    test('executes a whitelisted command and captures output', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'echo'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.executeCommand('echo', ['hello']);
      expect(result['stdout'].trim(), 'hello');
      expect(result['stderr'], '');
      expect(result['exitCode'], 0);
    });

    test('captures non-zero exit code', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'false'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.executeCommand('false');
      expect(result['exitCode'], 1);
    });

    test('throws ArgumentError for a non-whitelisted command', () {
      final executor = CliToolExecutor();
      expect(
        () => executor.executeCommand('rm', ['-rf', '/']),
        throwsArgumentError,
      );
    });

    test('runs without args when none are given', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'true'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.executeCommand('true');
      expect(result['exitCode'], 0);
    });
  });
}

/// [CliToolExecutor.execute] dispatch routing.
void executeDispatchTests() {
  group('CliToolExecutor.execute dispatch', () {
    test('routes cli_execute_command with args list', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'echo'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.execute('cli_execute_command', {
        'command': 'echo',
        'args': ['dispatched'],
      });
      expect(result['stdout'].trim(), 'dispatched');
      expect(result['exitCode'], 0);
    });

    test('routes cli_execute_command without args', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'true'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.execute('cli_execute_command', {
        'command': 'true',
      });
      expect(result['exitCode'], 0);
    });

    test('rejects a non-whitelisted command through dispatch', () {
      final executor = CliToolExecutor();
      expect(
        () => executor.execute('cli_execute_command', {'command': 'curl'}),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for an unknown tool', () {
      final executor = CliToolExecutor();
      expect(
        () => executor.execute('cli_unknown', {'command': 'git'}),
        throwsArgumentError,
      );
    });
  });
}
