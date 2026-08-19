/// Registry of job names dispatchable by `dmtools run <job-name>`.
///
/// Ported from the `switch` in the Java `JobRunner.createJobInstance()`:
/// names are matched case-insensitively, and several jobs accept legacy
/// aliases (e.g. `diagramcreator`) that stay dispatchable through
/// [knownJobs] but are hidden from [displayJobs].
library;

/// Known job names for the `dmtools run` dispatcher.
class JobRegistry {
  /// Every job name and alias accepted by `dmtools run` (lowercase).
  static const Set<String> knownJobs = {
    'presalesupport',
    'documentationgenerator',
    'requirementscollector',
    'testcasesgenerator',
    'instructionsgenerator',
    'solutionarchitecturecreator',
    'diagramscreator',
    'diagramcreator',
    'codegenerator',
    'devproductivityreport',
    'baproductivityreport',
    'businessanalyticdorgeneration',
    'qaproductivityreport',
    'reportgenerator',
    'reportgeneratorjob',
    'reportvisualizer',
    'reportvisualizerjob',
    'expert',
    'teammate',
    'cliagent',
    'sourcecodetrackersyncjob',
    'sourcecodecommittrackersyncjob',
    'userstorygenerator',
    'unittestsgenerator',
    'jsrunner',
    'kbprocessing',
    'kbprocessingjob',
  };

  /// Returns true if [name] is a known job name (case-insensitive).
  static bool isKnownJob(String name) => knownJobs.contains(name.toLowerCase());

  /// Returns the unique job names for display (deduplicated aliases).
  static List<String> get displayJobs => const [
        'presalesupport',
        'documentationgenerator',
        'requirementscollector',
        'testcasesgenerator',
        'instructionsgenerator',
        'solutionarchitecturecreator',
        'diagramscreator',
        'codegenerator',
        'devproductivityreport',
        'baproductivityreport',
        'businessanalyticdorgeneration',
        'qaproductivityreport',
        'reportgenerator',
        'reportvisualizer',
        'expert',
        'teammate',
        'cliagent',
        'sourcecodetrackersyncjob',
        'sourcecodecommittrackersyncjob',
        'userstorygenerator',
        'unittestsgenerator',
        'jsrunner',
        'kbprocessing',
      ];
}
