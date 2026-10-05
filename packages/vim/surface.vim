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

def Complete(findstart: number, prefix: string): any
  if findstart
    b:surface_base = {}
    b:surface_pending = {}
    var raw = Snapshot()
    var Query = get(b:, 'surface_query', v:null)
    var Acquire = get(b:, 'surface_acquire', v:null)
    try
      if type(Query) != v:t_func || type(Acquire) != v:t_func
        throw 'surface_query and surface_acquire must be Funcrefs'
      endif
      var query = call(Query, [deepcopy(raw)])
      var end = raw.cursor.column - 1
      var text = raw.working[raw.cursor.line - 1]
      if !Unchanged(raw, Query, Acquire) || type(query) != v:t_dict
          || sort(keys(query)) != ['input', 'start'] || type(query.start) != v:t_number
          || query.start < 0 || query.start > end
          || byteidx(text, charidx(text, query.start)) != query.start
        throw 'invalid or stale query'
      endif
      raw.start = query.start
      raw.input = deepcopy(query.input)
      b:surface_pending = {raw: raw, Query: Query, Acquire: Acquire}
      return query.start
    catch
      echo '補完を取得できません。編集は保持します'
      return -3
    endtry
  endif

  var pending = get(b:, 'surface_pending', {})
  b:surface_pending = {}
  b:surface_base = {}
  if empty(pending)
    return []
  endif
  var raw = pending.raw
  var native = Snapshot()
  var expected = copy(raw.working)
  var row = raw.cursor.line - 1
  var end = raw.cursor.column - 1
  var text = expected[row]
  expected[row] = strpart(text, 0, raw.start) .. strpart(text, end)
  if native.buffer != raw.buffer || native.cursor.line != raw.cursor.line
      || native.cursor.column != raw.start + 1
      || !Same(native.working, expected) || prefix != strpart(text, raw.start, end - raw.start)
      || !Same(raw.source, native.source) || !Same(raw.current, native.current)
      || !Same(raw.context, native.context)
      || !Same(pending.Query, get(b:, 'surface_query', v:null))
      || !Same(pending.Acquire, get(b:, 'surface_acquire', v:null))
    return []
  endif
  var data: dict<any>
  try
    data = ValidateView(call(pending.Acquire, [deepcopy(raw)]))
  catch
    echo '候補を取得できません。編集は保持します'
    return []
  endtry
  if !Unchanged(native, pending.Query, pending.Acquire)
    echo '文脈が変わりました。再補完してください'
    return []
  endif
  var groups = copy(data.contexts)->filter((_, group) => Same(group.current, raw.current) && Same(group.context, raw.context))
  if len(groups) != 1
    return []
  endif
  b:surface_base = raw
  return copy(groups[0].items)->map((_, item) => ({word: join(item.text, "\n"), abbr: item.label,
    menu: item.provenance, info: get(item, 'info', join(item.text, "\n")), user_data: deepcopy(item.handle), dup: 1, equal: 1, empty: 1}))
enddef

def Completed()
  b:surface_done = {}
  if complete_info(['mode']).mode != 'function' || empty(get(b:, 'surface_base', {}))
      || !Same(&l:completefunc, string(Complete)) || empty(v:completed_item)
    return
  endif
  b:surface_done = {item: deepcopy(v:completed_item), base: deepcopy(b:surface_base)}
enddef

def Replace(first: number, count: number, lines: list<string>)
  if count > len(lines)
    deletebufline(bufnr(), first + len(lines), first + count - 1)
  elseif count < len(lines)
    append(first + count - 1, repeat([''], len(lines) - count))
  endif
  setline(first, lines)
enddef

# Native insertion may reshape multiline text. Only its own lines, ending at the
# cursor, become prefix + selection + suffix, or the original line if the rest changed.
def Apply()
  var done = get(b:, 'surface_done', {})
  b:surface_done = {}
  if empty(done)
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
    if first >= 1
      Replace(first, len(lines), [text])
      cursor(first, raw.cursor.column)
    endif
    echo '文脈が変わりました。挿入を取り消し、選択は記録しません'
    return
  endif
  if !Same(getline(first, last), lines)
    Replace(first, len(lines), lines)
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
  b:surface_base = {}
  b:surface_pending = {}
  b:surface_done = {}
  setlocal completeopt=menuone,noselect,popup
  &l:completefunc = Complete
  augroup edits_surface
    autocmd! CompleteDonePre,CompleteDone <buffer>
    autocmd CompleteDonePre <buffer> Completed()
    autocmd CompleteDone <buffer> Apply()
  augroup END
  command! -buffer SurfaceSelection ShowSelection()
enddef
