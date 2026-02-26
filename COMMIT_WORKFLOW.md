# Commit and Push Workflow

When asked to "commit and push" changes in this project, follow this process exactly.
The release script reads git commit subjects to build the GitHub release changelog, so
message format matters.

---

## 1. Run the reliability gate first

Before committing, always verify the build is clean:

```bash
python3 scripts/audit_mount_calls.py && \
  xcodebuild -project macfuseGui.xcodeproj \
    -scheme macfuseGui \
    -configuration Debug \
    -derivedDataPath build/DerivedData \
    -destination 'platform=macOS,arch=arm64' \
    test CODE_SIGNING_ALLOWED=NO
```

All tests must pass and the audit must print `PASS` before you commit.

---

## 2. How the release changelog works

`scripts/release.sh` generates release notes by reading `git log` subjects since the
last `vX.Y.Z` tag. Each commit subject is transformed and bucketed:

| Prefix in subject | Displayed as | Section |
|---|---|---|
| `fix:` | `Fix: <message>` | ### Fixes |
| `feat:` | `New: <message>` | ### Other Changes |
| `perf:` | `Performance: <message>` | ### Other Changes |
| `refactor:` | `Refactor: <message>` | ### Other Changes |
| `chore:` / `build:` / `ci:` / `style:` / `test:` | `Maintenance: <message>` | ### Other Changes |
| `docs:` | `Docs: <message>` | ### Other Changes |
| (no prefix) | shown as-is | ### Other Changes |

**Commits are excluded from the changelog if every changed file matches:**
```
^docs/  |  \.html$  |  ^scripts/.*\.sh$  |  ^macfuseGuiTests?/  |  ^macfuseGuiTest/
```
(case-insensitive). A commit that touches both a production file and a test file is
**included** because it has at least one non-ignored path.

**Release commits** (`Release vX.Y.Z`) are always excluded.

---

## 3. Commit message format

Use conventional commit format. The subject becomes the changelog bullet. The body
explains the *why* for engineers reading `git log`.

```
fix: concise description of what was wrong and what was fixed

Paragraph explaining the root cause and the concrete failure scenario.
Second paragraph if needed for additional context or edge cases.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Rules:
- Subject line: imperative mood, ≤ 72 characters, no trailing period
- Blank line between subject and body
- Body: explain *why* the change was needed, not *what* lines changed
- Always append the `Co-Authored-By` trailer

---

## 4. How to group changes into commits

**One logical fix or feature per commit.** Group all files that belong to the same
change together. Do not batch unrelated changes into one commit.

Example groupings from a four-bug session:
```
Commit 1  macfuseGui/Services/KeychainService.swift
          macfuseGuiTests/KeychainServiceTests.swift

Commit 2  macfuseGui/Services/MountStateParser.swift
          macfuseGui/Services/UnmountService.swift

Commit 3  macfuseGui/Services/MountCommandBuilder.swift
          macfuseGui/Services/MountManager.swift
          macfuseGuiTests/MountArgBuilderTests.swift

Commit 4  macfuseGui/ViewModels/RemotesViewModel.swift
```

**When one file contains changes from two different bugs:** keep that file in the commit
for the more important fix rather than using interactive patch splitting. Note in both
commit bodies that the file also carries the other change.

Use explicit `git add <file> [file ...]` — never `git add .` or `git add -A`.

---

## 5. Making each commit

```bash
git add macfuseGui/Services/KeychainService.swift macfuseGuiTests/KeychainServiceTests.swift
git commit -m "$(cat <<'EOF'
fix: return trimmed password from KeychainService to prevent whitespace auth failures

readPassword returned the raw stored value even after trimming it to check for
blank-only passwords. A password pasted with a trailing newline was returned
with that whitespace intact, causing silent SSH authentication failures.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

Use a HEREDOC for the message to avoid quoting issues with apostrophes or special chars.

---

## 6. Push

After all commits are made:

```bash
git push origin main
```

No force push. No `--no-verify`. If the push is rejected, investigate — do not override.

---

## 7. What goes in Fixes vs Other Changes

- **Bug fixes** → `fix:` prefix → appears under **### Fixes** in the release notes
- **New behaviour, improvements** → `feat:`, `perf:`, or bare subject → **### Other Changes**
- **Test-only changes** → use `test:` prefix; will be filtered out of the changelog entirely
- **Internal cleanup with no user-visible effect** → `refactor:` or `chore:`

When in doubt about whether something is user-facing, use `fix:` or `feat:` so it
appears in the changelog. Changelog readers are end users checking what changed.

---

## 8. Quick checklist

1. [ ] Reliability gate passes (audit + tests)
2. [ ] Changes grouped into one commit per logical fix/feature
3. [ ] Each commit uses `fix:` or appropriate prefix
4. [ ] Subject line is ≤ 72 chars and describes the user-visible problem, not the code
5. [ ] Body explains root cause and failure scenario
6. [ ] `Co-Authored-By` trailer present
7. [ ] `git add` lists explicit files only
8. [ ] `git push origin main` — clean, no force
