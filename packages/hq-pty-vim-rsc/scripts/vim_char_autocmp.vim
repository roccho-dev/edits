set nocompatible
set noswapfile
set nomore
set rtp^=vim
let g:hq_autocmp_world = getcwd() . '/examples/world.jsonl'
let g:hq_autocmp_log = getcwd() . '/cache/vim-autocmp.jsonl'
call delete(g:hq_autocmp_log)
source vim/plugin/hq_autocmp.vim
enew
setlocal filetype=hqcmd
call setline(1, '')
for ch in split('pane.shell.', '\zs')
  execute 'normal! A' . ch
  " In headless ex mode Vim does not always run Insert-mode events naturally;
  " this fires the same TextChanged hook after each one-character buffer change.
  doautocmd TextChanged
endfor
write! cache/vim-autocmp-buffer.txt
qa!
