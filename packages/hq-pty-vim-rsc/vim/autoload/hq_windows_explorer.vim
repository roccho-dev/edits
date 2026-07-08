function! hq_windows_explorer#complete(findstart, base) abort
  if a:findstart
    let l:line = getline('.')
    let l:start = col('.') - 1
    while l:start > 0 && l:line[l:start - 1] =~# '\k'
      let l:start -= 1
    endwhile
    return l:start
  endif
  let l:hq = get(g:, 'hq_bin', 'hq')
  let l:home = get(g:, 'hq_windows_home', $USERPROFILE)
  let l:cmd = l:hq . ' windows-explorer-complete --home ' . shellescape(l:home) . ' --base ' . shellescape(a:base)
  let l:raw = system(l:cmd)
  if v:shell_error != 0
    return []
  endif
  let l:decoded = json_decode(l:raw)
  let l:out = []
  for l:item in get(l:decoded, 'items', [])
    call add(l:out, {
          \ 'word': get(l:item, 'name', ''),
          \ 'abbr': get(l:item, 'name', ''),
          \ 'menu': '[explorer]',
          \ 'info': get(l:item, 'path', ''),
          \ 'kind': 'd',
          \ 'user_data': json_encode({'target': get(l:item, 'name', ''), 'path': get(l:item, 'path', ''), 'action': 'explorer.open'})
          \ })
  endfor
  return l:out
endfunction

function! hq_windows_explorer#preview(target) abort
  let l:hq = get(g:, 'hq_bin', 'hq')
  let l:home = get(g:, 'hq_windows_home', $USERPROFILE)
  return system(l:hq . ' windows-explorer-preview --home ' . shellescape(l:home) . ' --target ' . shellescape(a:target))
endfunction

function! hq_windows_explorer#open(target) abort
  let l:hq = get(g:, 'hq_bin', 'hq')
  let l:home = get(g:, 'hq_windows_home', $USERPROFILE)
  execute 'silent !' . l:hq . ' windows-explorer-preview --execute --home ' . shellescape(l:home) . ' --target ' . shellescape(a:target)
endfunction
