# Centli B4-PATCH G24 notes

Baseline HEAD (before G24): `1dd14b3` · version `1.4.2+8` · schema **11** · tests **224**

## Subtask → commit

| Task | hash | Notes |
|---|---|---|
| G24.1 | (this commit) | `git rm --cached` 6 machine-generated audit_input files; keep notes.md; README wording; gitignore `!notes.md` |
| G24.2 | (same / follow-up) | commit notes.md; Final HEAD → 见 `git log -1` |
| G24.3 | (follow-up) | `test/fixtures/README.md` + `.gitattributes` binary for `*.db` |

## G24 self-prove

- `git ls-files docs/grokbot/audit_input` → only `notes.md`
- All 6 generated files still on disk after `git rm --cached`
- `tools/verify.ps1` → VERIFY: OK; corrupt HEAD.txt → AUDIT INPUT STALE exit 1; restore via re-run

## Gate

### analyze / test
Deferred to verify script; version stay **1.4.2+8** (G24.5: no bump)

## Risks / scope

- Version **not** bumped
- No APK / no push / no amend
- Never touched `docs/grokbot/audit_report_*.md`
- Used only `git rm --cached` (files kept on disk)

## Final
- Final HEAD: 见 `git log -1`
- version: **1.4.2+8** · schema **11** · tests **224**
