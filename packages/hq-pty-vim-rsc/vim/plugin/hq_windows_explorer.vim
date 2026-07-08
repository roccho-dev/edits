if exists('g:loaded_hq_windows_explorer')
  finish
endif
let g:loaded_hq_windows_explorer = 1
command! -nargs=1 HqExplorerPreview echo hq_windows_explorer#preview(<q-args>)
command! -nargs=1 HqExplorerOpen call hq_windows_explorer#open(<q-args>)
command! HqExplorerComplete setlocal completefunc=hq_windows_explorer#complete
