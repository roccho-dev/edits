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
  if complete_info(['mode']).mode != 'function' || empty(get(b:, 'surface_base', {}))
      || !Same(&l:completefunc, string(Complete))
    return
  endif
  if !empty(v:completed_item)
    b:surface_selection = {handle: deepcopy(v:completed_item.user_data), base: deepcopy(b:surface_base)}
    echo $'{v:completed_item.abbr}・{v:completed_item.menu}（未採用）'
  endif
enddef

export def Attach()
  if !exists('b:surface_selection')
    b:surface_selection = {}
  endif
  b:surface_base = {}
  b:surface_pending = {}
  setlocal completeopt=menuone,noselect,popup
  &l:completefunc = Complete
  augroup edits_surface
    autocmd! CompleteDonePre <buffer>
    autocmd CompleteDonePre <buffer> Completed()
  augroup END
enddef
