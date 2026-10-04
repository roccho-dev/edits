vim9script
import '../surface.vim' as surface

# Owned fixture bootstrap; importing the product does not create buffers or read IO.
if argc() != 0 || bufname() != '' || &modified || getline(1, '$') != ['']
  throw 'surface example requires a fresh owned Vim session'
endif

def Query(raw: dict<any>): dict<any>
  return {start: raw.cursor.column - 1, input: v:null}
enddef

def Acquire(raw: dict<any>): any
  if raw.source == ''
    throw 'EDITS_COMPLETION_SOURCE is required'
  endif
  return json_decode(readfile(raw.source)->join("\n"))
enddef

const path = $EDITS_COMPLETION_SOURCE
const examples = surface.ValidateView(Acquire({source: path})).contexts
var buffers: list<number> = []
for group in examples
  var bnr = bufadd(tempname())
  bufload(bnr)
  setbufvar(bnr, '&buflisted', 1)
  setbufvar(bnr, '&bufhidden', 'hide')
  buffers->add(bnr)
  execute $'buffer {bnr}'
  b:surface_source = path
  b:surface_current = deepcopy(group.current)
  b:surface_context = deepcopy(group.context)
  b:surface_query = Query
  b:surface_acquire = Acquire
  surface.Attach()
endfor
if empty(buffers)
  throw 'fixture requires at least one context'
endif
execute $'buffer {buffers[0]}'
cursor(1, 1)
echo '例: CTRL-X CTRL-Uで補完。選択・取消・編集は未採用'
