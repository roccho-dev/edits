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

def Envelope(raw: dict<any>): dict<any>
  return {input: deepcopy(raw.input),
    state: {current: deepcopy(raw.current), working: copy(raw.working), context: deepcopy(raw.context)},
    focus: {line: raw.cursor.line, column: raw.cursor.column, start: raw.start}}
enddef

# The owner answers this exact query; its proposals are kept whole in each handle.
def View(output: string, query: dict<any>, raw: dict<any>): dict<any>
  var result = json_decode(output)
  if !Exact(result, ['query', 'proposals', 'evaluation']) || !Same(result.query, query)
      || type(result.proposals) != v:t_list || type(result.evaluation) != v:t_dict
    throw 'invalid or unrelated semcmp result'
  endif
  var seen: list<string> = []
  var items: list<dict<any>> = []
  for proposal in result.proposals
    if !Exact(proposal, ['id', 'meaning', 'representation', 'evidence'])
        || type(proposal.id) != v:t_string || empty(trim(proposal.id)) || index(seen, proposal.id) >= 0
        || type(proposal.representation) != v:t_string || empty(trim(proposal.representation))
        || !Exact(proposal.evidence, ['theme', 'noul']) || proposal.evidence.theme != 'intent-fit'
        || index([v:t_number, v:t_float], type(proposal.evidence.noul)) < 0
        || !(proposal.evidence.noul >= 0 && proposal.evidence.noul <= 1)
      throw 'invalid semcmp proposal'
    endif
    add(seen, proposal.id)
    var text = split(proposal.representation, "\n", 1)
    add(items, {handle: deepcopy(proposal), label: text[0],
      provenance: $'intent-fit {proposal.evidence.noul}', text: text,
      info: "representation:\n" .. proposal.representation .. "\n\nmeaning: " .. json_encode(proposal.meaning)
        .. "\nevidence: " .. json_encode(proposal.evidence)})
  endfor
  return surface.ValidateView({schema: 'decision-completion.view/1',
    contexts: [{current: deepcopy(raw.current), context: deepcopy(raw.context), items: items}]})
enddef

# One nonblocking semcmp process per request; Deliver gets a view or a bounded failure code.
# The process lives at most two owner timeouts (proposing, then evaluating); the
# returned Funcref stops it earlier.
def Acquire(binary: string, proposer: string, raw: dict<any>, Deliver: func): any
  if empty(binary) || empty(proposer)
    Deliver('NOT_CONFIGURED')
    return v:null
  endif
  var query = Envelope(raw)
  var out: list<string> = []
  var err: list<string> = []
  var ended = {closed: false, exited: false, status: 0, late: false}
  var run = {job: v:null, timer: 0}
  var Stop = () => {
    if job_status(run.job) ==# 'run'
      job_stop(run.job, 'kill')
    endif
  }
  var Finish = () => {
    if !ended.closed || !ended.exited
      return
    endif
    timer_stop(run.timer)
    if ended.late
      Deliver('TIMEOUT')
    elseif ended.status != 0
      var code = trim(join(err, ''))
      Deliver(code =~# '^[A-Z_]\+$' ? code : 'SEMCMP')
    else
      try
        Deliver(View(join(out, ''), query, raw))
      catch
        Deliver('RESULT')
      endtry
    endif
  }
  run.job = job_start([binary, '--propose', proposer], {in_io: 'pipe', out_mode: 'raw', err_mode: 'raw',
    out_cb: (_, chunk) => add(out, chunk), err_cb: (_, chunk) => add(err, chunk),
    close_cb: (_) => {
      ended.closed = true
      Finish()
    },
    exit_cb: (_, status) => {
      ended.exited = true
      ended.status = status
      Finish()
    }})
  if job_status(run.job) ==# 'fail'
    Deliver('START')
    return v:null
  endif
  var limit = str2nr($JEV_TIMEOUT_MS) > 0 ? str2nr($JEV_TIMEOUT_MS) : 15000
  run.timer = timer_start(2 * limit, (_) => {
    ended.late = true
    Stop()
  })
  ch_sendraw(run.job, json_encode({query: query}))
  ch_close_in(run.job)
  return Stop
enddef

export def Attach(binary: string, proposer: string)
  if !exists('b:surface_query')
    b:surface_query = Query
  endif
  b:surface_source = {semcmp: binary, proposer: proposer}
  b:surface_acquire = function(Acquire, [binary, proposer])
  surface.Attach()
enddef
