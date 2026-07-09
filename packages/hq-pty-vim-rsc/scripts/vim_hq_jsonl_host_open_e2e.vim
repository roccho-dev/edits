set nomore
let s:hq = get(g:, 'hqwin_bin', 'dist/hq.exe')
let s:queue = get(g:, 'hq_host_open_queue', 'cache/vim-host-open.queue.jsonl')
let s:receipts = get(g:, 'hq_host_open_receipts', 'cache/vim-host-open.receipts.jsonl')
let s:explorer = get(g:, 'hq_explorer_bin', 'dist/fake-explorer.exe')
let s:target = get(g:, 'hq_host_open_target', getcwd())
let s:summary = get(g:, 'hq_host_open_summary', 'cache/vim-hq-jsonl-host-open-e2e.json')

call delete(s:queue)
call delete(s:receipts)
call delete(s:summary)

let s:append_out = system([s:hq,
      \ 'host-open-append',
      \ '--queue', s:queue,
      \ '--id', 'vim-open-edits-001',
      \ '--path', s:target,
      \ '--mode', 'open',
      \ '--source', 'vim',
      \ '--confirmed'])
if v:shell_error != 0
  call writefile([json_encode({'kind':'proof.vim-hq-jsonl-host-open','ok':v:false,'phase':'append','output':s:append_out})], s:summary)
  cquit 1
endif

let s:dispatch_out = system([s:hq,
      \ 'host-open-dispatch',
      \ '--queue', s:queue,
      \ '--receipts', s:receipts,
      \ '--explorer-bin', s:explorer,
      \ '--execute'])
if v:shell_error != 0
  call writefile([json_encode({'kind':'proof.vim-hq-jsonl-host-open','ok':v:false,'phase':'dispatch','output':s:dispatch_out})], s:summary)
  cquit 1
endif

call writefile([json_encode({
      \ 'kind':'proof.vim-hq-jsonl-host-open',
      \ 'ok':v:true,
      \ 'vim_called':'hqwin',
      \ 'direct_explorer_from_vim':v:false,
      \ 'queue':s:queue,
      \ 'receipts':s:receipts,
      \ 'target':s:target
      \ })], s:summary)
cquit 0
