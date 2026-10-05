import 'package:dmtools/src/integrations/confluence/confluence_markdown.dart';
import 'package:test/test.dart';

/// Dart mirror of the Java `ConfluenceExcerptInlinerTest`,
/// `ConfluenceMentionResolverTest`, and the `Content.getSpaceKey` checks
/// (dm.ai commits 932e0db0 / bb1b51e9, ticket gh-347). The resolver classes
/// take a [ConfluenceResolverClient], so the Java Mockito stubs become a
/// fake client here.
void main() {
  _excerptInlinerTests();
  _mentionResolverTests();
  _spaceKeyTests();
}

/// A [ConfluenceResolverClient] stub keyed like the Java Mockito stubs.
class _FakeResolverClient implements ConfluenceResolverClient {
  final pages = <String, Map<String, dynamic>?>{};
  final profiles = <String, String>{};
  final findCalls = <String>[];
  final profileCalls = <String>[];

  @override
  Map<String, dynamic>? findContent(String title, {String? spaceKey}) {
    findCalls.add('${spaceKey ?? ''}|$title');
    return pages['${spaceKey ?? ''}|$title'];
  }

  @override
  String? userProfile(String accountId) {
    profileCalls.add(accountId);
    if (!profiles.containsKey(accountId)) {
      throw StateError('profile lookup failed');
    }
    return profiles[accountId];
  }
}

Map<String, dynamic> _page(String id, String? space, String storage) => {
      'id': id,
      if (space != null) 'space': {'key': space},
      'body': {
        'storage': {'value': storage, 'representation': 'storage'},
      },
    };

String _excerptMacro(String macro, String name, String body) =>
    '<ac:structured-macro ac:name="$macro">'
    '<ac:parameter ac:name="name">$name</ac:parameter>'
    '<ac:rich-text-body>$body</ac:rich-text-body>'
    '</ac:structured-macro>';

String _includeMacro(
        String macro, String title, String? spaceKey, String name) =>
    '<ac:structured-macro ac:name="$macro" ac:schema-version="1">'
    '<ac:parameter ac:name="page"><ac:link><ri:page ri:content-title="$title"'
    '${spaceKey == null ? '' : ' ri:space-key="$spaceKey"'}/></ac:link>'
    '</ac:parameter>'
    '<ac:parameter ac:name="name">$name</ac:parameter>'
    '</ac:structured-macro>';

const _table =
    '<table><tbody><tr><th>Key</th><th>Value</th></tr><tr><td>alpha</td>'
    '<td>1</td></tr></tbody></table>';

void _excerptInlinerTests() {
  group('ConfluenceExcerptInliner (Java ConfluenceExcerptInliner parity)', () {
    _excerptInlinerResolutionTests();
    _excerptInlinerBlankNameTests();
    _excerptInlinerFallbackTests();
    _excerptInlinerNestingTests();
  });
}

void _excerptInlinerResolutionTests() {
  test('inlines named table excerpt from target page in source space', () {
    final client = _FakeResolverClient();
    final target = '<p>intro</p>'
        '${_excerptMacro('table-excerpt', 'Rules', _table)}'
        '${_excerptMacro('table-excerpt', 'Other', '<p>other</p>')}';
    client.pages['SPACE|Target'] = _page('2', 'SPACE', target);

    final result = ConfluenceExcerptInliner(client).inline(
      '<p>before</p>'
          '${_includeMacro('table-excerpt-include', 'Target', null, 'Rules')}'
          '<p>after</p>',
      'SPACE',
    );

    expect(result, contains(_table));
    expect(result, isNot(contains('other')));
    expect(result, isNot(contains('table-excerpt-include')));
    expect(result, startsWith('<p>before</p>'));
    expect(result, endsWith('<p>after</p>'));
  });

  test('name matching ignores case, whitespace and nbsp', () {
    final client = _FakeResolverClient();
    client.pages['SPACE|Target'] = _page(
      '2',
      'SPACE',
      _excerptMacro('excerpt', '&nbsp;Flow  Positions ', '<p>content</p>'),
    );

    final result = ConfluenceExcerptInliner(client).inline(
      _includeMacro('excerpt-include', 'Target', 'SPACE', 'flow positions'),
      'SPACE',
    );

    expect(result, '<p>content</p>');
  });
}

void _excerptInlinerBlankNameTests() {
  test('blank name uses the unnamed excerpt, else all of the kind', () {
    final client = _FakeResolverClient();
    client.pages['SPACE|P1'] = _page(
      '1',
      'SPACE',
      _excerptMacro('excerpt', 'Named', '<p>named</p>') +
          _excerptMacro('excerpt', '', '<p>unnamed</p>'),
    );
    client.pages['SPACE|P2'] = _page(
      '2',
      'SPACE',
      _excerptMacro('table-excerpt', 'A', '<p>a</p>') +
          _excerptMacro('table-excerpt', 'B', '<p>b</p>'),
    );
    final inliner = ConfluenceExcerptInliner(client);

    expect(
      inliner.inline(_includeMacro('excerpt-include', 'P1', null, ''), 'SPACE'),
      '<p>unnamed</p>',
    );
    expect(
      inliner.inline(
          _includeMacro('table-excerpt-include', 'P2', null, ''), 'SPACE'),
      '<p>a</p><p>b</p>',
    );
  });
}

