vim9script
import './surface.vim' as surface

def Exact(value: any, names: list<string>): bool
  return type(value) == v:t_dict && sort(keys(value)) == sort(copy(names))
enddef

def Same(left: any, right: any): bool
  if index([v:t_number, v:t_float], type(left)) >= 0 && index([v:t_number, v:t_float], type(right)) >= 0
    return left == right
  endif
  if type(left) != type(right)
    return false
  endif
  if type(left) == v:t_dict
    return sort(keys(left)) == sort(keys(right)) && empty(filter(keys(left), (_, key) => !Same(left[key], right[key])))
  elseif type(left) == v:t_list
    if len(left) != len(right)
      return false
    endif
    for i in range(len(left))
      if !Same(left[i], right[i])
        return false
      endif
    endfor
    return true
  endif
  return left ==# right
enddef

def Query(raw: dict<any>): dict<any>
  return {start: 0, input: strpart(raw.working[raw.cursor.line - 1], 0, raw.cursor.column - 1)}
enddef

def Acquire(binary: string, catalog: string, raw: dict<any>): dict<any>
  if empty(binary) || empty(catalog)
    throw 'semcmp executable and catalog must be configured'
  endif
  var bytes = readfile(catalog, 'b')
  var supplied = json_decode(join(bytes, "\n"))
  if type(supplied) != v:t_list
    throw 'invalid semcmp catalog'
  endif
  var ids: list<string> = []
  for item in supplied
    if !Exact(item, ['id', 'meaning', 'representation']) || type(item.id) != v:t_string
        || empty(trim(item.id)) || index(ids, item.id) >= 0
        || type(item.representation) != v:t_string || empty(trim(item.representation))
      throw 'invalid semcmp catalog item'
    endif
    add(ids, item.id)
  endfor
  var query = {input: deepcopy(raw.input),
    state: {current: deepcopy(raw.current), working: copy(raw.working), context: deepcopy(raw.context)},
    focus: {line: raw.cursor.line, column: raw.cursor.column, start: raw.start}}
  silent var output = system([binary], json_encode({query: query, proposals: supplied}))
  if v:shell_error != 0 || !Same(bytes, readfile(catalog, 'b'))
    throw 'semcmp failed or catalog changed'
  endif
  var result = json_decode(output)
  if !Exact(result, ['query', 'proposals', 'evaluation']) || !Same(result.query, query)
      || type(result.proposals) != v:t_list || len(result.proposals) != len(supplied)
      || type(result.evaluation) != v:t_dict
    throw 'invalid or unrelated semcmp result'
  endif
  var seen: list<string> = []
  var items: list<dict<any>> = []
  for proposal in result.proposals
    if !Exact(proposal, ['id', 'meaning', 'representation', 'evidence'])
        || type(proposal.id) != v:t_string || index(seen, proposal.id) >= 0
        || index(ids, proposal.id) < 0
      throw 'invalid semcmp proposal identity'
    endif
    var original = supplied[index(ids, proposal.id)]
    if !Same(proposal.meaning, original.meaning) || !Same(proposal.representation, original.representation)
        || !Exact(proposal.evidence, ['theme', 'noul']) || proposal.evidence.theme != 'intent-fit'
        || index([v:t_number, v:t_float], type(proposal.evidence.noul)) < 0
        || !(proposal.evidence.noul >= 0 && proposal.evidence.noul <= 1)
      throw 'invalid semcmp proposal correspondence'
    endif
    add(seen, proposal.id)
    var text = split(proposal.representation, "\n", 1)
    add(items, {handle: deepcopy(proposal), label: text[0],
      provenance: $'intent-fit {proposal.evidence.noul}', text: text})
  endfor
  return surface.ValidateView({schema: 'decision-completion.view/1',
    contexts: [{current: deepcopy(raw.current), context: deepcopy(raw.context), items: items}]})
enddef

export def Attach(binary: string, catalog: string)
  if !exists('b:surface_query')
    b:surface_query = Query
  endif
  b:surface_source = {semcmp: binary, catalog: catalog}
  b:surface_acquire = function(Acquire, [binary, catalog])
  surface.Attach()
enddef
