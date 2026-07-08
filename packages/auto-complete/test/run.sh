#!/bin/sh
set -eu
cat > /tmp/jpcmp-golden.vim <<'VIM'
set nomore
set encoding=utf-8
set fileencoding=utf-8
let s:normal = [{'word':'houjinScore','rank':1300},{'word':'houjinRepository','rank':1200},{'word':'houjinbaikyakuPlan','rank':1100},{'word':'hogeBufferOnly','rank':1000}]
let s:dict = [{'reading':'ほうじん','romaji':'houjin','word':'法人','rank':10},{'reading':'ほうじんばいきゃく','romaji':'houjinbaikyaku','word':'法人売却','rank':20},{'reading':'ほうしん','romaji':'houshin','word':'方針','rank':30},{'reading':'ほじょ','romaji':'hojo','word':'補助','rank':40}]
function! s:Hira(x) abort
  let out=a:x
  let out=substitute(out,'houjinbaikyaku','ほうじんばいきゃく','g')
  let out=substitute(out,'houjin','ほうじん','g')
  let out=substitute(out,'houji','ほうじ','g')
  let out=substitute(out,'hou','ほう','g')
  return out
endfunction
function! s:Cands(prefix) abort
  let out=[]
  for item in s:normal
    if item.word =~? '^' . escape(a:prefix,'\')
      call add(out, {'word':item.word,'source':'normal','rank':item.rank})
    endif
  endfor
  let view=s:Hira(a:prefix)
  for r in s:dict
    if stridx(r.romaji,a:prefix)==0 || stridx(r.reading,view)==0
      call add(out, {'word':r.word,'source':'jp-dict','rank':100-r.rank})
    endif
  endfor
  call sort(out,{a,b -> b.rank ==# a.rank ? (a.word ># b.word) - (a.word <# b.word) : b.rank - a.rank})
  return out
endfunction
let s:fail=[]
function! s:Has(prefix, word, source) abort
  let labels=map(copy(s:Cands(a:prefix)), {_,x -> x.word . ' [' . x.source . ']'})
  let target=a:word . ' [' . a:source . ']'
  if index(labels,target)<0 | call add(s:fail,a:prefix . ' missing ' . target . ' got=' . string(labels)) | endif
endfunction
function! s:Top(prefix, word, source) abort
  let c=s:Cands(a:prefix)
  if empty(c) || c[0].word !=# a:word || c[0].source !=# a:source | call add(s:fail,a:prefix . ' top mismatch got=' . string(c)) | endif
endfunction
call s:Has('houji','houjinScore','normal')
call s:Has('houji','法人','jp-dict')
call s:Has('houji','法人売却','jp-dict')
call s:Top('houji','houjinScore','normal')
call s:Top('houjin','houjinScore','normal')
call s:Has('houjinb','法人売却','jp-dict')
call s:Top('houjinb','houjinbaikyakuPlan','normal')
call s:Has('houjinScore','houjinScore','normal')
let summary={'schema':'jpcmp_proof_summary.v1','status':empty(s:fail)?'PASS':'FAIL','total_assertions':8,'failures':s:fail}
call mkdir('test','p')
call writefile([json_encode(summary)], 'test/proof_summary.json')
if !empty(s:fail) | cquit | endif
qa!
VIM
vim --clean -Nu NONE -n -es -S /tmp/jpcmp-golden.vim
cat test/proof_summary.json
