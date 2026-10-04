vim9script
import './semcmp.vim' as semcmp

# No example buffers or invented current: attach only the actual current buffer.
semcmp.Attach($EDITS_SEMCMP_BIN, $EDITS_SEMCMP_CATALOG)
