New-Item -ItemType Directory -Force -Path cache | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue cache\windows-launcher-smoke.json

go build -o dist/hq.exe ./cmd/hqwin
.\dist\hq.exe windows-launcher-smoke --home 'C:\Users\resta' --out cache\windows-launcher-smoke.json

$smoke = Get-Content cache\windows-launcher-smoke.json -Raw | ConvertFrom-Json
if (-not $smoke.ok) { throw 'windows launcher retired smoke did not return ok=true' }
if (-not $smoke.direct_explorer_side_retired) { throw 'direct explorer side was not marked retired' }
if (-not $smoke.side_effect_free) { throw 'retired launcher smoke must be side-effect free' }
if (-not $smoke.requires_hq_semantic_intent) { throw 'host path opening must require hq semantic intent' }
