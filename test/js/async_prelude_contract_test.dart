import 'package:dmtools/src/js/async_job_pool.dart';
import 'package:test/test.dart';

/// Pins the adapter <-> package prelude contract: [dispatchAsyncJob] and
/// [waitAsyncJob] re-implement the host-function half of the package's
/// `runAsync` protocol (the `asyncJobPrelude` JS side lives in
/// `quickjs_runtime`). A jsr minor bump that renames the host functions or
/// reshapes the envelope breaks this adapter at runtime, not compile time —
/// this test is the loud tripwire (review finding on #226).
void main() {
  final prelude = asyncJobPrelude;

  test('package prelude installs the adapter host-fn names', () {
    expect(prelude, contains('__jsrDispatchHost'),
        reason: 'asyncJobPrelude must call the adapter dispatch host fn');
    expect(prelude, contains('__jsrWaitHost'),
        reason: 'asyncJobPrelude must call the adapter wait host fn');
  });

  test('package prelude consumes the adapter envelope shape', () {
    // {ok, result, error} success envelope + __jsError failure sentinel.
    expect(prelude, contains('.ok'), reason: 'prelude reads the ok field');
    expect(prelude, contains('__jsError'),
        reason: 'prelude rethrows the __jsError sentinel');
  });
}
