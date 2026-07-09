# UX visual audit

The UX visual artifact is generated from the Go LSP JSON-RPC response and then audited semantically.

The audit does not compare pixels. It checks the canonical JSON payload and confirms the SVG/Markdown contain:

- raw buffer `houji`;
- preedit `ほうじ`;
- normal top candidate `houjinScore`;
- Japanese candidates `法人` and `法人売却`.

This prevents artifact-upload-only false green.
