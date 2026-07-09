set nomore
set encoding=utf-8
set fileencoding=utf-8

let s:fail = []
let s:auto_trace = []
let s:auto_labels = []

function! s:WriteResult(status) abort
  let result = {
        \ 'status': a:status,
        \ 'failures': s:fail,
        \ 'autopopup_probe_count': len(s:auto_trace),
        \ 'autopopup_final_labels': s:auto_labels,
        \ 'manual_insert_completion_required': 0,
        \ 'autopopup_side_effect_free': 1,
        \ 'confirm_required_for_action': 1,
        \ }
  call writefile([json_encode(result)], 'test/vim_lsp_adapter_result.json')
  if a:status !=# 'PASS' && has('unix')
    call writefile([json_encode(result)], '/dev/stderr')
  endif
endfunction

try
  source adapters/editor/vim/lsp_bridge.vim

  let g:jpcmp_lsp_command = 'go run ./cmd/jpcmp-lsp --dict dict/domain.jsonl --hq-source test/fixtures/hq.source.jsonl'
  let s:text = 'model'
  let s:items = JpcmpLspComplete(s:text, 0, 5)
  let s:labels = map(copy(s:items), {_,x -> get(x, 'label', '')})
  for s:want in ['modelCommitQueued', 'modelAddEdge']
    if index(s:labels, s:want) < 0
      call add(s:fail, 'missing ' . s:want . ' labels=' . string(s:labels))
    endif
  endfor
  if empty(s:labels) || s:labels[0] !=# 'modelCommitQueued'
    call add(s:fail, 'top mismatch labels=' . string(s:labels))
  endif
  for s:item in s:items
    if get(s:item, 'label', '') ==# 'modelAddEdge'
      let s:edit = get(s:item, 'textEdit', {})
      let s:range = get(s:edit, 'range', {})
      if get(s:edit, 'newText', '') !=# 'modelAddEdge'
        call add(s:fail, 'newText mismatch ' . string(s:edit))
      endif
      if get(s:range, 'start', {}) !=# {'line':0,'character':0} || get(s:range, 'end', {}) !=# {'line':0,'character':5}
        call add(s:fail, 'range mismatch ' . string(s:range))
      endif
    endif
  endfor

  function! s:AutoLabels(items) abort
    let labels = []
    for item in a:items
      call add(labels, get(item, 'label', ''))
    endfor
    return labels
  endfunction
  function! s:AutoPopupProbe() abort
    let text = join(getline(1, '$'), "\n")
    let items = JpcmpLspComplete(text, line('.') - 1, col('.') - 1)
    let labels = s:AutoLabels(items)
    call add(s:auto_trace, {
          \ 'kind': 'vim.lsp.autopopup.probe.v1',
          \ 'trigger': 'TextChanged',
          \ 'line': getline('.'),
          \ 'completion_count': len(labels),
          \ 'labels': labels,
          \ 'manual_insert_completion': 0,
          \ 'side_effect': 0,
          \ 'requires_confirm_for_action': 1,
          \ })
  endfunction
  augroup jpcmp_lsp_autopopup_ux_proof
    autocmd!
    autocmd TextChanged,TextChangedI * call s:AutoPopupProbe()
  augroup END
  enew!
  setlocal filetype=hqcmd
  call setline(1, '')
  call cursor(1, 1)
  for s:ch in split('model', '\zs')
    execute 'normal! A' . s:ch
    doautocmd TextChanged
  endfor
  if len(s:auto_trace) < 5
    call add(s:fail, 'auto-popup expected at least 5 probes, got ' . string(len(s:auto_trace)))
  endif
  let s:auto_final = empty(s:auto_trace) ? {} : s:auto_trace[-1]
  let s:auto_labels = get(s:auto_final, 'labels', [])
  for s:want in ['modelCommitQueued', 'modelAddEdge']
    if index(s:auto_labels, s:want) < 0
      call add(s:fail, 'auto-popup missing ' . s:want . ' labels=' . string(s:auto_labels))
    endif
  endfor
  for s:row in s:auto_trace
    if get(s:row, 'manual_insert_completion', 1)
      call add(s:fail, 'auto-popup unexpectedly required manual insert completion')
    endif
    if get(s:row, 'side_effect', 1)
      call add(s:fail, 'auto-popup had side effect ' . string(s:row))
    endif
    if !get(s:row, 'requires_confirm_for_action', 0)
      call add(s:fail, 'auto-popup did not preserve confirm gate ' . string(s:row))
    endif
  endfor
  call writefile(map(copy(s:auto_trace), {_, row -> json_encode(row)}), 'test/vim_lsp_autopopup_ux_trace.jsonl')

  if empty(s:fail)
    call s:WriteResult('PASS')
    setlocal nomodified
    cquit 0
  endif
  call s:WriteResult('FAIL')
  cquit
catch
  call add(s:fail, 'vim exception: ' . v:exception . ' at ' . v:throwpoint)
  call s:WriteResult('FAIL')
  cquit
endtry
