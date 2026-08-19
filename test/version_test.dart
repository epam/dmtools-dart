import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  group('version', () {
    test('versionLine follows the Java CLI format', () {
      expect(versionLine(), 'dmtools $dmtoolsVersion');
    });

    test('version constant matches pubspec', () {
      expect(dmtoolsVersion, '0.1.0');
    });
  });
}
