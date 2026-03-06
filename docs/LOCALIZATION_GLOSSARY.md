# Localization Glossary

## Purpose
This document defines the translation rules for `macfuseGui` so runtime UI and App Store metadata stay consistent across locales.

## Product Terms
- `macfuseGui`: never translate
- `macFUSE`: never translate
- `SSHFS`: never translate
- `Finder`: never translate
- `Keychain`: never translate
- `VS Code`: never translate
- `VSCodium`: never translate
- `Cursor`: never translate
- `Zed`: never translate

## User Data
Never translate:
- remote display names
- usernames
- hostnames / IP addresses
- file paths
- mount points
- ports
- plugin manifest ids
- plugin manifest display names from external JSON

## Tone
- Keep labels compact and technical.
- Prefer direct verbs for buttons.
- Avoid marketing language.
- Prefer operational wording over explanatory fluff.
- When space is tight, preserve the action and drop extra context.

## Formatting Rules
- Keep `%@` and `%lld` placeholders exactly intact.
- Do not reorder placeholders unless required by grammar.
- Keep slash-delimited paths untouched.
- Preserve ellipsis style already used by the source string.
- Keep `Open In` and `Open in %@` distinct.

## Menu Bar Constraints
The menu bar popover has tight width limits.
Prioritize short translations for:
- status pills
- action buttons
- recovery banners
- browser footer actions

## Browser Terms
Use these meanings consistently:
- `Remote Directory`: source path on the server
- `Local Mount Point`: local folder exposed in Finder
- `Mounted`: active resolved mount path
- `Reconnecting`: transient recovery state, not a hard failure
- `Degraded`: data is shown from cache or health is impaired

## App Store Notes
- Keep the app name branded as `macfuseGui`.
- Localize subtitle, description, keywords, release notes, and screenshot captions.
- Prefer the locale-specific App Store language listed in the metadata checklist.
