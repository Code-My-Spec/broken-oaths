# Hand-write Req clients for external APIs, test with ReqCassette

## Status
Accepted (pre-made)

## Context
We need to integrate with external HTTP APIs and test that code without hitting real services in CI.

## Decision
Strongly prefer hand-written `Req` clients over third-party API-wrapper libraries. A thin module that builds the request and pattern-matches the response is easier to read, owns its own error handling, adds no transitive dependencies, and never drifts from the API behind a generated abstraction. Test these clients with ReqCassette: inject the cassette plug via `Application.get_env` so production code stays unaware of tests, filter authorization headers out of cassettes, and replay in CI. This yields deterministic, async-safe, offline tests that document the exact API interactions the system depends on. Only reach for a wrapper library when the surface is genuinely large and the library is first-party and well-maintained.

## Consequences
This is a pre-made decision for the standard CodeMySpec stack.
