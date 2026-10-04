vim9script

# Fixture UI only: no shared provider, semantic apply, or admission.
# EDITS_COMPLETION_SOURCE supplies decision-completion.view/1 display data.
if argc() != 0 || bufname() != '' || &modified || getline(1, '$') != ['']
  throw 'surface example requires a fresh owned Vim session'
endif

def ReadSource(base: dict<any> = {}): any
  var path = get(base, 'source', $EDITS_COMPLETION_SOURCE)
  if path == ''
    throw 'EDITS_COMPLETION_SOURCE is required'
  endif
  return json_decode(readfile(path)->join("\n"))
enddef

def ValidateView(data: any): dict<any>
  if type(data) != v:t_dict || sort(keys(data)) != ['contexts', 'schema']
      || data.schema != 'decision-completion.view/1' || type(data.contexts) != v:t_list
    throw 'invalid decision-completion.view/1 fixture'
  endif
  for group in data.contexts
    if type(group) != v:t_dict || sort(keys(group)) != ['context', 'current', 'items']
        || type(group.items) != v:t_list
      throw 'invalid fixture context'
    endif
    for item in group.items
      if type(item) != v:t_dict || sort(keys(item)) != ['handle', 'label', 'provenance', 'text']
          || type(item.label) != v:t_string || type(item.provenance) != v:t_string
          || type(item.text) != v:t_list || !empty(filter(copy(item.text), (_, line) => type(line) != v:t_string))
        throw 'invalid fixture candidate'
      endif
    endfor
  endfor
  return data
enddef

def Same(left: any, right: any): bool
  return type(left) == type(right) && left ==# right
enddef

def Complete(findstart: number, _base: string): any
  if findstart
    return col('.') - 1
  endif
  var base = {source: $EDITS_COMPLETION_SOURCE, buffer: bufnr(), tick: b:changedtick,
    working: getline(1, '$'), current: deepcopy(b:surface_current), context: deepcopy(b:surface_context)}
  b:surface_base = {}
  var Acquire = get(b:, 'surface_acquire', ReadSource)
  var data: dict<any>
  try
    if type(Acquire) != v:t_func
      throw 'surface_acquire must be a Funcref'
    endif
    data = ValidateView(call(Acquire, [deepcopy(base)]))
  catch
    echo '例: 候補を取得できません。未採用の編集は保持します'
    return []
  endtry
  var groups = copy(data.contexts)->filter((_, group) => Same(group.current, base.current) && Same(group.context, base.context))
  if len(groups) != 1 || base.source != $EDITS_COMPLETION_SOURCE || base.buffer != bufnr()
      || base.tick != b:changedtick || !Same(base.working, getline(1, '$'))
      || !Same(base.current, b:surface_current) || !Same(base.context, b:surface_context)
      || !Same(Acquire, get(b:, 'surface_acquire', ReadSource))
    echo '例: 文脈が変わりました。候補を再取得してください'
    return []
  endif
  b:surface_base = base
  return copy(groups[0].items)->map((_, item) => ({word: join(item.text, "\n"), abbr: item.label,
    menu: item.provenance, info: join(item.text, "\n"), user_data: deepcopy(item.handle), dup: 1, equal: 1, empty: 1}))
enddef

def Completed()
  if complete_info(['mode']).mode != 'function' || empty(b:surface_base)
    return
  endif
  if empty(v:completed_item)
    echo '例: 候補を取消しました'
  else
    b:surface_selection = {handle: deepcopy(v:completed_item.user_data), base: deepcopy(b:surface_base)}
    echo $'例: {v:completed_item.abbr}・{v:completed_item.menu}（未採用）'
  endif
enddef

const examples = ValidateView(ReadSource()).contexts
var buffers: list<number> = []
for group in examples
  var bnr = bufadd(tempname())
  bufload(bnr)
  setbufvar(bnr, '&buflisted', 1)
  setbufvar(bnr, '&bufhidden', 'hide')
  setbufvar(bnr, 'surface_current', deepcopy(group.current))
  setbufvar(bnr, 'surface_context', deepcopy(group.context))
  setbufvar(bnr, 'surface_base', {})
  setbufvar(bnr, 'surface_selection', {})
  buffers->add(bnr)
  execute $'buffer {bnr}'
  setlocal completeopt=menuone,noselect,popup
  &l:completefunc = Complete
  autocmd CompleteDonePre <buffer> Completed()
endfor
if empty(buffers)
  throw 'fixture requires at least one context'
endif
execute $'buffer {buffers[0]}'
cursor(1, 1)
echo '例: i → CTRL-X CTRL-U → CTRL-N / CTRL-P → CTRL-Y / CTRL-E → Esc。編集・:write・u、:bnextで次の文脈'
