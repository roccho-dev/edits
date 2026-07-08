function! hq_autocmp#probe() abort
  let l:world = get(g:, 'hq_autocmp_world', 'examples/world.jsonl')
  let l:log = get(g:, 'hq_autocmp_log', 'cache/vim-autocmp.jsonl')
  let l:line = getline('.')
  let l:cmd = 'go run ./cmd/hq complete --world ' . shellescape(l:world) . ' --line ' . shellescape(l:line) . ' --version ' . shellescape(string(b:changedtick))
  let l:out = system(l:cmd)
  let l:items = json_decode(l:out)
  let l:labels = []
  if type(l:items) == v:t_list
    for l:item in l:items
      call add(l:labels, get(l:item, 'label', ''))
    endfor
  endif
  let l:row = {'kind': 'vim.autocmp.probe', 'changedtick': b:changedtick, 'line': l:line, 'completion_count': len(l:labels), 'labels': l:labels}
  call writefile([json_encode(l:row)], l:log, 'a')
endfunction
