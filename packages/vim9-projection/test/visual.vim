vim9script

set encoding=utf-8
set nomore
set noshowmode
set noruler
set laststatus=0
set nonumber
set norelativenumber

var root = fnamemodify(expand('<sfile>:p'), ':h:h')
execute 'set runtimepath^=' .. fnameescape(root)
runtime plugin/vim9_projection.vim
execute 'edit ' .. fnameescape(root .. '/test/input.txt')
execute 'Vim9ProjectionLoad ' .. fnameescape(root .. '/test/maps.jsonl')
normal! gg
redraw!

var rows: list<string> = []
for row in range(1, 6)
  var text = ''
  for column in range(1, 79)
    text ..= screenstring(row, column)
  endfor
  rows->add(text)
endfor
writefile(rows, root .. '/test/screen.out')
qa!
