vim9script

set nomore
set noswapfile
set encoding=utf-8

var root = fnamemodify(expand('<sfile>:p'), ':h:h')
execute 'set runtimepath^=' .. fnameescape(root)
runtime plugin/vim9_projection.vim

var input = root .. '/test/input.txt'
var maps = root .. '/test/maps.jsonl'
var invalid_maps = root .. '/test/invalid-zero-width.jsonl'
var before = sha256(readfile(input, 'b')->join("\n"))

execute 'edit ' .. fnameescape(input)
execute 'Vim9ProjectionLoad ' .. fnameescape(maps)

assert_equal(4, b:vim9_projection_effective_maps)
assert_equal(4, b:vim9_projection_match_count)
assert_equal(4, b:vim9_projection_property_count)
assert_equal(4, len(getmatches()))
assert_equal(4, len(prop_list(1, {
  end_lnum: line('$'),
  types: ['Vim9ProjectionVirtual'],
})))
assert_equal(1, search('\<ceo\>', 'nw'))
assert_equal('role: ceo', getline(1))

# A later invalid map must be rejected before the current valid display is
# replaced or partially cleared.
writefile([
  '{"id":"valid.first","pattern":"\\<ceo\\>","display":"valid"}',
  '{"id":"invalid.zero","pattern":"^","display":"invalid"}',
], invalid_maps)
var invalid_rejected = false
try
  execute 'Vim9ProjectionLoad ' .. fnameescape(invalid_maps)
catch /zero-width/
  invalid_rejected = true
endtry
assert_true(invalid_rejected)
assert_equal(4, b:vim9_projection_effective_maps)
assert_equal(4, len(getmatches()))
assert_equal(4, len(prop_list(1, {
  end_lnum: line('$'),
  types: ['Vim9ProjectionVirtual'],
})))
delete(invalid_maps)

silent write
var after = sha256(readfile(input, 'b')->join("\n"))
assert_equal(before, after)

Vim9ProjectionClear
assert_equal(0, len(getmatches()))
assert_equal(0, len(prop_list(1, {
  end_lnum: line('$'),
  types: ['Vim9ProjectionVirtual'],
})))
assert_equal('role: ceo', getline(1))

# Conceal options are window-local. Applying and clearing in a split must
# restore that split without changing the original window's local values.
setlocal conceallevel=1
setlocal concealcursor=n
split
setlocal conceallevel=2
setlocal concealcursor=v
Vim9ProjectionApply
Vim9ProjectionClear
assert_equal(2, &l:conceallevel)
assert_equal('v', &l:concealcursor)
wincmd p
assert_equal(1, &l:conceallevel)
assert_equal('n', &l:concealcursor)
wincmd p
close

if !empty(v:errors)
  writefile(v:errors, root .. '/test/failures.log')
  cquit 1
endif

writefile([
  'proof_pass=true',
  'input_rows=5',
  'effective_maps=4',
  'matches=4',
  'properties=4',
  'raw_search=true',
  'hash_equal=true',
  'invalid_map_atomic=true',
  'window_options_restored=true',
], root .. '/test/proof.out')
qa!
