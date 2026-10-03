#!/usr/bin/env bash
# Make a patched copy of GE-Proton11-7 called GE-Proton11-7-firestorm.
# The original GE-Proton11-7 is left untouched.
#
# Usage: ./install.sh path/to/ole32.dll
# COMPAT_DIR overrides the compatibility tools directory.
set -euo pipefail

dll=${1:?usage: $0 path/to/ole32.dll}
compat=${COMPAT_DIR:-$HOME/.local/share/Steam/compatibilitytools.d}
dest=$compat/GE-Proton11-7-firestorm

for name in GE-Proton11-7-x86_64 GE-Proton11-7; do
    [ -f "$compat/$name/proton" ] && { src=$compat/$name; break; }
done
[ -n "${src:-}" ] || { echo "GE-Proton11-7 not found in $compat" >&2; exit 1; }

# The DLL is built from GE-Proton11-7's Wine source and only fits that release.
grep -qw 'GE-Proton11-7' "$src/version" || { echo "$src is not GE-Proton11-7" >&2; exit 1; }
[ ! -e "$dest" ] || { echo "$dest already exists; remove it first" >&2; exit 1; }

echo "copying $src -> $dest"
cp -a "$src" "$dest"

name=$(basename "$src")
sed -i "s|\"$name\" // Internal name|\"GE-Proton11-7-firestorm\" // Internal name|; \
        s|\"display_name\" \"[^\"]*\"|\"display_name\" \"GE-Proton11-7-firestorm (ole32 RevokeDragDrop fix)\"|" \
    "$dest/compatibilitytool.vdf"

lib=$dest/files/lib/wine/x86_64-windows
cp -a "$lib/ole32.dll" "$lib/ole32.dll.orig"
install -m 555 "$dll" "$lib/ole32.dll"

echo "installed; original ole32.dll kept as $lib/ole32.dll.orig"
