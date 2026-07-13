vim9script

import autoload 'lsp/completion.vim' as completion

def g:HqNativePopupForceCompletion()
  completion.LspComplete(true)
enddef
