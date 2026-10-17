# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-17
### Added
- D-pad left/right switches to the previous/next owned spell while playing.
- The D-pad no longer walks (the left stick still does); toggle with `FreeDpadFromMovement`.
- One-click `Install.bat` / `Uninstall.bat` that find the game, install BepInEx 6.0.0-be.789 from a
  bundled, checksum-verified archive when it is missing, and copy the plugin.
- A second, plugin-only package for people who already use BepInEx or a mod manager.
- Config file with `Enabled`, `FreeDpadFromMovement`, `InvertDirection` and `Verbose`.
