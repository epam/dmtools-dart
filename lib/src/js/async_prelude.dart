/// JS preludes for `runAsync(fn, args)` — parallel job execution over the
/// synchronous QuickJS bridge (epam/dmtools-dart#224, Option A).
///
/// Two bootstrap scripts:
///
/// - [asyncJobPrelude] — evaluated on the MAIN engine. Exposes
///   `runAsync(fn, args)` returning a `Job` handle with a **blocking**
///   `wait()` (the scripting surface is sync-call-style, Java parity; no
///   promise pumping), plus `runAsync.all(jobs)` / `AsyncJob`.
/// - [asyncWorkerBootstrap] — evaluated on each WORKER engine right before
///   a dispatched function runs. Provides `__jsrCall(fnSource, argsJson)`:
///   materializes the (closure-free) function source, calls it with the
///   parsed args, and returns the JSON-encoded result.
///
/// Host functions underneath (registered by `JsJobRunner` when the
/// `parallelWorkers` job param is >= 2):
/// - `__jsrDispatchHost(fnSource, argsJson)` → JSON job id, or a
///   `{'__jsError': …}` sentinel (rethrown as a real JS `Error`).
/// - `__jsrWaitHost(jobId)` → JSON envelope `{'ok', 'result', 'error'}` —
///   blocks the calling engine until the worker answers (pthread condvar
///   via `Mailbox.take()`, same proven primitive as the HTTP bridge).
library;

/// Main-engine bootstrap: `runAsync` / `AsyncJob` / `runAsync.all`.
const String asyncJobPrelude = '''
(function() {
    // Host results arrive as real JS values (the C bridge runs
    // JS_ParseJSON on them) — no JSON.parse here, only sentinel checks.
    function Job(id) {
        this.id = id;
    }
    Job.prototype.wait = function() {
        var env = __jsrWaitHost(this.id);
        if (env && env.__jsError !== undefined) {
            throw new Error(env.__jsError);
        }
        if (!env || !env.ok) {
            throw new Error('runAsync job ' + this.id + ' failed: ' +
                (env && env.error ? env.error : 'no result'));
        }
        return env.result;
    };
    function runAsync(fn, args) {
        if (typeof fn !== 'function') {
            throw new Error('runAsync expects a function as its first argument');
        }
        var argsJson = JSON.stringify(args === undefined ? null : args);
        var jobId = __jsrDispatchHost(fn.toString(), argsJson);
        if (jobId && jobId.__jsError !== undefined) {
            throw new Error(jobId.__jsError);
        }
        return new Job(jobId);
    }
    runAsync.all = function(jobs) {
        if (!Array.isArray(jobs)) {
            throw new Error('runAsync.all expects an array of jobs');
        }
        return {
            wait: function() {
                return jobs.map(function(job) { return job.wait(); });
            }
        };
    };
    globalThis.runAsync = runAsync;
    globalThis.AsyncJob = Job;
})();
''';

/// Worker-engine bootstrap: materializes and runs one dispatched function.
const String asyncWorkerBootstrap = '''
(function() {
    globalThis.__jsrCall = function(fnSource, argsJson) {
        var fn = eval('(' + fnSource + ')');
        if (typeof fn !== 'function') {
            throw new Error('runAsync: dispatched value is not a function');
        }
        return fn(JSON.parse(argsJson));
    };
})();
''';
