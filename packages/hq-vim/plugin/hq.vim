vim9script

if get(g:, 'loaded_hq_vim', false)
  finish
endif
g:loaded_hq_vim = true

import autoload '../autoload/hq.vim' as hq

def g:HqVimStart(profile: string = '')
  hq.Start(profile)
enddef

def g:HqVimSubmit(): dict<any>
  return hq.Submit()
enddef

def g:HqVimDoctor()
  echo hq.Doctor()
enddef

def g:HqVimCompletionRequest(): dict<any>
  return hq.CompletionRequest()
enddef

command! -nargs=? HqStart g:HqVimStart(<q-args>)
command! HqSubmit g:HqVimSubmit()
command! HqDoctor g:HqVimDoctor()
