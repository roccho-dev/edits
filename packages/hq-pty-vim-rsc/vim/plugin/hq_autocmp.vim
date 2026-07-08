if exists('g:loaded_hq_autocmp')
  finish
endif
let g:loaded_hq_autocmp = 1
augroup hq_autocmp
  autocmd!
  autocmd TextChanged,TextChangedI * call hq_autocmp#probe()
augroup END
command! HqAutocmpProbe call hq_autocmp#probe()
