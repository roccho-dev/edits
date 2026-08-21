set shortmess+=c
set noswapfile
call setline(1, '')
call cursor(1, 1)
let g:proof_out = $HQ_FEEDKEYS_PROOF_OUT
let g:proof_mode = $HQ_FEEDKEYS_MODE

function! HqFeedkeysProofFinish(status, detail) abort
  let l:info = complete_info(['selected', 'items'])
  call writefile([json_encode({
        \ 'status': a:status,
        \ 'detail': a:detail,
        \ 'mode': g:proof_mode,
        \ 'line': getline(1),
        \ 'selected': get(l:info, 'selected', -99),
        \ 'pumvisible': pumvisible(),
        \ })], g:proof_out)
  qa!
endfunction

function! HqFeedkeysProofStart(timer) abort
  call complete(1, [
        \ {'word': 'alpha', 'abbr': 'alpha', 'menu': 'original-first'},
        \ {'word': 'beta', 'abbr': 'beta', 'menu': 'original-second'},
        \ ])
  call feedkeys("\<C-N>\<C-N>\<C-Y>\<Esc>", g:proof_mode)

  " Deliberately replace the completion set before queued keys are flushed.
  " mode=n therefore selects from the wrong recomputed set, while mode=nx
  " consumes the keys immediately against the observed original set.
  if g:proof_mode ==# 'n'
    call complete(1, [{'word': 'wrong', 'abbr': 'wrong', 'menu': 'recomputed'}])
    call feedkeys('', 'x')
  endif
  call timer_start(20, {-> HqFeedkeysProofFinish('PASS', 'observed')})
endfunction

augroup hq_feedkeys_local_proof
  autocmd!
  autocmd InsertEnter * ++once call timer_start(10, function('HqFeedkeysProofStart'))
augroup END
startinsert
