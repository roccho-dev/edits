# Windows Explorer launcher proof

Goal: make the imported hq PTY/Vim RSC payload usable from Windows without making shell the primary interface.

First workflow:

```text
Windows Terminal
  -> Herdr
    -> direct Vim process
      -> hq completion candidates
      -> explicit accept boundary
      -> explorer.exe open/select command
```

Proof command on Windows:

```powershell
./scripts/proof_windows_launcher.ps1
```

Expected:

```text
WINDOWS_LAUNCHER_PROOF_OK
```

Important boundary: completion and preview return a side-effect-free `ExplorerPlan`. Only `windows-explorer-preview --execute` starts `explorer.exe`.
