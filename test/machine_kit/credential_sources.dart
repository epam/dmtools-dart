// Shared file access for the gh-63 credential regression tests. The suite
// spans three test files — the installer pins, the trace-script pins, and
// the sandbox execution tests — and all of them must look at the same
// sources, so the paths and the reader live here exactly once.
import 'dart:io';

import 'package:test/test.dart';

const workflowPath = '.github/workflows/ai-teammate-issues.yml';
const templatePath = 'machine-kit/templates/ai-teammate-issues.yml';
const installerPath = 'machine-kit/scripts/install-source-git-credentials.sh';
const traceScriptPath = 'machine-kit/scripts/trace-git-credentials.sh';

/// All YAML files that carry the credential machinery (workflow + template —
/// they must not drift apart, PR #68 review thread 6).
final List<String> credentialYamlFiles = [workflowPath, templatePath];

/// Reads [path], failing the test with a clear reason when the file is
/// absent (a deleted script should read as a missing pin, not as an I/O
/// exception).
String readSource(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('missing expected file: $path');
  }
  return file.readAsStringSync();
}
