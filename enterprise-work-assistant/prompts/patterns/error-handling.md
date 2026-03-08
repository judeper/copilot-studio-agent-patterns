# Error Handling

Error handling patterns for all Enterprise Work Assistant agents. Reference this pattern to ensure consistent degradation behavior and structured error reporting.

---

## Graceful Degradation

1. **Always return valid JSON**: Even when an error occurs, the response must be valid JSON that conforms to the output schema. Never return plain text error messages or stack traces.
2. **Partial results over no results**: If some data sources succeed and others fail, return the successful results and indicate which sources failed. Do not discard all results because one lookup timed out.
3. **Fallback values**: When a tool action fails and a default is reasonable, use it:
   - Failed sender lookup → `"sender_context": null`
   - Failed calendar query → `"calendar_conflicts": []`
   - Failed confidence calculation → `"confidence_score": null, "low_confidence_note": "Confidence scoring unavailable"`

## Structured Error Responses

When an agent cannot fulfill a request, return a structured error within the normal output schema:

```json
{
  "card_status": "ERROR",
  "item_summary": "Unable to process signal — [brief reason]",
  "confidence_score": null,
  "low_confidence_note": "Processing failed: [error details]",
  "error_detail": {
    "error_type": "TOOL_FAILURE | RATE_LIMITED | INVALID_INPUT | TIMEOUT",
    "failed_tool": "QueryCalendar",
    "message": "HTTP 503 — Dataverse temporarily unavailable",
    "retryable": true
  }
}
```

### Error Types

| Type | Meaning | Retryable |
|------|---------|-----------|
| `TOOL_FAILURE` | A tool action returned an unexpected error | Usually yes |
| `RATE_LIMITED` | HTTP 429 — throttling limit reached | Yes (with backoff) |
| `INVALID_INPUT` | Input data is malformed or missing required fields | No |
| `TIMEOUT` | Tool action did not respond within the allowed time | Yes |
| `CONTRACT_VIOLATION` | Agent output does not match the expected schema | No |

## Retry Guidance

1. **Exponential backoff**: When signaling that an error is retryable, the consuming flow should use exponential backoff: 5s → 15s → 45s.
2. **Max 3 retries**: After 3 failed attempts, stop retrying and create a fallback card (see [Degraded Mode Fallback](../../docs/architecture-enhancements.md#degraded-mode-fallback)).
3. **Idempotent operations**: Ensure retried operations do not create duplicate records. Use the signal's `conversationId` or `internetMessageId` as an idempotency key when creating Dataverse rows.

## Logging Format

When logging errors (to `cr_errorlog` or processing notes), use this structured format:

```json
{
  "timestamp": "2026-02-25T14:30:00Z",
  "flow_run_id": "{workflow run ID}",
  "agent_name": "Triage Agent",
  "agent_version": "2.2.0",
  "error_type": "TOOL_FAILURE",
  "tool_name": "QuerySenderProfile",
  "http_status": 503,
  "message": "Dataverse temporarily unavailable",
  "retry_count": 2,
  "signal_id": "{conversationId or messageId}",
  "resolved": false
}
```

This format enables filtering and aggregation in Power BI dashboards and supports correlation across flow runs.
