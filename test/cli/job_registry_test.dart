import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  group('JobRegistry.isKnownJob', () {
    test('accepts every registered job name', () {
      for (final job in JobRegistry.knownJobs) {
        expect(JobRegistry.isKnownJob(job), isTrue, reason: job);
      }
    });

    test('matches case-insensitively', () {
      expect(JobRegistry.isKnownJob('CodeGenerator'), isTrue);
      expect(JobRegistry.isKnownJob('CLIAGENT'), isTrue);
      expect(JobRegistry.isKnownJob('JsRunner'), isTrue);
    });

    test('rejects unknown names', () {
      expect(JobRegistry.isKnownJob('notajob'), isFalse);
      expect(JobRegistry.isKnownJob('jira'), isFalse);
      expect(JobRegistry.isKnownJob(''), isFalse);
    });
  });

  group('JobRegistry.displayJobs', () {
    test('contains 23 unique job names', () {
      expect(JobRegistry.displayJobs.length, 23);
      expect(JobRegistry.displayJobs.toSet().length, 23);
    });

    test('every display job is a known job', () {
      for (final job in JobRegistry.displayJobs) {
        expect(JobRegistry.knownJobs.contains(job), isTrue, reason: job);
      }
    });

    test('hides aliases but keeps them dispatchable', () {
      const aliases = [
        'diagramcreator',
        'reportgeneratorjob',
        'reportvisualizerjob',
        'kbprocessingjob',
      ];
      for (final alias in aliases) {
        expect(JobRegistry.displayJobs, isNot(contains(alias)));
        expect(JobRegistry.isKnownJob(alias), isTrue);
      }
    });
  });
}
