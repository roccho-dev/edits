" Minimal Vim adapter proof autoload file.
" Vim is only the confirm UI: meaning lives in hq command LSP, side effects live in hq dispatch.
function! hq_command_lsp#start(world) abort
  if !exists('*lsp#register_server')
    echoerr 'This proof expects a Vim LSP client such as vim-lsp. hq core remains editor-independent.'
    return
  endif
  call lsp#register_server({
        \ 'name': 'hq-command-lsp',
        \ 'cmd': ['hq', 'lsp', '--world', a:world],
        \ 'allowlist': ['hqcmd'],
        \ })
endfunction

function! hq_command_lsp#dispatch(plan_file, receipt_file) abort
  " Explicit confirm boundary. Completion never runs this function.
  execute '!hq dispatch --plan ' . shellescape(a:plan_file) . ' --receipts ' . shellescape(a:receipt_file) . ' --confirmed'
endfunction
