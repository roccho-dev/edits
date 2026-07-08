" Vim adapter proof for jpcmp-lsp.
" This file intentionally contains no dictionary parsing, rank merge, or candidate generation.

function! JpcmpLspFrame(payload) abort
  let body = json_encode(a:payload)
  return 'Content-Length: ' . strlen(body) . "\r\n\r\n" . body
endfunction

function! JpcmpLspResponses(raw) abort
  let out = []
  let pos = 0
  while 1
    let start = match(a:raw, 'Content-Length: \d\+\r\n\r\n', pos)
    if start < 0
      break
    endif
    let header = matchstr(a:raw, 'Content-Length: \d\+\r\n\r\n', start)
    let n = str2nr(matchstr(header, '\d\+'))
    let body_start = start + strlen(header)
    let body = strpart(a:raw, body_start, n)
    call add(out, json_decode(body))
    let pos = body_start + n
  endwhile
  return out
endfunction

function! JpcmpLspComplete(text, line, character) abort
  let uri = 'file:///vim-lsp-golden.txt'
  let input = ''
  let input .= JpcmpLspFrame({'jsonrpc':'2.0','id':1,'method':'initialize','params':{}})
  let input .= JpcmpLspFrame({'jsonrpc':'2.0','method':'textDocument/didOpen','params':{'textDocument':{'uri':uri,'text':a:text}}})
  let input .= JpcmpLspFrame({'jsonrpc':'2.0','id':2,'method':'textDocument/completion','params':{'textDocument':{'uri':uri},'position':{'line':a:line,'character':a:character}}})
  let input .= JpcmpLspFrame({'jsonrpc':'2.0','method':'exit'})
  let raw = system('go run ./cmd/jpcmp-lsp --dict dict/domain.jsonl', input)
  let responses = JpcmpLspResponses(raw)
  for r in responses
    if has_key(r, 'id') && r.id ==# 2
      return get(r, 'result', [])
    endif
  endfor
  throw 'jpcmp-lsp completion response not found: ' . raw
endfunction
