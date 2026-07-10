if exists('g:loaded_hq_vim')
  finish
endif
let g:loaded_hq_vim = 1

command! -nargs=? HqStart call hq#start(<f-args>)
command! HqSubmit call hq#submit()
command! HqDoctor echo string(hq#doctor())
