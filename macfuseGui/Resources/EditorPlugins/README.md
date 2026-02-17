# Built-in Editor Plugins

This folder contains bundled built-in editor plugin manifests.

Structure:
- one folder per built-in plugin
- each plugin folder contains `plugin.json`

Current built-ins:
- `vscode`
- `vscodium`
- `cursor`
- `zed`

These manifests are loaded first at runtime. If a bundled manifest is missing/invalid,
the app falls back to the hardcoded safe defaults in `EditorPluginRegistry`.
