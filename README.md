# firestorm-wine-fix

This repo gets the official [Firestorm](https://firestorm-servers.com) launcher running on Linux with GE-Proton. It fixes one Wine function (`ole32!RevokeDragDrop`), which crashes the launcher right after its splash screen.

This is an unofficial fix. It is not affiliated with Firestorm, Valve, GloriousEggroll or WineHQ.

## The problem

The Firestorm launcher (v2.0.21, built with Tauri 2 and WebView2) starts under Wine/Proton and shows its splash screen. It then crashes while creating the login window:

```
page fault ... in ole32 (+0x34d7d)   <- RevokeDragDrop+0x6d in GE-Proton11-7
```

We hit this with GE-Proton11-7 and with plain Wine 11.18.

## Cause

[wry](https://github.com/tauri-apps/wry) is Tauri's webview layer. Its WebView2 drag-and-drop code (`src/webview2/drag_drop.rs`, `inject_in_hwnd`) walks every child window of the webview host. For each window it calls `RevokeDragDrop()`, and if that call does not return `DRAGDROP_E_INVALIDHWND`, it calls `RegisterDragDrop()`.

Some of those child windows belong to the `msedgewebview2.exe` process, which has registered its own drop target on them. Wine's `RevokeDragDrop()` reads that drop-target pointer from a property on the window. The pointer is only valid inside the other process, but Wine calls `IDropTarget::Release()` on it anyway, and the launcher crashes.

Wine's `RegisterDragDrop()` already refuses windows owned by another process and returns `DRAGDROP_E_INVALIDHWND`. The [patch](patches/0001-ole32-Don-t-revoke-drop-targets-on-other-processes-w.patch) adds the same check to `RevokeDragDrop()`, so it is 9 added lines.

wry's code expects `DRAGDROP_E_INVALIDHWND` for windows owned by another process, which suggests that is what Windows returns. This has not been confirmed with a test on Windows. Other Tauri + WebView2 apps may hit the same crash under Wine, but none have been tested.

## What's in this repo

| File | What it does |
| --- | --- |
| `patches/0001-…patch` | The Wine fix. |
| `build.sh` | Builds the patched 64-bit `ole32.dll` from the exact Wine source GE-Proton11-7 uses. The build is reproducible. |
| `install.sh` | Copies GE-Proton11-7 to a new runner, `GE-Proton11-7-firestorm`, and swaps in the patched DLL. The original GE-Proton11-7 is not modified. |
| [Releases](https://github.com/s1aai/firestorm-wine-fix/releases) | A prebuilt `ole32.dll` and its `SHA256SUMS`. |

## Install

You need:

- GE-Proton11-7 in `~/.local/share/Steam/compatibilitytools.d/`, installed with ProtonUp-Qt or by hand.
- [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher).

Steps:

1. Get the patched DLL. Either:
   - download `ole32.dll` and `SHA256SUMS` from [Releases](https://github.com/s1aai/firestorm-wine-fix/releases) and run `sha256sum -c SHA256SUMS`, or
   - build it yourself with `./build.sh` (see [Building](#building)).
2. Create the patched runner:
   ```sh
   ./install.sh ole32.dll       # or: ./install.sh out/ole32.dll
   ```
   This creates `~/.local/share/Steam/compatibilitytools.d/GE-Proton11-7-firestorm`.
3. Set up a Proton prefix with the Microsoft WebView2 Runtime installed, then install the Firestorm launcher into it.
4. Run the launcher with the patched runner:
   ```sh
   WINEPREFIX=~/Games/firestorm GAMEID=umu-default \
   PROTONPATH=~/.local/share/Steam/compatibilitytools.d/GE-Proton11-7-firestorm \
   umu-run ~/Games/firestorm/drive_c/users/steamuser/AppData/Local/"Firestorm Launcher"/FirestormLauncher.exe
   ```

Do **not** set `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`. The launcher passes its own Wine-specific WebView2 flags, and that variable overrides them, which sends WebView2's GPU process into a crash loop.

To undo the install, delete the `GE-Proton11-7-firestorm` folder.

## Lutris

1. Choose **Add locally installed game** and set the runner to **Wine**.
2. In **Game options**, set **Executable** to `FirestormLauncher.exe` and **Wine prefix** to your prefix.
3. In **Runner options**, set **Wine version** to `GE-Proton11-7-firestorm`. Lutris lists Proton builds from `compatibilitytools.d` and runs them through umu.

Lutris hides its own DXVK and VKD3D settings for Proton runners, because Proton ships and enables its own copies.

We also turned off **Enable D3D Extras** to keep the prefix the same as in the manual setup. This is optional.

## Tested with

- CachyOS, Hyprland, Intel Arc A580
- GE-Proton11-7, umu-launcher 1.4.3, Lutris 0.5.22
- Firestorm launcher 2.0.21, WebView2 Runtime 154.0.4258.53, prefix set to Windows 11

What works:

- logging in, including 2FA
- downloading and installing the client (The War Within)
- restoring the saved session on the next start
- starting the launcher from Lutris

## Building

`build.sh` does the following:

- fetches [ValveSoftware/wine](https://github.com/ValveSoftware/wine) at `46b29104`, the commit GE-Proton11-7's `wine` submodule points to
- applies the two ole32 patches that GE-Proton11-7 adds on top, then this repo's patch
- builds only `ole32.dll` with clang and lld

The build takes about a minute and needs network access.

You need `git curl patch make gcc clang lld autoconf flex bison perl python3`. On Arch-based distros:

```sh
sudo pacman -S --needed base-devel git curl clang lld autoconf flex bison perl python
```

The result goes to `out/ole32.dll`. The build is byte-for-byte reproducible, so your `out/SHA256SUMS` should match the one in the release.

The DLL only fits GE-Proton11-7. For another Proton version, set `WINE_COMMIT` and the GE patch URL in `build.sh` to that release's values, and update the version check in `install.sh`.

## License

LGPL-2.1-or-later, the same as Wine; see [LICENSE](LICENSE). The prebuilt DLL is built from Wine source (ValveSoftware/wine `46b29104e3741fe23bf5e2547196a253aab88c89`) plus the patches listed above.
