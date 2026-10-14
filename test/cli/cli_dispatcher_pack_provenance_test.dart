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
  _testMissingJsPathLogsProvenance();
  _testFailedRequireLogsProvenance();
  _testMissingProvenanceFileStaysSilent();
  _testNonMatchingFailureHasNoProvenanceLine();
  _testSuccessfulRunIsNoiseFree();
}

CliDispatcher _dispatcherOf(
  Directory packRoot,
  List<String> lines,
  File entry,
) {
  return CliDispatcher(
    writer: lines.add,
    propertyReader: PropertyReader(),
    isTty: () => false,
    pools: CliDispatcherPools(
      packResolver: _FakePackResolver(
        ResolvedPack(
          packRoot: packRoot,
          entryFile: entry,
          agent: 'it-pack',
          version: '1.2.3',
        ),
      ),
    ),
  );
}

Directory _newPack() {
  final packRoot = Directory.systemTemp.createTempSync('prov-pack-');
  addTearDown(() => packRoot.deleteSync(recursive: true));
  PackProvenance(
    name: 'it-pack',
    version: '1.2.3',
    sha256: 'abc123',
    sourceUrl: 'https://example.test/it-pack-1.2.3.zip',
  ).write(packRoot);
  return packRoot;
}

File _entryWith(Directory packRoot, String jsPath) =>
    File(p.join(packRoot.path, 'entry.json'))
      ..writeAsStringSync('{"name":"JSRunner","params":{"jsPath":"$jsPath"}}');

void _isolatePropertyReader() {
  PropertyReader.testIsolation = true;
  setUp(() {
    PropertyReader.testIsolation = true;
  });
  tearDown(() {
    PropertyReader.clearOverrides();
    PropertyReader.testIsolation = false;
  });
}

void _testMissingJsPathLogsProvenance() {
  _isolatePropertyReader();
  test('missing jsPath logs pack provenance before the error', () async {
    final packRoot = _newPack();
    final lines = <String>[];
    final dispatcher =
        _dispatcherOf(packRoot, lines, _entryWith(packRoot, 'no-such.js'));
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 1);
    expect(
      lines.join('\n'),
      contains('pack provenance: name=it-pack version=1.2.3'),
    );
  });
}

void _testFailedRequireLogsProvenance() {
  _isolatePropertyReader();
  test('failed require module logs pack provenance', () async {
    final packRoot = _newPack();
    final failing = File(p.join(packRoot.path, 'needs.js'))
      ..writeAsStringSync("function action(params) { require('./nope.js'); }");
    final lines = <String>[];
    final dispatcher =
        _dispatcherOf(packRoot, lines, _entryWith(packRoot, failing.path));
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 1);
    expect(lines.join('\n'), contains('pack provenance: name=it-pack'));
  });
}

void _testMissingProvenanceFileStaysSilent() {
  _isolatePropertyReader();
  test('matching failure without a provenance file stays silent', () async {
    final packRoot = _newPack();
    File(p.join(packRoot.path, '.provenance.json')).deleteSync();
    final lines = <String>[];
    final dispatcher =
        _dispatcherOf(packRoot, lines, _entryWith(packRoot, 'no-such.js'));
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 1);
    expect(lines.join('\n'), isNot(contains('pack provenance')));
  });
}

void _testNonMatchingFailureHasNoProvenanceLine() {
  _isolatePropertyReader();
  test('non-matching failure rethrows without provenance line', () async {
    final packRoot = _newPack();
    final entry = File(p.join(packRoot.path, 'entry.json'))
      ..writeAsStringSync('{"name":"no_such_agent_kind","params":{}}');
    final lines = <String>[];
    final dispatcher = _dispatcherOf(packRoot, lines, entry);
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 1);
    expect(lines.join('\n'), contains('Error:'));
    expect(lines.join('\n'), isNot(contains('pack provenance')));
  });
}

void _testSuccessfulRunIsNoiseFree() {
  _isolatePropertyReader();
  test('successful pack run is provenance-noise-free', () async {
    final packRoot = _newPack();
    final ok = File(p.join(packRoot.path, 'ok.js'))
      ..writeAsStringSync("function action(params) { return 'packed'; }");
    final lines = <String>[];
    final dispatcher =
        _dispatcherOf(packRoot, lines, _entryWith(packRoot, ok.path));
    final code = await dispatcher.dispatch(['run', 'it-pack-1.2.3.zip']);
    expect(code, 0);
    expect(lines.join('\n'), contains('packed'));
    expect(lines.join('\n'), isNot(contains('pack provenance')));
  });
}
