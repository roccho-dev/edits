# edits core

This package defines provider-independent console semantics.

It owns only immutable values and pure transitions for:

- edit context;
- suggestions and diagnostics;
- edit plans;
- explicit acceptance requests;
- typed intent envelopes;
- result and view projections.

It owns no executable discovery, process launch, effect execution, retry policy,
cancel policy, durable result writing, receipt writing, or provider selection.
Concrete transports and runtimes depend on these ports; this package depends on
none of them.
