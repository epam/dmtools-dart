import 'dart:io';

import 'package:dmtools/src/cli/cli_dispatcher.dart';
import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/pack/agent_pack_resolver.dart';
import 'package:dmtools/src/pack/pack_provenance.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// gh-375 pack provenance on failure: a raw JS error escaping the job run of
/// a versioned agent pack logs the pack's identity line before the error
/// propagates, so the failure names the exact zip that ran. Non-matching
/// failures and non-pack targets stay untouched; success is noise-free.
class _FakePackResolver extends AgentPackResolver {
  _FakePackResolver(this._resolved);

  final ResolvedPack _resolved;

  @override
  bool isPack(String? runArg) => true;

  @override
  ResolvedPack resolve(String runArg, {String? githubToken}) => _resolved;
}

void main() {
  late Directory packRoot;
  late List<String> lines;

  setUp(() {
    PropertyReader.testIsolation = true;
    packRoot = Directory.systemTemp.createTempSync('prov-pack-');
    addTearDown(() => packRoot.deleteSync(recursive: true));
    PackProvenance(
      name: 'it-pack',
      version: '1.2.3',
      sha256: 'abc123',
      sourceUrl: 'https://example.test/it-pack-1.2.3.zip',
    ).write(packRoot);
    lines = [];
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    PropertyReader.testIsolation = false;
  });

  CliDispatcher dispatcherOf(File entry) {
    lines = [];
    return CliDispatcher(
      writer: lines.add,
      propertyReader: PropertyReader(),
      isTty: () => false,
      packResolver: _FakePackResolver(
        ResolvedPack(
          packRoot: packRoot,
          entryFile: entry,
          agent: 'it-pack',
          version: '1.2.3',
        ),
      ),
    );
  }

  File entryWith(String jsPath) => File(p.join(packRoot.path, 'entry.json'))
    ..writeAsStringSync('{"name":"JSRunner","params":{"jsPath":"$jsPath"}}');

  test('missing jsPath logs pack provenance before the error', () async {
    final dispatcher = dispatcherOf(entryWith('no-such-script.js'));
    final code = await dispatcher.dispatch(
      ['run', 'it-pack-1.2.3.zip'],
    );
    expect(code, 1);
    expect(
      lines.join('\n'),
      contains('pack provenance: name=it-pack version=1.2.3'),
    );
  });

  test('failed require module logs pack provenance', () async {
    final failing = File(p.join(packRoot.path, 'needs.js'))
      ..writeAsStringSync("function action(params) { require('./nope.js'); }");
    final dispatcher = dispatcherOf(entryWith(failing.path));
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 1);
    expect(lines.join('\n'), contains('pack provenance: name=it-pack'));
  });

  test('matching failure without a provenance file stays silent', () async {
    File(p.join(packRoot.path, '.provenance.json')).deleteSync();
    final dispatcher = dispatcherOf(entryWith('no-such-script.js'));
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 1);
    expect(lines.join('\n'), isNot(contains('pack provenance')));
  });

  test('non-matching failure rethrows without provenance line', () async {
    final entry = File(p.join(packRoot.path, 'entry.json'))
      ..writeAsStringSync('{"name":"no_such_agent_kind","params":{}}');
    final dispatcher = dispatcherOf(entry);
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 1);
    expect(lines.join('\n'), contains('Error:'));
    expect(lines.join('\n'), isNot(contains('pack provenance')));
  });

  test('successful pack run is provenance-noise-free', () async {
    final ok = File(p.join(packRoot.path, 'ok.js'))
      ..writeAsStringSync("function action(params) { return 'packed'; }");
    final dispatcher = dispatcherOf(entryWith(ok.path));
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 0);
    expect(lines.join('\n'), contains('packed'));
    expect(lines.join('\n'), isNot(contains('pack provenance')));
  });
}
