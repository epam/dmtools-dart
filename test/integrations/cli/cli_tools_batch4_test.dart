import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the batch-4 CLI tool (`cli_list_allowed_commands`) added to
/// [CliToolExecutor] and [cliTools].
void main() {
  tearDown(PropertyReader.clearOverrides);
  catalogTests();
  listAllowedCommandsTests();
}

/// Catalog checks for the new tool.
void catalogTests() {
  group('cliTools catalog (batch 4)', () {
    final tools = cliTools();

    test('registers three tools', () {
      expect(tools, hasLength(3));
    });

    test('cli_list_allowed_commands has correct metadata', () {
      final tool = tools.firstWhere(
        (t) => t.name == 'cli_list_allowed_commands',
      );
      expect(tool.integration, 'cli');
      expect(tool.category, 'system');
      expect(tool.params, isEmpty);
    });
  });
}

/// [CliToolExecutor.getAllowedCommands] and dispatch tests.
void listAllowedCommandsTests() {
  group('cli_list_allowed_commands', () {
    test('returns the default whitelist as a sorted array', () {
      final executor = CliToolExecutor();
      final commands = executor.getAllowedCommands();
      expect(commands, containsAll(defaultAllowedCommands));
      expect(commands, equals(commands.toList()..sort()));
    });

    test('includes env-extended commands', () {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'echo,make'});
      final executor = CliToolExecutor(PropertyReader());
      final commands = executor.getAllowedCommands();
      expect(commands, containsAll(['echo', 'make', 'git']));
    });

    test('routes through execute dispatch as a commands array', () async {
      PropertyReader.setOverrides({'CLI_ALLOWED_COMMANDS': 'echo'});
      final executor = CliToolExecutor(PropertyReader());
      final result = await executor.execute('cli_list_allowed_commands', {});
      final commands = (result['commands'] as List).cast<String>();
      expect(commands, containsAll(defaultAllowedCommands));
      expect(commands, contains('echo'));
      expect(commands, equals(commands.toList()..sort()));
    });
  });
}
