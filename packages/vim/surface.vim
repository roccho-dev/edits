vim9script

# Native Human surface only. Meaning, ranking and admission belong to the owner.
export def ValidateView(data: any): dict<any>
  if type(data) != v:t_dict || sort(keys(data)) != ['contexts', 'schema']
      || data.schema != 'decision-completion.view/1' || type(data.contexts) != v:t_list
    throw 'invalid decision-completion.view/1'
  endif
  for group in data.contexts
    if type(group) != v:t_dict || sort(keys(group)) != ['context', 'current', 'items']
        || type(group.items) != v:t_list
      throw 'invalid view context'
    endif
    for item in group.items
      if type(item) != v:t_dict
          || (sort(keys(item)) != ['handle', 'label', 'provenance', 'text']
            && sort(keys(item)) != ['handle', 'info', 'label', 'provenance', 'text'])
          || type(item.label) != v:t_string || type(item.provenance) != v:t_string
          || type(item.text) != v:t_list || !empty(filter(copy(item.text), (_, line) => type(line) != v:t_string))
          || (has_key(item, 'info') && type(item.info) != v:t_string)
        throw 'invalid view candidate'
      endif
    endfor
  endfor
  return data
enddef

def Same(left: any, right: any): bool
  return type(left) == type(right) && left ==# right
enddef

def Snapshot(): dict<any>
  return {source: deepcopy(get(b:, 'surface_source', v:null)), buffer: bufnr(),
    tick: b:changedtick, working: getline(1, '$'),
    current: deepcopy(get(b:, 'surface_current', v:null)),
    context: deepcopy(get(b:, 'surface_context', v:null)),
    cursor: {line: line('.'), column: col('.')}}
enddef

def Unchanged(base: dict<any>, Query: any, Acquire: any): bool
  return base.buffer == bufnr() && Same(base, Snapshot())
    && Same(Query, get(b:, 'surface_query', v:null))
    && Same(Acquire, get(b:, 'surface_acquire', v:null))
enddef

def Key(): dict<any>
  return {buffer: bufnr(), working: getline(1, '$'), cursor: [line('.'), col('.')]}
enddef

def Fail(code: string)
  if code !=# b:surface_error
    echomsg $'候補を取得できません（{code}）。編集は保持します'
  endif
  b:surface_error = code
enddef

