#!/usr/bin/env bash
# One-command setup for the official Firestorm launcher on Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/s1aai/firestorm-wine-fix/main/setup.sh | bash
#
# Steps (each one is skipped if it is already done, so running it again is safe):
#   1. download umu-launcher (runs Proton outside Steam)
#   2. make GE-Proton11-7-firestorm: GE-Proton11-7 with the patched ole32.dll
#   3. create the Wine prefix ~/Games/firestorm, set to Windows 11
#   4. install the Microsoft WebView2 Runtime into it
#   5. install the Firestorm launcher into it
#   6. add "Firestorm Launcher" to the apps menu, then start it
#
# FIRESTORM_PREFIX=/some/dir changes where the prefix goes.

main() {
set -Eeuo pipefail

UMU_URL=https://github.com/Open-Wine-Components/umu-launcher/releases/download/1.4.4/umu-launcher-1.4.4-zipapp.tar
UMU_SHA256=eb590691841f7fad3fc3ad8fd5db4ccb87849fe7948e62b28ece7a4ee48cc851
GE_URL=https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton11-7/GE-Proton11-7-x86_64.tar.gz
GE_SHA512=7db87e9787e20c35cbdac26018431d5794626b626e4067b050684e45a88cc2ca229d7d263519eafb2e168cde5bef57611065d159d3685aaec152ccb9abe3073f
DLL_URL=https://github.com/s1aai/firestorm-wine-fix/releases/download/v1.0.0/ole32.dll
DLL_SHA256=a8477943f5cfaa2fdd939d1938d474e1cb637722b875a679c407e40a9243dfc3
WEBVIEW2_URL='https://go.microsoft.com/fwlink/?linkid=2124701'
LAUNCHER_URL='https://app-cdn.firestorm-servers.com/launcher-tauri/Firestorm%20Launcher%20Setup.exe'
ICON_URL=https://firestorm-servers.com/assets/img/favicon/android-icon-192x192.png

app=$HOME/.local/share/firestorm-wine-fix
compat=$HOME/.local/share/Steam/compatibilitytools.d
proton=$compat/GE-Proton11-7-firestorm
prefix=${FIRESTORM_PREFIX:-$HOME/Games/firestorm}
umu=$app/umu-run
dll=$proton/files/lib/wine/x86_64-windows/ole32.dll
launcher="$prefix/drive_c/users/steamuser/AppData/Local/Firestorm Launcher/FirestormLauncher.exe"
log=$app/setup.log

step=""
trap 'echo; echo "!!! Something went wrong during: $step"; echo "!!! Details are in $log"; echo "!!! You can run the same command again; finished steps are skipped."' ERR

say() { step=$1; echo; echo "==> $1"; }
fetch() { curl -fL --retry 3 --progress-bar -o "$2" "$1"; }
check() { echo "$2  $3" | "$1" -c --quiet - >>"$log" 2>&1 || { echo "Download is damaged: $3"; rm -f "$3"; false; }; }
in_prefix() {
    WINEPREFIX=$prefix GAMEID=umu-default PROTONPATH=$proton \
        timeout "$1" "$umu" "${@:2}" </dev/null >>"$log" 2>&1
}
webview2_installed() {
    compgen -G "$prefix/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/*/msedgewebview2.exe" >/dev/null
}

say "Checking your system"
[ "$(id -u)" -ne 0 ] || { echo "Don't run this with sudo. Run it as your normal user."; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "This only works on 64-bit PCs (x86_64)."; exit 1; }
for tool in curl tar sha256sum sha512sum python3 timeout; do
    command -v "$tool" >/dev/null || { echo "Missing program: $tool. Install it with your package manager and run this again."; exit 1; }
done
python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' || { echo "Python 3.10 or newer is needed."; exit 1; }
if [ -e "$prefix" ] && ! grep -qs GE-Proton "$prefix/version"; then
    echo "$prefix already exists and wasn't made by this script."
    echo "Move or rename it, then run this again."
    exit 1
fi
mkdir -p "$app/downloads" "$compat" "$(dirname "$prefix")"
echo "--- setup started $(date)" >>"$log"
free_gb=$(df -P -BG "$(dirname "$prefix")" | awk 'NR==2 {print int($4)}')
[ "$free_gb" -ge 5 ] || { echo "Only ${free_gb} GB free. Setup needs about 5 GB."; exit 1; }
[ "$free_gb" -ge 120 ] || echo "Note: only ${free_gb} GB free. Setup fits, but the game itself needs about 115 GB."

say "1/6 Getting umu-launcher"
if [ ! -x "$umu" ]; then
    fetch "$UMU_URL" "$app/downloads/umu.tar"
    check sha256sum "$UMU_SHA256" "$app/downloads/umu.tar"
    tar -xOf "$app/downloads/umu.tar" umu/umu-run >"$umu"
    chmod +x "$umu"
    rm -f "$app/downloads/umu.tar"
fi

say "2/6 Making the patched Proton (GE-Proton11-7-firestorm)"
if [ ! -f "$proton/proton" ]; then
    rm -rf "$compat/.firestorm-tmp"
    mkdir -p "$compat/.firestorm-tmp"
    if [ -f "$compat/GE-Proton11-7-x86_64/proton" ]; then
        cp -a "$compat/GE-Proton11-7-x86_64" "$compat/.firestorm-tmp/"
    elif [ -f "$compat/GE-Proton11-7/proton" ]; then
        cp -a "$compat/GE-Proton11-7" "$compat/.firestorm-tmp/"
    else
        echo "Downloading GE-Proton11-7 (about 560 MB)..."
        fetch "$GE_URL" "$app/downloads/ge-proton.tar.gz"
        check sha512sum "$GE_SHA512" "$app/downloads/ge-proton.tar.gz"
        echo "Unpacking..."
        tar -xzf "$app/downloads/ge-proton.tar.gz" -C "$compat/.firestorm-tmp"
        rm -f "$app/downloads/ge-proton.tar.gz"
    fi
    mv "$compat/.firestorm-tmp"/GE-Proton11-7* "$proton"
    rmdir "$compat/.firestorm-tmp"
    sed -i 's|^\(\s*\)"GE-Proton11-7[^"]*" // Internal name|\1"GE-Proton11-7-firestorm" // Internal name|; s|"display_name" "[^"]*"|"display_name" "GE-Proton11-7-firestorm (ole32 RevokeDragDrop fix)"|' \
        "$proton/compatibilitytool.vdf"
    cp -a "$dll" "$dll.orig"
fi
if ! echo "$DLL_SHA256  $dll" | sha256sum -c --quiet - >/dev/null 2>&1; then
    fetch "$DLL_URL" "$app/downloads/ole32.dll"
    check sha256sum "$DLL_SHA256" "$app/downloads/ole32.dll"
    install -m 555 "$app/downloads/ole32.dll" "$dll"
    rm -f "$app/downloads/ole32.dll"
fi

say "3/6 Creating the Windows environment in $prefix"
if [ ! -f "$prefix/system.reg" ]; then
    echo "The first time, this also downloads the Steam Linux Runtime and can take a few minutes..."
    in_prefix 1800 winecfg /v win11
fi

say "4/6 Installing Microsoft WebView2 (needed by the launcher)"
if ! webview2_installed; then
    echo "Downloading WebView2 (about 200 MB)..."
    fetch "$WEBVIEW2_URL" "$app/downloads/webview2.exe"
    echo "Installing (takes a minute or two, nothing will show on screen)..."
    in_prefix 900 "$app/downloads/webview2.exe" /silent /install || true
    in_prefix 120 wineboot -k || true  # stop Edge's updater if it is still running
    webview2_installed || { echo "WebView2 did not install."; false; }
    rm -f "$app/downloads/webview2.exe"
fi

say "5/6 Installing the Firestorm launcher"
if [ ! -f "$launcher" ]; then
    fetch "$LAUNCHER_URL" "$app/downloads/firestorm-setup.exe"
    in_prefix 600 "$app/downloads/firestorm-setup.exe" /S
    [ -f "$launcher" ] || { echo "The launcher did not install."; false; }
    rm -f "$app/downloads/firestorm-setup.exe"
fi

say "6/6 Adding Firestorm Launcher to your apps menu"
cat >"$app/start.sh" <<EOF
#!/usr/bin/env bash
# Starts the Firestorm launcher. Made by firestorm-wine-fix/setup.sh.
export WINEPREFIX=$(printf %q "$prefix") GAMEID=umu-default PROTONPATH=$(printf %q "$proton")
exec $(printf %q "$umu") $(printf %q "$launcher") "\$@"
EOF
chmod +x "$app/start.sh"
curl -fsL -o "$app/firestorm.png" "$ICON_URL" || true
mkdir -p "$HOME/.local/share/applications"
cat >"$HOME/.local/share/applications/firestorm-launcher.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Firestorm Launcher
Comment=Firestorm WoW launcher (runs with GE-Proton)
Exec="$app/start.sh"
Icon=$app/firestorm.png
Terminal=false
Categories=Game;
EOF
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

trap - ERR
echo
echo "=============================================================="
echo " ALL DONE!"
echo
echo " The Firestorm launcher is starting now."
echo " Next time, open \"Firestorm Launcher\" from your apps menu."
echo
echo " Log in, then install the game from inside the launcher."
echo " The game needs about 115 GB of free disk space."
echo "=============================================================="
setsid -f "$app/start.sh" >/dev/null 2>&1 </dev/null
}

main "$@"
