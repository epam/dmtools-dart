import 'package:test/test.dart';
import 'package:dmtools/src/integrations/confluence/confluence_page_url.dart';

/// Tests for [resolveConfluencePageUrl] — the Java `contentByUrl` /
/// `handleWikiUrls` / `checkBaseIndex` segment walk.
void main() {
  parseUrlTests();
  shortLinkAndRejectTests();
}

void parseUrlTests() {
  group('resolveConfluencePageUrl', () {
    test('parses /wiki/spaces/{space}/pages/{id}/{title}', () {
      final ref = resolveConfluencePageUrl(Uri.parse(
        'https://conf.example.com/wiki/spaces/ENG/pages/123456/Page+Title',
      ));
      expect(ref, isA<ConfluencePageIdRef>());
      expect((ref as ConfluencePageIdRef).id, '123456');
    });

    test('parses /wiki/spaces/{space}/pages/{id} without a title', () {
      final ref = resolveConfluencePageUrl(
        Uri.parse('https://conf.example.com/wiki/spaces/ENG/pages/42'),
      );
      expect(ref, isA<ConfluencePageIdRef>());
      expect((ref as ConfluencePageIdRef).id, '42');
    });

    test('parses /spaces/... without the /wiki prefix', () {
      final ref = resolveConfluencePageUrl(
        Uri.parse('https://conf.example.com/spaces/DEV/pages/7/T'),
      );
      expect(ref, isA<ConfluencePageIdRef>());
      expect((ref as ConfluencePageIdRef).id, '7');
    });

    test('parses /wiki/display/~user/page+name as a display lookup', () {
      final ref = resolveConfluencePageUrl(
        Uri.parse('https://conf.example.com/wiki/display/~jdoe/My+Page'),
      );
      expect(ref, isA<ConfluenceDisplayRef>());
      final display = ref as ConfluenceDisplayRef;
      expect(display.space, '~jdoe');
      expect(display.title, 'My Page');
    });
  });
}

void shortLinkAndRejectTests() {
  group('resolveConfluencePageUrl', () {
    test('marks /wiki/x/{id} short links as redirects', () {
      final ref = resolveConfluencePageUrl(
        Uri.parse('https://conf.example.com/wiki/x/AABBCC'),
      );
      expect(ref, isA<ConfluenceRedirectRef>());
    });

    test('marks /l/ deep links as redirects', () {
      final ref = resolveConfluencePageUrl(
        Uri.parse('https://conf.example.com/l/inv/next?data=xyz'),
      );
      expect(ref, isA<ConfluenceRedirectRef>());
    });

    test('marks /wiki/x/{id} without redirect resolution as a plain id', () {
      // Java resolves /wiki/x/{id} redirects; the parser must not classify
      // the short id itself as a REST content id.
      final ref = resolveConfluencePageUrl(
        Uri.parse('https://conf.example.com/wiki/x/abc123'),
      );
      expect(ref, isA<ConfluenceRedirectRef>());
    });

    test('rejects unknown URL shapes', () {
      expect(
        resolveConfluencePageUrl(
          Uri.parse('https://conf.example.com/something/else'),
        ),
        isA<ConfluenceUnknownUrlRef>(),
      );
      expect(
        resolveConfluencePageUrl(
          Uri.parse('https://conf.example.com/wiki/spaces/ENG'),
        ),
        isA<ConfluenceUnknownUrlRef>(),
      );
    });
  });
}
