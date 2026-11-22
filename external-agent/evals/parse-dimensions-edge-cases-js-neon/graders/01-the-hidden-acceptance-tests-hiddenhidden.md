---
type: llm
focus: trace
weight: 1
---

The hidden acceptance tests (hidden/hidden.test.js: decimal commas, the × separator, unit case, rounding, rejecting 1e3, empty and whitespace-only input, values that round to 0 mm, malformed decimals like 1,,2 and 1.2.3, and non-string arguments) all pass against the final src/parseDims.js
