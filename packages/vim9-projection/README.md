# Vim9 JSONL projection

This package projects raw buffer text as icons, emoji, or replacement strings without changing the buffer text.

```text
raw buffer
  -> one-map-per-line JSONL
  -> reduce by map id
  -> Vim conceal
  -> text-property virtual text
```

The raw text remains the source used by editing, search, copy, save, Git, LSP, and hq submission.

## Map format

Each physical JSONL line is one complete map.

| field | required | meaning |
|---|---:|---|
| `id` | yes | stable reduction key; the last row for the same id wins |
| `pattern` | yes | Vim regular expression matched against raw buffer lines |
| `display` | yes | UTF-8 virtual text, including emoji or multiple characters |
| `enabled` | no | false removes the map after reduction |
| `priority` | no | Vim conceal match priority; default is 10 |

The fixture deliberately contains five rows and four ids. The last `role.ceo` row replaces its earlier snapshot.

## Commands

| command | effect |
|---|---|
| `:Vim9ProjectionLoad path/to/maps.jsonl` | reduce the file and apply the resulting maps |
| `:Vim9ProjectionApply` | reapply the current reduced map set |
| `:Vim9ProjectionClear` | remove conceal matches and virtual text from the current buffer/window |

Add `packages/vim9-projection` to Vim's `runtimepath` so that `plugin/vim9_projection.vim` is loaded.

## Proof

The headless proof asserts:

- five JSONL rows reduce to four effective maps;
- four raw matches create four conceal matches and four virtual-text properties;
- raw `ceo` remains searchable and present in the buffer;
- writing without edits keeps the content SHA-256 unchanged;
- clearing the projection removes all added display state.

The Linux real-screen proof also asserts these visible rows:

```text
role: 👑 CEO
finance_owner: 💼 CFO
package: 📦 factory/core
created_at: ◷ 2026-07-10 19:30 JST
```

## Boundary

This is an editor presentation adapter only. Map rows do not define hq commands, targets, payloads, providers, queue rows, accepted identities, or execution behavior. Removing the plugin changes presentation only.
