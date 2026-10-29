vim9script
# Contract trace integrity for this Package; no external provider or credentials.
const root = fnamemodify(expand('<sfile>:p'), ':h:h')
const rows = readfile(root .. '/contracts.jsonl')->filter((_, line) => !empty(line))->map((_, line) => json_decode(line))
var seen: dict<bool> = {}
var operations = 0
var failures = 0
for record in rows
  if type(record) != v:t_dict || !has_key(record, 'id') || type(record.id) != v:t_string || empty(record.id) || has_key(seen, record.id)
    failures += 1
    continue
  endif
  seen[record.id] = true
  if record.kind ==# 'operation'
    operations += 1
    if !has_key(record, 'provided') || record.provided !~# '^packages/vim/' || !has_key(record, 'status')
      failures += 1
      continue
    endif
    if empty(get(record, 'anchor', ''))
      if record.status !~# 'unobserved'
        failures += 1
      endif
      continue
    endif
    var path = root .. '/' .. substitute(record.provided, '^packages/vim/', '', '')
    if !filereadable(path) || len(filter(readfile(path), (_, line) => stridx(line, record.anchor) >= 0)) != 1
      failures += 1
    endif
    if record.status =~# 'PASS\|accepted\|conformant'
      failures += 1
    endif
  endif
endfor
if len(rows) < 9 || operations < 6 || failures != 0
  echomsg 'contract trace failed: ' .. failures .. ' failures, ' .. operations .. ' operations'
  cquit 1
endif
echomsg 'contract trace structure and exact anchors PASS (' .. operations .. ' operations; execution claims still unobserved)'
quitall!
