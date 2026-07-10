let s:server = 'hq-lsp'
let s:last_response = {}
let s:done = 0

function! hq#doctor() abort
  let l:hq = get(g:, 'hq_bin', 'hq')
  return {
        \ 'vim_lsp': !empty(globpath(&runtimepath, 'autoload/lsp.vim')),
        \ 'hq_bin': l:hq,
        \ 'hq_bin_ok': executable(l:hq),
        \ 'profile': get(g:, 'hq_profile', 'local'),
        \ }
endfunction

function! hq#start(...) abort
  if empty(globpath(&runtimepath, 'autoload/lsp.vim'))
    throw 'hq.vim requires vim-lsp on runtimepath'
  endif
  runtime plugin/lsp.vim
  let l:profile = a:0 == 1 && !empty(a:1) ? a:1 : get(g:, 'hq_profile', 'local')
  let l:hq = get(g:, 'hq_bin', 'hq')
  if !executable(l:hq)
    throw 'hq.vim requires hq on PATH or an executable g:hq_bin'
  endif
  if empty(l:profile)
    throw 'hq.vim requires a non-empty hq profile'
  endif
  let s:server = get(g:, 'hq_server_name', 'hq-lsp')
  call lsp#register_server({
        \ 'name': s:server,
        \ 'cmd': [l:hq, 'lsp', '--profile', l:profile],
        \ 'allowlist': ['hqjson'],
        \ })
  call lsp#enable()
  call lsp#activate()
  return 1
endfunction

function! hq#request(method, params) abort
  let s:done = 0
  let s:last_response = {}
  call lsp#send_request(s:server, {
        \ 'method': a:method,
        \ 'params': a:params,
        \ 'on_notification': function('s:on_response'),
        \ })
  let l:wait_result = lsp#utils#_wait(5000, {-> s:done}, 10)
  if l:wait_result != 0
    throw 'vim-lsp request timed out: ' . a:method
  endif
  if !has_key(s:last_response, 'response')
    throw 'vim-lsp response missing for ' . a:method . ': ' . string(s:last_response)
  endif
  return s:last_response.response
endfunction

function! hq#submit() abort
  let l:line_nr = line('.') - 1
  let l:line_len = strlen(getline('.'))
  let l:action_response = hq#request('textDocument/codeAction', {
        \ 'textDocument': lsp#get_text_document_identifier(),
        \ 'range': {
        \   'start': {'line': l:line_nr, 'character': 0},
        \   'end': {'line': l:line_nr, 'character': l:line_len},
        \ },
        \ 'context': {'diagnostics': []},
        \ })
  let l:actions = get(l:action_response, 'result', [])
  if type(l:actions) != v:t_list || empty(l:actions)
    throw 'no hq code actions returned'
  endif
  let l:cmd = get(l:actions[0], 'command', {})
  if get(l:cmd, 'command', '') !=# 'hq.submit'
    throw 'unexpected hq command action: ' . string(l:cmd)
  endif
  let l:exec_response = hq#request('workspace/executeCommand', l:cmd)
  let l:result = get(l:exec_response, 'result', {})
  if get(l:result, 'kind', '') !=# 'hq.submitResult.v1' || get(l:result, 'status', '') !=# 'queued'
    throw 'hq.submit did not queue the buffer: ' . string(l:result)
  endif
  return l:result
endfunction

function! s:on_response(data) abort
  let s:last_response = a:data
  let s:done = 1
endfunction
