# App Store Localization Checklist

## Primary Locale
- `en-US`

## Wave 1 Locales
- `zh-Hans`
- `ja`
- `de-DE`
- `fr-FR`
- `pt-BR`
- `es-MX`
- `ko`

## Metadata To Localize
- app subtitle
- app description
- keywords
- promo text
- release notes
- screenshot captions
- support URL copy if localized externally

## Brand Rules
- Keep `macfuseGui` unchanged.
- Keep `macFUSE`, `SSHFS`, `Finder`, `Keychain`, and editor brand names unchanged.

## Operational Steps
1. Prepare English source metadata.
2. Adapt keywords per locale instead of translating literally.
3. Export screenshots with localized captions where needed.
4. Verify App Store Connect locale mapping before submission.
5. Check search term coverage for `sshfs`, `macfuse`, `mount`, and `menu bar` variants per locale.

## QA
- title and subtitle fit on store pages
- keywords are locale-appropriate
- screenshots match translated UI terms
- release notes are localized for each submitted locale
