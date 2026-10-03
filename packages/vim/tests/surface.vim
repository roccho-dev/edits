vim9script

# Native UI examples only: no Proposal, admission, or accepted state.
# Source in a fresh owned Vim session; :write saves only its temporary files.
if argc() != 0 || bufname() != '' || &modified
  throw 'surface example requires a fresh owned Vim session'
endif

var buffers: list<number> = []
for words in [['あお', 'あか'], ['うえ', 'した']]
  var bnr = bufadd(tempname())
  bufload(bnr)
  setbufvar(bnr, '&buflisted', 1)
  setbufvar(bnr, '&complete', '.')
  setbufvar(bnr, '&bufhidden', 'hide')
  setbufline(bnr, 1, [''] + words)
  buffers->add(bnr)
endfor
execute $'buffer {buffers[0]}'
cursor(1, 1)
echo 'Native example: i, CTRL-N / CTRL-P, CTRL-Y, Esc; edit, :write, u; :bnext'
