# Manual completion from an empty hq draft

The canonical draft may be exactly one empty line. Because there is no typed trigger in that state, hq-vim exposes:

```vim
:HqComplete
```

Run it from Insert mode after `:HqStart` has attached the pinned `yegappan/lsp` client. The command is only a thin call to the client's exported `LspComplete(true)` operation.

It adds no hq matcher, popup, key mapping, history parser, ranker, or text-edit implementation. hq remains responsible for candidate meaning and accepted-history policy; `yegappan/lsp` and Vim remain responsible for the native popup, documentation, selection, and standard `textEdit` application.

Completion and selection append zero accepted rows. Only explicit `:HqSubmit` creates a fresh canonical accepted instruction.
