# Third-party notices

## BepInEx
The release zip bundles an **unmodified** BepInEx build so that you do not have to install the mod loader yourself:

* `BepInEx-Unity.IL2CPP-win-x64-6.0.0-be.789+6cea286.zip` (renamed `BepInEx-be.789.zip`)
* Source and licenses: <https://github.com/BepInEx/BepInEx> (the loader is LGPL-2.1; it ships with and depends on
  other open-source components such as Harmony, MonoMod, Cpp2IL, Il2CppInterop and the .NET runtime, each under its own license - see the BepInEx project for details)
* Official build: <https://builds.bepinex.dev/projects/bepinex_be>
* SHA-256 of the bundled archive: `29519614d0121a3eefc9df6d61436f0c09a2c5f85b0a7d92559a135ce3055eb1`

## Game
"Castlevania: Belmont's Curse" is a product of Konami and its developers. This project is not affiliated with
or endorsed by them. No game code or assets are included here: the plugin is compiled against interop assemblies
that BepInEx generates on your own machine from your own copy of the game, and those are never redistributed.

## Button icons (README graphic)
The controller button icons in `docs/controls.png` come from **Kenney Input Prompts** by Kenney (<https://www.kenney.nl>),
released under **CC0 1.0** (public domain): <https://kenney.nl/assets/input-prompts>. They are used only in the README image and are not part of the mod.
