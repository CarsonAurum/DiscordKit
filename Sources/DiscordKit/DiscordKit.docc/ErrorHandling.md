# Handle failures without losing outcomes

Separate validation, admission, transport, server and indeterminate-operation failures.

## Overview

### Validate before sending

Typed identifiers, payload constructors and endpoint descriptors reject local contract violations before transport execution. These checks do not prove the current user has permission or that a resource exists. Keep server API failures visible to application policy, and retain unknown fields/raw values when decoding supported projections.

### Preserve mutation uncertainty

An operation can fail before send, receive a definitive server rejection, or lose its response after the server may have acted. Only the first two establish a known outcome. A timeout or disconnect after an ambiguous mutation must not be converted into an automatic second mutation.

Inspect DiscordCore's DiscordError and the product-specific error types in the API reference. Use safe retries only when the endpoint/executor's replay contract permits them. Preserve partial results from bounded bulk operations so a later recovery can target unresolved work.

### Interpret failures by layer

| Layer | Examples | Application response |
| --- | --- | --- |
| Local validation | Invalid identifier/body, unsupported combination | Correct input; no retry loop |
| Admission | Queue capacity, byte budget, closed coordinator | Apply backpressure or stop; inspect ownership |
| Transport | Connection/TLS/read failure, deadline, cancellation | Use typed outcome and permitted retry policy |
| API | Authentication, permission, not found, structured validation, rate limit | Correct authority/input; honor coordinated limits |
| State | Sequence gap, stale scope, expired consent, reconnect generation | Invalidate and explicitly resynchronize |
| Media/security | Invalid tag, replay, exhausted counter, untrusted participant | Reject data and follow documented recovery |

### Report useful diagnostics

Log bounded categories, operation names, durations and public correlation IDs. Avoid credentials, OAuth URLs, interaction path tokens, raw signed bodies, user-controlled payloads and unbounded label values. Redacted descriptions reduce accidental exposure; they do not sanitize every arbitrary value passed to a logger.

### Exercise recovery locally

Inject deterministic transports and clocks to test queue saturation, expiry, cancellation before and during work, malformed responses and ambiguous outcomes. Assert both the error and cleanup/state change. <doc:TestingApplications> points to concrete tests and peers; each product guide explains its own retry, freshness and ownership limits.
