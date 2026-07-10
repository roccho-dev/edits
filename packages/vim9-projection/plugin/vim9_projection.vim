vim9script

if exists('g:loaded_vim9_projection')
  finish
endif
g:loaded_vim9_projection = 1

const PropType = 'Vim9ProjectionVirtual'
var EffectiveMaps: list<dict<any>> = []


def ValidateMap(value: any, line_number: number): dict<any>
  if type(value) != v:t_dict
    throw $'vim9-projection: line {line_number} must be a JSON object'
  endif

  var item: dict<any> = value
  for key in ['id', 'pattern', 'display']
    if !has_key(item, key) || type(item[key]) != v:t_string || item[key] ==# ''
      throw $'vim9-projection: line {line_number} requires non-empty string {key}'
    endif
  endfor

  if has_key(item, 'enabled') && type(item.enabled) != v:t_bool
    throw $'vim9-projection: line {line_number} enabled must be boolean'
  endif
  if has_key(item, 'priority') && type(item.priority) != v:t_number
    throw $'vim9-projection: line {line_number} priority must be a number'
  endif

  try
    matchstrpos('', item.pattern)
  catch
    throw $'vim9-projection: line {line_number} has invalid pattern: {v:exception}'
  endtry

  return item
enddef


def ReduceMaps(path: string): list<dict<any>>
  var by_id: dict<dict<any>> = {}
  var order: list<string> = []
  var line_number = 0

  for line in readfile(path)
    line_number += 1
    if trim(line) ==# ''
      continue
    endif

    var item = ValidateMap(json_decode(line), line_number)
    var id: string = item.id
    if !has_key(by_id, id)
      order->add(id)
    endif
    by_id[id] = item
  endfor

  var reduced: list<dict<any>> = []
  for id in order
    var item = by_id[id]
    if get(item, 'enabled', true)
      reduced->add(item)
    endif
  endfor
  return reduced
enddef


def ClearWindowMatches()
  for id in get(w:, 'vim9_projection_match_ids', [])
    silent! matchdelete(id)
  endfor
  w:vim9_projection_match_ids = []
enddef


def ClearBufferProperties()
  var buffer_number = bufnr()
  if !empty(prop_type_get(PropType, {bufnr: buffer_number}))
    prop_remove({type: PropType, bufnr: buffer_number, all: true})
  endif
enddef


def EnsurePropertyType()
  var buffer_number = bufnr()
  if empty(prop_type_get(PropType, {bufnr: buffer_number}))
    prop_type_add(PropType, {
      bufnr: buffer_number,
      combine: true,
    })
  endif
enddef


def SaveConcealOptions()
  if !exists('b:vim9_projection_saved_conceallevel')
    b:vim9_projection_saved_conceallevel = &l:conceallevel
    b:vim9_projection_saved_concealcursor = &l:concealcursor
  endif
enddef


def RestoreConcealOptions()
  if exists('b:vim9_projection_saved_conceallevel')
    &l:conceallevel = b:vim9_projection_saved_conceallevel
    &l:concealcursor = b:vim9_projection_saved_concealcursor
    unlet b:vim9_projection_saved_conceallevel
    unlet b:vim9_projection_saved_concealcursor
  endif
enddef


def ApplyProjection()
  ClearWindowMatches()
  ClearBufferProperties()
  EnsurePropertyType()
  SaveConcealOptions()
  &l:conceallevel = 3
  &l:concealcursor = 'nvic'

  var match_ids: list<number> = []
  var property_count = 0

  for item in EffectiveMaps
    var priority: number = get(item, 'priority', 10)
    var pattern: string = item.pattern
    var display: string = item.display

    for line_number in range(1, line('$'))
      var text = getline(line_number)
      var start = 0
      while start <= strlen(text)
        var found = matchstrpos(text, pattern, start)
        var start_byte: number = found[1]
        var end_byte: number = found[2]
        if start_byte < 0
          break
        endif
        if end_byte <= start_byte
          throw $'vim9-projection: zero-width match is not allowed for {item.id}'
        endif

        var match_id = matchaddpos(
          'Conceal',
          [[line_number, start_byte + 1, end_byte - start_byte]],
          priority)
        if match_id < 0
          throw $'vim9-projection: failed to conceal {item.id}'
        endif
        match_ids->add(match_id)
        prop_add(line_number, start_byte + 1, {
          type: PropType,
          text: display,
          bufnr: bufnr(),
        })
        property_count += 1
        start = end_byte
      endwhile
    endfor
  endfor

  w:vim9_projection_match_ids = match_ids
  b:vim9_projection_effective_maps = len(EffectiveMaps)
  b:vim9_projection_match_count = len(match_ids)
  b:vim9_projection_property_count = property_count
enddef


def LoadAndApply(path: string)
  var absolute = fnamemodify(path, ':p')
  if !filereadable(absolute)
    throw $'vim9-projection: map file is not readable: {absolute}'
  endif

  # Reduction completes before replacing the active set, so malformed JSONL
  # cannot leave a partially loaded projection.
  var reduced = ReduceMaps(absolute)
  EffectiveMaps = reduced
  g:vim9_projection_map_path = absolute
  ApplyProjection()
enddef


def ClearProjection()
  ClearWindowMatches()
  ClearBufferProperties()
  RestoreConcealOptions()
  b:vim9_projection_match_count = 0
  b:vim9_projection_property_count = 0
enddef

command! -nargs=1 -complete=file Vim9ProjectionLoad LoadAndApply(<q-args>)
command! -nargs=0 Vim9ProjectionApply ApplyProjection()
command! -nargs=0 Vim9ProjectionClear ClearProjection()
