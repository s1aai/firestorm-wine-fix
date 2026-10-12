# Firestorm Launcher on Linux

Play on [Firestorm](https://firestorm-servers.com) on Linux using their **official launcher**.

## How to install

**Step 1.** Open a **Terminal**. Search for "Terminal" in your apps menu.

**Step 2.** Copy this line, paste it into the terminal, and press **Enter**:

```
curl -fsSL https://raw.githubusercontent.com/s1aai/firestorm-wine-fix/main/setup.sh | bash
```

> To paste into a terminal, press **Ctrl+Shift+V**. Plain Ctrl+V doesn't work there.

**Step 3.** Wait until it says **ALL DONE!** This takes about 5–10 minutes.

**Step 4.** The Firestorm launcher opens by itself. Log in, then install the game from inside the launcher.

To play later, open **Firestorm Launcher** from your apps menu.

You need about **120 GB of free disk space**. The game alone is about 115 GB.

## Already have the game files?

If someone gave you the game folder (for example, copied from a Windows PC), you can skip the big 115 GB download.

**Step 1.** Do the 4 steps in [How to install](#how-to-install) first. When the launcher opens, **close it**.

**Step 2.** Find the game folder you were given. It's the folder that has **`Wow.exe`** inside it. On Windows it is usually called **The War Within**.

**Step 3.** Open your file manager. Go to your **Home** folder, then **Games** → **firestorm** → **drive_c**.

**Step 4.** In **drive_c**, make a new folder called **`Firestorm`**. Spelling and capital F matter.

**Step 5.** Move the game folder into that **Firestorm** folder. When you're done, this file should exist:

```
~/Games/firestorm/drive_c/Firestorm/The War Within/Wow.exe
```

> Moving is instant if the game is on the same drive. Copying 115 GB can take a long time; wait until it finishes.

**Step 6.** Open **Firestorm Launcher** from your apps menu and log in. If it asks where the game is or where to install it, choose **`C:\Firestorm\The War Within`**. The launcher then checks the files and downloads only what's missing or out of date.

If it starts downloading the whole game again, stop it, look for a button like **Locate**, **Browse** or **Change folder**, and choose `C:\Firestorm\The War Within`.

## Something went wrong?

| What you see | What to do |
| --- | --- |
| `Missing program: something` | Install that program with your system's package manager, then paste the command again. |
| `Something went wrong during: ...` | Paste the command again. Steps that already finished are skipped. If it fails again, [open an issue](https://github.com/s1aai/firestorm-wine-fix/issues) and attach the file `~/.local/share/firestorm-wine-fix/setup.log`. |
| `... already exists and wasn't made by this script` | You already have a folder at `~/Games/firestorm`. Rename it to something else, then paste the command again. |
| `Don't run this with sudo` | Paste the command without `sudo` in front of it. |

## How to remove it

Paste this into a terminal. **It also deletes the game.**

```
rm -rf ~/Games/firestorm ~/.local/share/firestorm-wine-fix ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-7-firestorm ~/.local/share/applications/firestorm-launcher.desktop
```

## Is this safe?

The script never asks for your password and only changes files in your home folder. It downloads:

| What | From | Checked |
| --- | --- | --- |
| umu-launcher, which runs Proton outside Steam | GitHub (Open-Wine-Components) | checksum |
| GE-Proton11-7 | GitHub (GloriousEggroll) | checksum |
| The patched `ole32.dll` | [This repo's releases](https://github.com/s1aai/firestorm-wine-fix/releases) | checksum |
| Microsoft WebView2 Runtime | Microsoft | not checked: the link always serves Microsoft's newest version, so there's no fixed checksum |
| Firestorm launcher | Firestorm's own download server | not checked: Firestorm updates it, so there's no fixed checksum |

You can read [`setup.sh`](setup.sh) before running it.

This project is unofficial. It is not affiliated with Firestorm, Valve, GloriousEggroll or WineHQ.

## Lutris (optional)

To start the launcher from Lutris instead of the apps menu, run `setup.sh` first, then in Lutris:

1. Choose **Add locally installed game** and set the runner to **Wine**.
2. In **Game options**, set **Executable** to `~/Games/firestorm/drive_c/users/steamuser/AppData/Local/Firestorm Launcher/FirestormLauncher.exe` and **Wine prefix** to `~/Games/firestorm`.
3. In **Runner options**, set **Wine version** to `GE-Proton11-7-firestorm`.

Lutris has no DXVK or VKD3D settings for Proton runners, because Proton ships and enables its own copies.

---

## Technical details

### The problem

The Firestorm launcher (v2.0.21, built with Tauri 2 and WebView2) starts under Wine/Proton and shows its splash screen. It then crashes while creating the login window:

```
page fault ... in ole32 (+0x34d7d)   <- RevokeDragDrop+0x6d in GE-Proton11-7
```

We hit this with GE-Proton11-7 and with plain Wine 11.18.

### Cause

[wry](https://github.com/tauri-apps/wry) is Tauri's webview layer. Its WebView2 drag-and-drop code (`src/webview2/drag_drop.rs`, `inject_in_hwnd`) walks every child window of the webview host. For each window it calls `RevokeDragDrop()`, and if that call does not return `DRAGDROP_E_INVALIDHWND`, it calls `RegisterDragDrop()`.

Some of those child windows belong to the `msedgewebview2.exe` process, which has registered its own drop target on them. Wine's `RevokeDragDrop()` reads that drop-target pointer from a property on the window. The pointer is only valid inside the other process, but Wine calls `IDropTarget::Release()` on it anyway, and the launcher crashes.

Wine's `RegisterDragDrop()` already refuses windows owned by another process and returns `DRAGDROP_E_INVALIDHWND`. The [patch](patches/0001-ole32-Don-t-revoke-drop-targets-on-other-processes-w.patch) adds the same check to `RevokeDragDrop()`, so it is 9 added lines.

wry's code expects `DRAGDROP_E_INVALIDHWND` for windows owned by another process, which suggests that is what Windows returns. This has not been confirmed with a test on Windows. Other Tauri + WebView2 apps may hit the same crash under Wine, but none have been tested.

### What `setup.sh` does

1. Downloads umu-launcher 1.4.4 to `~/.local/share/firestorm-wine-fix/`.
2. Creates `~/.local/share/Steam/compatibilitytools.d/GE-Proton11-7-firestorm`. It copies your existing GE-Proton11-7 if you have one, or downloads it, then replaces `files/lib/wine/x86_64-windows/ole32.dll` with the patched DLL. The original DLL is kept as `ole32.dll.orig`. Your own GE-Proton11-7 is not modified.
3. Creates the prefix `~/Games/firestorm` and sets it to Windows 11. Set `FIRESTORM_PREFIX` to use a different folder.
4. Installs the WebView2 Runtime (`/silent /install`).
5. Installs the Firestorm launcher (`/S`).
6. Writes `~/.local/share/firestorm-wine-fix/start.sh` and an apps-menu entry, then starts the launcher.

Do **not** set `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`. The launcher passes its own Wine-specific WebView2 flags, and that variable overrides them, which sends WebView2's GPU process into a crash loop.

### Building the DLL yourself

`build.sh` does the following:

- fetches [ValveSoftware/wine](https://github.com/ValveSoftware/wine) at `46b29104`, the commit GE-Proton11-7's `wine` submodule points to
- applies the two ole32 patches that GE-Proton11-7 adds on top, then this repo's patch
- builds only `ole32.dll` with clang and lld

The build takes about a minute and needs `git curl patch make gcc clang lld autoconf flex bison perl python3`. On Arch-based distros:

```sh
sudo pacman -S --needed base-devel git curl clang lld autoconf flex bison perl python
```

The build is byte-for-byte reproducible, so `out/SHA256SUMS` should match the release.

The DLL only fits GE-Proton11-7. For another Proton version, set `WINE_COMMIT` and the GE patch URL in `build.sh` to that release's values.

### Tested with

- CachyOS, Hyprland, Intel Arc A580
- GE-Proton11-7, umu-launcher 1.4.3 and 1.4.4, Lutris 0.5.22
- Firestorm launcher 2.0.21, WebView2 Runtime 154.0.4258.53

What works:

- logging in, including 2FA
- downloading and installing the client (The War Within)
- restoring the saved session on the next start
- starting the launcher from Lutris
- running `setup.sh` from scratch

## License

LGPL-2.1-or-later, the same as Wine; see [LICENSE](LICENSE). The prebuilt DLL is built from Wine source (ValveSoftware/wine `46b29104e3741fe23bf5e2547196a253aab88c89`) plus the patches listed above.
