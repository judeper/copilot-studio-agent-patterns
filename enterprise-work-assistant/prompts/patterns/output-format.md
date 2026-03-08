# Output Format

JSON output formatting rules for all Intelligent Work Layer agents. Reference this pattern to ensure consistent, parseable responses across the agent pipeline.

---

## JSON Requirements

1. **Valid JSON only**: Every agent response must be valid JSON. No trailing commas, no single quotes, no unescaped special characters.
2. **No markdown wrapping**: Do not wrap JSON output in markdown code fences (`` ```json ... ``` ``). Return raw JSON only — the consuming flow uses Parse JSON, not a markdown renderer.
3. **No commentary**: Do not include explanatory text before or after the JSON object. The response must begin with `{` and end with `}`.

## Field Rules

1. **Required fields always present**: Every field defined as required in the output schema must appear in every response, even if the value is empty or default. Omitting a required field causes Parse JSON to fail in Power Automate.
2. **Null for missing optional fields**: If an optional field has no applicable value, set it to `null` — not an empty string, not `"N/A"`, not `"none"`. This enables reliable null-checking in flow expressions.
3. **Consistent types**: A field must always return the same JSON type. If `confidence_score` is defined as `integer`, never return it as a string (`"85"`) or float (`85.0`).

## Date and Time

1. **ISO 8601 format**: All date and time values must use ISO 8601 format: `"2026-02-25T14:30:00Z"`.
2. **UTC timezone**: Use UTC (Z suffix) for all timestamps unless the field explicitly represents a user-local time.
3. **Date-only fields**: For fields that represent a date without time, use `"2026-02-25"` (no time component).

## String Content

1. **Escape special characters**: Ensure all string values properly escape quotes (`\"`), backslashes (`\\`), and newlines (`\n`).
2. **No HTML in summaries**: The `item_summary` and other user-facing text fields must contain plain text. Strip any HTML tags from source content before including in the response.
3. **Length limits**: Keep `item_summary` under 500 characters. If the source content is longer, truncate with an ellipsis and set `"summary_truncated": true` if the schema supports it.

## Arrays and Objects

1. **Empty arrays, not null**: If a list field has no items, return `[]` — not `null`. This prevents null-reference errors in flow expressions that iterate over the array.
2. **Consistent object shape**: Objects in an array must all have the same set of keys. Do not omit keys from some objects — use `null` for missing values.
