#!/usr/bin/env bash
# Build the patched 64-bit ole32.dll for GE-Proton11-7.
#
# Uses the exact Wine source GE-Proton11-7 was built from (ValveSoftware/wine
# at the commit pinned by its "wine" submodule), applies the two ole32 patches
# GE adds on top, then this repo's fix. Only ole32.dll and the build tools it
# needs are compiled, not all of Wine. Needs network access (git, curl and
# Wine's make_vulkan, which downloads vk.xml).
#
# Output: out/ole32.dll and out/SHA256SUMS
set -euo pipefail

WINE_REPO=https://github.com/ValveSoftware/wine
WINE_COMMIT=46b29104e3741fe23bf5e2547196a253aab88c89  # "wine" submodule of GE-Proton11-7
GE_PATCHES=https://raw.githubusercontent.com/GloriousEggroll/proton-ge-custom/GE-Proton11-7/patches/wine-hotfixes/pending

here=$(cd "$(dirname "$0")" && pwd)
work=$here/work
out=$here/out

for tool in git curl patch make gcc clang lld-link autoreconf flex bison perl python3; do
    command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 1; }
done

mkdir -p "$work" "$out"
cd "$work"

if [ ! -f wine/configure ]; then
    rm -rf wine
    git init -q wine
    git -C wine fetch -q --depth 1 "$WINE_REPO" "$WINE_COMMIT"
    git -C wine checkout -q FETCH_HEAD
    cd wine
    for p in ole32-clipboard-stale-handle-1-tests ole32-clipboard-stale-handle-2-fix; do
        curl -fsSL "$GE_PATCHES/$p.patch" | patch -Np1
    done
    patch -Np1 < "$here"/patches/0001-ole32-Don-t-revoke-drop-targets-on-other-processes-w.patch
    tools/make_requests
    tools/make_specfiles
    dlls/winevulkan/make_vulkan -x vk.xml -X video.xml
    autoreconf -if
    cd ..
fi

mkdir -p build
cd build
if [ ! -f Makefile ]; then
    # Only the PE side matters; turn off every optional Unix library.
    # CROSSCFLAGS without -g keeps build paths out of the DLL; -Brepro replaces
    # the link timestamp with a hash so the build is byte-for-byte reproducible.
    ../wine/configure --enable-win64 --enable-archs=x86_64 --disable-tests \
        CROSSCFLAGS="-O2" CROSSLDFLAGS="-Wl,-Brepro" \
        --without-x --without-wayland --without-freetype --without-vulkan --without-opengl \
        --without-gstreamer --without-ffmpeg --without-alsa --without-pulse --without-oss \
        --without-cups --without-sane --without-gphoto --without-pcap --without-usb \
        --without-v4l2 --without-krb5 --without-gssapi --without-netapi --without-capi \
        --without-dbus --without-sdl --without-udev --without-unwind --without-inotify \
        --without-xinerama --without-fontconfig --without-gnutls --without-pcsclite \
        > configure.log
fi
make -j"$(nproc)" dlls/ole32/x86_64-windows/ole32.dll

cp dlls/ole32/x86_64-windows/ole32.dll "$out"/ole32.dll
cd "$out"
sha256sum ole32.dll > SHA256SUMS
cat SHA256SUMS
