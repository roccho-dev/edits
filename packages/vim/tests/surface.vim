vim9script

# Native UI examples only: no Proposal, admission, or accepted state.
# Source in a fresh owned Vim session; :write saves only its temporary files.
if argc() != 0 || bufname() != '' || &modified
  throw 'surface example requires a fresh owned Vim session'
endif

def Complete(findstart: number, _base: string): any
  return findstart ? col('.') - 1 : b:surface_items
enddef

def Completed()
  b:surface_completed = deepcopy(v:completed_item)
  echo empty(b:surface_completed) ? 'Example: cancelled' : $'Example selection: {b:surface_completed.user_data}'
enddef

# Native display input, kept outside the common view callbacks.
const examples = [
  ['色の例', [
    {word: 'あお', menu: '由来 A1', info: '色の表示入力 A1', user_data: 'A1', dup: 1, equal: 1},
    {word: 'あお', menu: '由来 A2', info: '色の表示入力 A2', user_data: 'A2', dup: 1, equal: 1},
  ]],
  ['位置の例', [
    {word: 'うえ', menu: '由来 B1', info: '位置の表示入力 B1', user_data: 'B1', dup: 1, equal: 1},
    {word: 'した', menu: '由来 B2', info: '位置の表示入力 B2', user_data: 'B2', dup: 1, equal: 1},
  ]],
]

var buffers: list<number> = []
for [context, items] in examples
  var bnr = bufadd(tempname())
  bufload(bnr)
  setbufvar(bnr, '&buflisted', 1)
  setbufvar(bnr, '&bufhidden', 'hide')
  setbufvar(bnr, 'surface_items', items)
  setbufvar(bnr, 'surface_completed', {})
  setbufline(bnr, 1, ['', context])
  buffers->add(bnr)
  execute $'buffer {bnr}'
  setlocal completeopt=menuone,noselect,popup
  &l:completefunc = Complete
  autocmd CompleteDonePre <buffer> Completed()
endfor
execute $'buffer {buffers[0]}'
cursor(1, 1)
echo 'Example: i, CTRL-X CTRL-U, CTRL-N / CTRL-P, CTRL-Y / CTRL-E, Esc; edit, :write, u; :bnext'