# Human edits ask for proposals. Native preview, a foreign menu, the last asked state
# and a state just ended by this menu do not; Ctrl-X Ctrl-U asks explicitly.
def Request(explicit = false)
  if (!explicit && mode() !~# '^i') || (pumvisible() && empty(b:surface_shown))
      || complete_info(['selected']).selected >= 0
    return
  endif
  var key = Key()
  if !explicit && (Same(key, b:surface_asked) || Same(key, b:surface_dismissed))
    return
  endif
  if pumvisible()
    b:surface_shown = {}
    complete(col('.'), [])
  endif
  b:surface_asked = key
  b:surface_dismissed = {}
  b:surface_serial += 1
  if b:surface_busy
    b:surface_again = true
  else
    Ask()
  endif
enddef

# One acquisition is in flight; a result may show only for the latest unchanged request.
def Ask()
  b:surface_again = false
  var base = Snapshot()
  var Query = get(b:, 'surface_query', v:null)
  var Acquire = get(b:, 'surface_acquire', v:null)
  if type(Query) != v:t_func || type(Acquire) != v:t_func
    Fail('SETUP')
    return
  endif
  var raw: dict<any>
  try
    var query = call(Query, [deepcopy(base)])
    var end = base.cursor.column - 1
    var text = base.working[base.cursor.line - 1]
    if !Unchanged(base, Query, Acquire) || type(query) != v:t_dict
        || sort(keys(query)) != ['input', 'start'] || type(query.start) != v:t_number
        || query.start < 0 || query.start > end
        || byteidx(text, charidx(text, query.start)) != query.start
      throw 'invalid or stale query'
    endif
    raw = extend(deepcopy(base), {start: query.start, input: deepcopy(query.input)})
  catch
    Fail('QUERY')
    return
  endtry
  b:surface_busy = true
  b:surface_asking = true
  try
    call(Acquire, [deepcopy(raw), function(Receive, [b:surface_serial, base, raw, Query, Acquire, win_getid()])])
  catch
    b:surface_busy = false
    Fail('ACQUIRE')
  finally
    b:surface_asking = false
  endtry
enddef

def Receive(serial: number, base: dict<any>, raw: dict<any>, Query: func, Acquire: func, window: number, result: any)
  if getbufvar(base.buffer, 'surface_asking', false)
    timer_start(0, (_) => Receive(serial, base, raw, Query, Acquire, window, result))
    return
  endif
  setbufvar(base.buffer, 'surface_busy', false)
  if bufnr() != base.buffer || win_getid() != window
    return
  endif
  if serial != b:surface_serial
    if b:surface_again && mode() =~# '^i'
      Ask()
    endif
    return
  endif
  if type(result) == v:t_string
    Fail(result)
    return
  endif
  var data: dict<any>
  try
    data = ValidateView(result)
  catch
    Fail('VIEW')
    return
  endtry
  b:surface_error = ''
  if mode() !~# '^i' || !Unchanged(base, Query, Acquire) || pumvisible()
    return
  endif
  var groups = copy(data.contexts)->filter((_, group) => Same(group.current, raw.current) && Same(group.context, raw.context))
  if len(groups) != 1
    return
  endif
  var items = copy(groups[0].items)->map((_, item) => ({word: join(item.text, "\n"), abbr: item.label,
    menu: item.provenance, info: get(item, 'info', join(item.text, "\n")), user_data: deepcopy(item.handle), dup: 1, equal: 1, empty: 1}))
  if empty(items)
    return
  endif
  # Replacing a menu ends the previous completion inside complete(); record this one after.
  complete(raw.start + 1, items)
  b:surface_shown = {raw: raw, handles: mapnew(items, (_, item) => item.user_data)}
enddef

def Complete(findstart: number, _: string): any
  if findstart
    Request(true)
    return -3
  endif
  return []
enddef

def Forget()
  b:surface_serial += 1
  b:surface_again = false
  b:surface_asked = {}
enddef

# Only this surface's visible menu is recorded; native keyword or other menus are not.
def Completed()
  b:surface_done = {}
  var shown = b:surface_shown
  b:surface_shown = {}
  if empty(shown) || complete_info(['mode']).mode !=# 'eval'
      || !Same(mapnew(complete_info(['items']).items, (_, item) => item.user_data), shown.handles)
    return
  endif
  b:surface_done = {item: deepcopy(v:completed_item), base: shown.raw}
enddef

def Dismiss()
  b:surface_dismissed = Key()
enddef

# Native insertion may reshape multiline text. Only its own lines, ending at the
# cursor, become prefix + selection + suffix, or the original line if the rest changed.
def Apply()
  var done = get(b:, 'surface_done', {})
  b:surface_done = {}
  if empty(done)
    return
  endif
  defer Dismiss()
  if empty(done.item)
    return
  endif
  var raw = done.base
  var row = raw.cursor.line - 1
  var text = raw.working[row]
  var suffix = strpart(text, raw.cursor.column - 1)
  var lines = split(strpart(text, 0, raw.start) .. done.item.word .. suffix, "\n", 1)
  var last = line('.')
  var first = last - len(lines) + 1
  if first < 1 || !Same(getline(1, first - 1), slice(raw.working, 0, row))
      || !Same(getline(last + 1, '$'), slice(raw.working, row + 1))
      || strpart(getline('.'), col('.') - 1) !=# suffix
    if first < 1
      echo '文脈が変わりました。選択は記録しません'
      return
    endif
    if last > first
      deletebufline(bufnr(), first + 1, last)
    endif
    setline(first, text)
    cursor(first, raw.cursor.column)
    echo '文脈が変わりました。挿入を取り消し、選択は記録しません'
    return
  endif
  if !Same(getline(first, last), lines)
    setline(first, lines)
  endif
  cursor(last, strlen(lines[-1]) - strlen(suffix) + 1)
  b:surface_selection = {handle: deepcopy(done.item.user_data), base: raw,
    label: done.item.abbr, provenance: done.item.menu, info: done.item.info}
  echo $'{done.item.abbr}・{done.item.menu}（選択時・未採用 :SurfaceSelection）'
enddef

def ShowSelection()
  var selection = get(b:, 'surface_selection', {})
  if !has_key(selection, 'info')
    echo '読み返せる選択はありません'
    return
  endif
  echo $"選択時・未採用（現在のWorkingやAcceptedではありません）\n{selection.label}・{selection.provenance}\n{selection.info}"
enddef

export def Attach()
  if !exists('b:surface_selection')
    b:surface_selection = {}
  endif
  b:surface_serial = get(b:, 'surface_serial', 0) + 1
  b:surface_busy = get(b:, 'surface_busy', false)
  b:surface_again = false
  b:surface_asking = false
  b:surface_asked = {}
  b:surface_dismissed = {}
  b:surface_shown = {}
  b:surface_done = {}
  b:surface_error = ''
  setlocal completeopt=menuone,noselect,popup
  &l:completefunc = Complete
  augroup edits_surface
    autocmd! CompleteDonePre,CompleteDone,TextChangedI,TextChangedP,InsertLeave,BufLeave,WinLeave <buffer>
    autocmd CompleteDonePre <buffer> Completed()
    autocmd CompleteDone <buffer> Apply()
    autocmd TextChangedI,TextChangedP <buffer> Request()
    autocmd InsertLeave,BufLeave,WinLeave <buffer> Forget()
  augroup END
  command! -buffer SurfaceSelection ShowSelection()
enddef
