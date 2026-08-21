import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the [ToolBridge] dispatcher lifetime.
void main() {
  test('reuses a single dispatcher across the bridge lifetime', () {
    final bridge = ToolBridge(registry: createDefaultToolRegistry());

    expect(bridge.dispatcher, same(bridge.dispatcher));
  });

  test('each bridge builds its own dispatcher', () {
    final registry = createDefaultToolRegistry();
    final first = ToolBridge(registry: registry);
    final second = ToolBridge(registry: registry);

    expect(first.dispatcher, isNot(same(second.dispatcher)));
  });
}
