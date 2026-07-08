if exists('g:loaded_hq_command_lsp')
  finish
endif
let g:loaded_hq_command_lsp = 1
command! -nargs=1 HqLspStart call hq_command_lsp#start(<q-args>)
command! -nargs=+ HqDispatch call hq_command_lsp#dispatch(<f-args>)
