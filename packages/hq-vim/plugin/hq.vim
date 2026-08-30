vim9script

if get(g:, 'loaded_hq_vim', false)
  finish
endif
g:loaded_hq_vim = true

import autoload '../autoload/hq.vim' as hq

def g:EditsVimStart(profile: string = '')
  hq.Start(profile)
enddef

def g:HqVimStart(profile: string = '')
  g:EditsVimStart(profile)
enddef

def g:EditsVimSubmit(): dict<any>
  return hq.Submit()
enddef

def g:HqVimSubmit(): dict<any>
  return g:EditsVimSubmit()
enddef

def g:EditsVimDoctor()
  echo hq.Doctor()
enddef

def g:HqVimDoctor()
  g:EditsVimDoctor()
enddef

def g:HqVimCompletionRequest(): dict<any>
  return hq.CompletionRequest()
enddef

command! -nargs=? EditsStart g:EditsVimStart(<q-args>)
command! -nargs=? HqStart g:EditsVimStart(<q-args>)
command! EditsSubmit g:EditsVimSubmit()
command! HqSubmit g:EditsVimSubmit()
command! EditsDoctor g:EditsVimDoctor()
command! HqDoctor g:EditsVimDoctor()
