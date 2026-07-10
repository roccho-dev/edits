if exists('g:loaded_hq_vim')
  finish
endif
let g:loaded_hq_vim = 1

command! -nargs=? HqStart call hq#start(<f-args>)
command! HqAcceptFirst call hq#accept_first()
command! HqDoctor echo string(hq#doctor())
