/// Builds final CLI commands by aggregating `cliPrompt` and `cliPrompts`.
///
/// Dart port of Java `CliCommandBuilder`. The combined prompt is written to
/// a temporary file and the file path is appended (quoted) to each command —
/// the same cross-platform approach as the Java original.
library;

import 'dart:io';

import 'instruction_processor.dart';

/// Builds final CLI commands with aggregated prompt injection.
class CliCommandBuilder {
  /// Creates a command builder.
  const CliCommandBuilder();

  /// Resolves effective CLI prompts by merging base with tracker-specific.
  ///
  /// When [cliPromptsByTracker] contains an entry for [trackerType], the
  /// tracker-specific prompts are appended to [baseCliPrompts]. If
  /// [trackerType] is null or blank, `"ado"` is used (Java default).
  static List<String>? resolveCliPrompts(
    List<String>? baseCliPrompts,
    Map<String, List<String>>? cliPromptsByTracker,
    String? trackerType,
  ) {
    var effectiveTracker = trackerType;
    if (effectiveTracker == null || effectiveTracker.trim().isEmpty) {
      effectiveTracker = 'ado';
    }
    if (cliPromptsByTracker == null ||
        !cliPromptsByTracker.containsKey(effectiveTracker)) {
      return baseCliPrompts;
    }
    final trackerPrompts = cliPromptsByTracker[effectiveTracker];
    if (trackerPrompts == null || trackerPrompts.isEmpty) {
      return baseCliPrompts;
    }
    return [
      if (baseCliPrompts != null) ...baseCliPrompts,
      ...trackerPrompts,
    ];
  }

  /// Builds the final CLI commands for execution.
  ///
  /// [cliCommands] — base commands from the job config.
  /// [cliPrompt] — single base prompt (may be null).
  /// [cliPrompts] — array of prompt entries (may be null).
  /// [cliPromptsByTracker] — tracker-specific prompts (may be null).
  /// [trackerType] — current tracker type for prompt resolution.
  /// [workingDirectory] — base dir for resolving file-path references in
  /// the combined prompt (passed to [InstructionProcessor]).
  ///
  /// Returns commands with the combined prompt appended, or the original
  /// commands when no prompt is provided.
  List<String> buildCommands(
    List<String> cliCommands,
    String? cliPrompt,
    List<String>? cliPrompts,
    Map<String, List<String>>? cliPromptsByTracker, {
    String? trackerType,
    String? workingDirectory,
  }) {
    if (cliCommands.isEmpty) return cliCommands;
    final merged = resolveCliPrompts(
      cliPrompts,
      cliPromptsByTracker,
      trackerType,
    );
    final combined = _buildCombinedPrompt(
      cliPrompt,
      merged,
      workingDirectory,
    );
    if (combined == null || combined.trim().isEmpty) return cliCommands;
    return _appendPromptToCommands(cliCommands, combined);
  }

  /// Combines [cliPrompt] and [cliPrompts] into a single prompt string.
  ///
  /// Non-blank entries are joined with a double-newline separator. The
  /// combined prompt is then enriched by [InstructionProcessor] (embeds
  /// file content, annotates GitHub PR and Jira references). Returns
  /// `null` when the result is empty.
  ///
  /// Mirrors `InstructionProcessor.buildCombinedPrompt()`.
  String? _buildCombinedPrompt(
    String? cliPrompt,
    List<String>? cliPrompts,
    String? workingDirectory,
  ) {
    final parts = <String>[];
    if (cliPrompt != null && cliPrompt.trim().isNotEmpty) {
      parts.add(cliPrompt.trim());
    }
    if (cliPrompts != null) {
      for (final p in cliPrompts) {
        if (p.trim().isNotEmpty) parts.add(p.trim());
      }
    }
    if (parts.isEmpty) return null;
    final combined = parts.join('\n\n');
    return InstructionProcessor(workingDirectory: workingDirectory)
        .process(combined);
  }

  /// Appends a prompt to each command via a temporary file.
  ///
  /// The prompt is written to a temp file (UTF-8) and the file path is
  /// appended as a quoted parameter to each non-empty command. This is
  /// cross-platform compatible — the CLI tool reads `$1` to get the prompt.
  ///
  /// Mirrors `CliExecutionHelper.appendPromptToCommands()`.
  List<String> _appendPromptToCommands(List<String> commands, String prompt) {
    final promptFile = _createPromptFile(prompt);
    if (promptFile == null) return commands;
    return commands.map((cmd) {
      if (cmd.trim().isEmpty) return cmd;
      return '$cmd "${promptFile.path}"';
    }).toList();
  }

  /// Creates a temporary file containing [prompt], or null on failure.
  File? _createPromptFile(String prompt) {
    try {
      final file = File(
        '${Directory.systemTemp.path}/dmtools_cli_prompt_'
        '${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      file.writeAsStringSync(prompt);
      return file;
    } catch (_) {
      return null;
    }
  }
}
