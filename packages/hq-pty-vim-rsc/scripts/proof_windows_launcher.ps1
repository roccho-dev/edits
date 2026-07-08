$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
New-Item -ItemType Directory -Force -Path cache | Out-Null
New-Item -ItemType Directory -Force -Path dist | Out-Null

go test ./...
go build -o dist/hq.exe ./cmd/hqwin
.\dist\hq.exe windows-launcher-smoke --home 'C:\Users\resta' --out cache\windows-launcher-smoke.json
.\dist\hq.exe windows-explorer-complete --home 'C:\Users\resta' --base re --out cache\windows-explorer-complete.json
.\dist\hq.exe windows-explorer-preview --home 'C:\Users\resta' --target edits --out cache\windows-explorer-preview-edits.json
.\dist\hq.exe windows-explorer-preview --select 'C:\Users\resta\Codex\repos\edits\README.md' --out cache\windows-explorer-preview-select.json

$smoke = Get-Content cache\windows-launcher-smoke.json -Raw | ConvertFrom-Json
if (-not $smoke.ok) { throw 'windows launcher smoke did not return ok=true' }
Write-Output 'WINDOWS_LAUNCHER_PROOF_OK'
