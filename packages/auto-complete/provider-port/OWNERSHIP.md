# ownership

| area | owner |
|---|---|
| provider | portable Japanese candidate discovery and provider-local rank |
| editor orchestrator | collect buffer and provider sources |
| candidate core | cross-source dedupe, final rank, Vim display decoration |
| cmp | candidate set and selected index |
| view | preedit and selected ghost |
| commit | exact raw span validation and sole buffer write |

The provider does not own selected state, ghost, final cross-source rank, or buffer writes.
