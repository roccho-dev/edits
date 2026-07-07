# later adapter trigger

Add a server-style transport only when at least one condition is true:

1. A second editor client needs the same provider.
2. One shared provider instance is required across editors.
3. Dictionary indexing must be isolated from the editor process.

Until then, keep provider in-process and keep the editor adapter responsible for interaction state.