void _excerptInlinerFallbackTests() {
  test('unresolvable includes are left untouched', () {
    final client = _FakeResolverClient();
    client.pages['SPACE|Present'] =
        _page('2', 'SPACE', _excerptMacro('excerpt', 'X', '<p>x</p>'));
    final inliner = ConfluenceExcerptInliner(client);

    final missingPage = _includeMacro('excerpt-include', 'Missing', null, 'X');
    final missingExcerpt =
        _includeMacro('excerpt-include', 'Present', null, 'Nope');
    expect(inliner.inline(missingPage, 'SPACE'), missingPage);
    expect(inliner.inline(missingExcerpt, 'SPACE'), missingExcerpt);
  });

  test('self-closing excerpt macros carry no body and are skipped', () {
    final client = _FakeResolverClient();
    client.pages['SPACE|Target'] = _page(
      '2',
      'SPACE',
      '<ac:structured-macro ac:name="excerpt"/>'
          '${_excerptMacro('excerpt', 'X', '<p>x</p>')}',
    );

    final result = ConfluenceExcerptInliner(client).inline(
      _includeMacro('excerpt-include', 'Target', null, 'X'),
      'SPACE',
    );

    expect(result, '<p>x</p>');
  });

  test('falls back to the default lookup when the space is unknown', () {
    final client = _FakeResolverClient();
    client.pages['|Target'] =
        _page('2', null, _excerptMacro('excerpt', 'X', '<p>x</p>'));

    final result = ConfluenceExcerptInliner(client).inline(
      _includeMacro('excerpt-include', 'Target', null, 'X'),
      null,
    );

    expect(result, '<p>x</p>');
  });
}

void _excerptInlinerNestingTests() {
  test('nested includes are resolved with the target page space', () {
    final client = _FakeResolverClient();
    client.pages['S1|Outer'] = _page(
      '1',
      'S2',
      _excerptMacro(
        'excerpt',
        'Outer',
        _includeMacro('excerpt-include', 'Inner', null, 'Leaf'),
      ),
    );
    client.pages['S2|Inner'] =
        _page('2', 'S2', _excerptMacro('excerpt', 'Leaf', '<p>leaf</p>'));

    final result = ConfluenceExcerptInliner(client).inline(
      _includeMacro('excerpt-include', 'Outer', null, 'Outer'),
      'S1',
    );

    expect(result, '<p>leaf</p>');
  });

  test('include cycles terminate and keep the inner macro', () {
    final client = _FakeResolverClient();
    client.pages['SPACE|Loop'] = _page(
      '1',
      'SPACE',
      _excerptMacro(
        'excerpt',
        'Loop',
        _includeMacro('excerpt-include', 'Loop', null, 'Loop'),
      ),
    );

    final result = ConfluenceExcerptInliner(client).inline(
      _includeMacro('excerpt-include', 'Loop', null, 'Loop'),
      'SPACE',
    );

    expect(result, contains('excerpt-include'));
    expect(result.length, lessThan(2000));
  });

  test('pages without includes are returned unchanged (no lookups)', () {
    final client = _FakeResolverClient();
    final html = '<p>plain</p>';
    expect(
      ConfluenceExcerptInliner(client).inline(html, 'SPACE'),
      same(html),
    );
    expect(client.findCalls, isEmpty);
  });
}

String _mention(String id) =>
    '<ac:link><ri:user ri:account-id="$id" ri:local-id="x" /></ac:link>';

void _mentionResolverTests() {
  group('ConfluenceMentionResolver (Java ConfluenceMentionResolver parity)',
      () {
    test('replaces mentions with display names and caches lookups', () {
      final client = _FakeResolverClient()
        ..profiles['acc-1'] = '{"displayName":"Jane Roe"}';

      final result = ConfluenceMentionResolver(client)
          .resolve('<p>${_mention('acc-1')} and ${_mention('acc-1')}</p>');

      expect(result, '<p>@Jane Roe and @Jane Roe</p>');
      expect(client.profileCalls, ['acc-1']);
    });

    test('escapes markup in display names', () {
      final client = _FakeResolverClient()
        ..profiles['acc-1'] = '{"displayName":"A <b> & C"}';

      final result =
          ConfluenceMentionResolver(client).resolve(_mention('acc-1'));

      expect(result, '@A &lt;b&gt; &amp; C');
    });

    test('unresolvable mentions are left untouched', () {
      final client = _FakeResolverClient();
      final html = '<p>${_mention('acc-1')}</p>';

      expect(ConfluenceMentionResolver(client).resolve(html), html);
      expect(client.profileCalls, ['acc-1']);
    });

    test('pages without mentions are returned unchanged (no lookups)', () {
      final client = _FakeResolverClient();
      final html = '<p>plain</p>';
      expect(ConfluenceMentionResolver(client).resolve(html), same(html));
      expect(client.profileCalls, isEmpty);
    });
  });
}

void _spaceKeyTests() {
  group('confluenceSpaceKeyOf (Java Content.getSpaceKey parity)', () {
    test('reads the expanded space key', () {
      expect(
          confluenceSpaceKeyOf(const {
            'id': '1',
            'space': {'key': 'ABC'}
          }),
          'ABC');
    });

    test('falls back to the _expandable space link', () {
      expect(
        confluenceSpaceKeyOf(const {
          'id': '1',
          '_expandable': {'space': '/rest/api/space/XYZ'},
        }),
        'XYZ',
      );
    });

    test('returns null when no space information is present', () {
      expect(confluenceSpaceKeyOf(const {'id': '1'}), isNull);
      expect(
          confluenceSpaceKeyOf(const {
            'id': '1',
            'space': {'key': '  '}
          }),
          isNull);
    });
  });
}
