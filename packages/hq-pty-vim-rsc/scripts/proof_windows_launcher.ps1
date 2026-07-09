function Invoke-Go {
  param([string[]]$GoArgs)
  $mise = Get-Command mise.exe -ErrorAction SilentlyContinue
  if ($mise) {
    & $mise.Source x go@1.23.2 -- go @GoArgs
  } else {
    & go @GoArgs
  }
  if ($LASTEXITCODE -ne 0) {
    throw "go $($GoArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
}

New-Item -ItemType Directory -Force -Path cache, dist | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue `
  cache\windows-launcher-smoke.json, `
  cache\vim-host-open.queue.jsonl, `
  cache\vim-host-open.receipts.jsonl, `
  cache\vim-hq-jsonl-host-open-e2e.json, `
  cache\fake-explorer-invoked.json

Invoke-Go -GoArgs @('build', '-o', 'dist/hq.exe', './cmd/hqwin')
Invoke-Go -GoArgs @('build', '-o', 'dist/fake-explorer.exe', './cmd/fake-explorer')
.\dist\hq.exe windows-launcher-smoke --home 'C:\Users\resta' --out cache\windows-launcher-smoke.json

$smoke = Get-Content cache\windows-launcher-smoke.json -Raw | ConvertFrom-Json
if (-not $smoke.ok) { throw 'windows launcher retired smoke did not return ok=true' }
if (-not $smoke.direct_explorer_side_retired) { throw 'direct explorer side was not marked retired' }
if (-not $smoke.side_effect_free) { throw 'retired launcher smoke must be side-effect free' }
if (-not $smoke.requires_hq_semantic_intent) { throw 'host path opening must require hq semantic intent' }

$env:HQ_FAKE_EXPLORER_RECEIPT = (Resolve-Path cache).Path + '\fake-explorer-invoked.json'
$target = (Resolve-Path .).Path
$vimPath = $null
$vim = Get-Command vim.exe -ErrorAction SilentlyContinue
if ($vim) {
  $vimPath = $vim.Source
}
if ($mise) {
  $resolvedVim = & $mise.Source x vim@latest -- where.exe vim 2>$null | Select-Object -First 1
  if ($LASTEXITCODE -eq 0 -and $resolvedVim) {
    $vimPath = $resolvedVim
  }
}
if (-not $vimPath) {
  throw 'vim.exe is required for the Vim -> hq JSONL host-open proof'
}

& $vimPath --clean -Nu NONE -n -es `
  --cmd "let g:hqwin_bin='dist/hq.exe'" `
  --cmd "let g:hq_explorer_bin='dist/fake-explorer.exe'" `
  --cmd "let g:hq_host_open_target='$target'" `
  --cmd "let g:hq_host_open_queue='cache/vim-host-open.queue.jsonl'" `
  --cmd "let g:hq_host_open_receipts='cache/vim-host-open.receipts.jsonl'" `
  --cmd "let g:hq_host_open_summary='cache/vim-hq-jsonl-host-open-e2e.json'" `
  -S scripts/vim_hq_jsonl_host_open_e2e.vim
if ($LASTEXITCODE -ne 0) {
  throw "Vim hq JSONL host-open proof failed with exit code $LASTEXITCODE"
}

$summary = Get-Content cache\vim-hq-jsonl-host-open-e2e.json -Raw | ConvertFrom-Json
if (-not $summary.ok) { throw 'Vim hq JSONL host-open summary did not return ok=true' }
if ($summary.vim_called -ne 'hqwin') { throw 'Vim proof must call hqwin, not explorer.exe directly' }
if ($summary.direct_explorer_from_vim) { throw 'Vim proof must not call explorer.exe directly' }

$queue = Get-Content cache\vim-host-open.queue.jsonl -Raw | ConvertFrom-Json
if ($queue.kind -ne 'hq.hostPathOpenQueued.v1') { throw 'unexpected host-open queue kind' }
if (-not $queue.confirmed) { throw 'host-open queue row must be confirmed' }
if ($queue.source.client -ne 'vim') { throw 'host-open queue row source must be vim' }

$receipt = Get-Content cache\vim-host-open.receipts.jsonl -Raw | ConvertFrom-Json
if ($receipt.kind -ne 'hq.hostPathOpenReceipt.v1') { throw 'unexpected host-open receipt kind' }
if ($receipt.status -ne 'executed') { throw 'host-open receipt must record executed status' }
if ($receipt.plan.executable -notmatch 'fake-explorer.exe$') { throw 'host-open receipt must call the explorer-compatible binary through hq' }

$fake = Get-Content cache\fake-explorer-invoked.json -Raw | ConvertFrom-Json
if ($fake.kind -ne 'fake.explorer.invoked.v1') { throw 'fake explorer was not invoked' }
if (($fake.argv | Select-Object -Last 1) -ne $target) { throw 'fake explorer did not receive the expected host path' }
