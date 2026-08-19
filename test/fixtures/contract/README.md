# L2 Contract Test Fixtures

This directory holds **contract fixtures** — recorded Java tool invocations
that are replayed against the Dart port to verify identical behavior over the
same upstream API response.

The framework lives in `test/contract/contract_test_helper.dart`; integration
contract tests (e.g. `test/contract/jira_contract_test.dart`) drive the fixtures
found here.

## Fixture format

Each fixture is one JSON file, named `<tool_name>[_scenario].json`:

```json
{
  "tool_name": "jira_get_ticket",
  "request_args": { "ticket_id": "PROJ-1" },
  "java_api_endpoint": "/rest/api/latest/issue/PROJ-1",
  "java_http_method": "GET",
  "expected_response": { "key": "PROJ-1", "fields": { "...": "..." } },
  "mock_response_body": "{\"raw\":\"api body\"}"
}
```

| Field | Required | Description |
|---|---|---|
| `tool_name` | yes | The MCP tool name (snake_case). Selects which Dart method runs. |
| `request_args` | yes | The arguments the tool was invoked with. |
| `java_api_endpoint` | yes | The upstream REST path the Java tool called. |
| `java_http_method` | yes | The HTTP verb (`GET`, `POST`, …). |
| `expected_response` | yes | The tool-level output the Dart port must reproduce. |
| `mock_response_body` | no | The raw API body the mock transport serves. When omitted, the mock serves a JSON encoding of `expected_response` (sufficient for tools that return the raw body verbatim). |

## How the comparison works

1. The integration's contract test loads every `*.json` here whose `tool_name`
   it knows about.
2. For each fixture it wires a mock HTTP transport that answers every request
   with `mock_response_body` (HTTP 200, `application/json`).
3. It invokes the Dart client method named by `tool_name` with `request_args`.
4. The Dart method's return value is compared with `expected_response` using
   deep equality.

A mismatch means the Dart port diverges from the recorded Java behavior for
that exact input — that is the contract being enforced.

## Regenerating from real Java recordings

The example fixtures here use hand-crafted, realistic API response shapes (not
real recordings). To replace them with genuine Java captures:

1. Run the Java DMTools CLI against a sandbox instance with request/response
   logging enabled, e.g.:

   ```bash
   java -Ddmtools.log.http=true -jar dmtools.jar jira_get_ticket '{"ticket_id":"PROJ-1"}'
   ```

2. From the captured log, take the upstream API response body and the tool's
   parsed output, and write them into a fixture as `mock_response_body` and
   `expected_response` respectively.

3. Re-run the contract tests. They now assert the Dart port reproduces that
   exact Java result.

When no recordings exist yet, the framework stays green: `runContractCases`
skips silently if the fixtures directory is empty and registers a test per
fixture that is present, so dropping in a recording later requires no code
change.
