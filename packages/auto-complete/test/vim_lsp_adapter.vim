set nomore
set encoding=utf-8
set fileencoding=utf-8
source adapters/editor/vim/lsp_bridge.vim
let s:text = "houjinScore houjinRepository houjinbaikyakuPlan hogeBufferOnly\nhouji"
let s:items = JpcmpLspComplete(s:text, 1, 5)
let s:labels = map(copy(s:items), {_,x -> get(x, 'label', '')})
let s:fail = []
for s:want in ['houjinScore', '法人', '法人売却']
  if index(s:labels, s:want) < 0
    call add(s:fail, 'missing ' . s:want . ' labels=' . string(s:labels))
  endif
endfor
if empty(s:labels) || s:labels[0] !=# 'houjinScore'
  call add(s:fail, 'top mismatch labels=' . string(s:labels))
endif
for s:item in s:items
  if get(s:item, 'label', '') ==# '法人売却'
    let s:edit = get(s:item, 'textEdit', {})
    let s:range = get(s:edit, 'range', {})
    if get(s:edit, 'newText', '') !=# '法人売却'
      call add(s:fail, 'newText mismatch ' . string(s:edit))
    endif
    if get(s:range, 'start', {}) !=# {'line':1,'character':0} || get(s:range, 'end', {}) !=# {'line':1,'character':5}
      call add(s:fail, 'range mismatch ' . string(s:range))
    endif
  endif
endfor
call writefile([json_encode({'status': empty(s:fail) ? 'PASS' : 'FAIL', 'failures': s:fail})], 'test/vim_lsp_adapter_result.json')
if !empty(s:fail)
  cquit
endif
qa!
