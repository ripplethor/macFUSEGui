# Acknowledgements

This project benefits from bug reports, testing, review, and pull requests from the community.

## v0.1.36

Thanks to @Yike-Ye for PR #6, which identified and proposed fixes for:

- AppleDouble/xattr copy failures in Finder and `cp`
- trailing-slash handling for remote directory symlink mounts
- ProxyJump support for Finder mounts and Test Connection
- standard Edit menu shortcuts in the accessory app
- the macOS beta settings-window sizing issue

The final implementation was applied directly to `main` while the maintainer's MacBook was in for repair, but the investigation and proposed fixes came from that contribution.

Thanks to @timc3 for PR #4, which raised the SSH host-key verification issue in the built-in browser and source tarball checksum pinning for release builds.
