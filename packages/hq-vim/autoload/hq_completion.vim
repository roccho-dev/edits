vim9script

import autoload 'lsp/buffer.vim' as lspbuf
import autoload 'lsp/completion.vim' as lspcompletion

# Trigger the pinned third-party client's existing completion path even when the
# disposable draft is empty.  Candidate meaning, filtering, presentation,
# textEdit application, and documentation remain owned by hq and yegappan/lsp.
export def Complete(): number
  if mode(1) !~# '^i'
    throw 'HqComplete requires Insert mode'
  endif
  if !g:LspServerReady()
    throw 'hq LSP is not ready for completion'
  endif
  var serverName = get(g:, 'hq_server_name', 'hq-lsp')
  var server = lspbuf.CurbufGetServerByName(serverName)
  if server->empty()
    throw $'hq LSP server is not attached: {serverName}'
  endif
  lspcompletion.LspComplete(true)
  return 1
enddef
