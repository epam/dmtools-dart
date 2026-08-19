import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  group('version', () {
    test('versionLine follows the Java CLI format', () {
      expect(versionLine(), 'dmtools $dmtoolsVersion');
    });

    test('version constant matches pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match =
          RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml has no version field');
      expect(dmtoolsVersion, match!.group(1),
          reason: 'lib/src/version.dart must mirror pubspec.yaml — bump both '
              '(release-cli.yml re-syncs it from the tag at build time).');
    });
  });
}
