# client port

The client port maps a native editing surface to provider-independent console
records. A client may open a disposable document, display suggestions and
diagnostics, apply a version-tied edit plan, expose one native undo unit, and
submit an explicit acceptance request.

The port never parses operation authority, starts a business process, or writes a
canonical result.
