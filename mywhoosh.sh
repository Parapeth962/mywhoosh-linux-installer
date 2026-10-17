#!/usr/bin/env bash
# MyWhoosh on Linux, reproducibly: a dedicated Proton prefix with pinned Proton and umu builds.
# OsmolControl owns the trainer and the controller natively over BlueZ. MyWhoosh sees
# OsmolControl as a Bluetooth trainer through ble-bridge.py and never touches the adapter.
# Most people should run install.sh, which installs system packages and asks questions.
#
#   mywhoosh.sh install [--hd] [--dircon[=HOST:PORT]] [--from <dir|msix>]
#                                                    Proton, umu, game, shim, prefix, shortcuts
#   mywhoosh.sh run                                  update if needed, start OsmolControl+MyWhoosh
#   mywhoosh.sh update                               install a newer MyWhoosh if there is one
#   mywhoosh.sh doctor                               check the installation
#   mywhoosh.sh reset-prefix                         recreate the prefix, keep the game files
#   mywhoosh.sh uninstall                            remove the installation and its shortcuts
# --hd selects MyWhoosh HD; the installed copy in <root>/bin remembers its edition.
#
# Bluetooth modes (remembered in <root>/bluetooth):
#   direct  MyWhoosh scans and pairs trainers, sensors and controllers itself through BlueZ
#           (the shim's blehelper.py). The default.
#   dircon  A DirCon virtual trainer on this PC (OsmolControl, qdomyos-zwift, ...) owns the
#           hardware; ble-bridge.py shows it to MyWhoosh as one Bluetooth device. OsmolControl,
#           if installed in ~/.local/bin, is started with the game.
#
# Why not LAN: MyWhoosh finds LAN (DirCon) trainers through Bonjour COM events, which wine-mono
# does not implement; once Bonjour is installed in the prefix every start crashes in
# OBM_Initialize. The bundled Bonjour installer is therefore disabled after every download.
#
# Bluetooth instead: MyWhoosh's .NET Bluetooth module needs the WinRT assembly "Windows", which
# Wine lacks. The "bleshim" from github.com/Dj0ulo/mywhoosh-linux supplies it and forwards GATT
# calls to 127.0.0.1:27019, answered by blehelper.py (direct) or ble-bridge.py (dircon).
#
# Updates: MyWhoosh ships new versions through the Microsoft Store, which does not exist here.
# run compares the installed version with the Store's and installs a newer one before starting
# (into game.new, swapped in only when complete); the prefix and the login are kept.
set -euo pipefail

HERE="$(dirname "$(realpath "$0")")"
EDITION=standard
INSTALLED_ROOT=""
# The installed copy lives in <root>/bin next to <root>/edition.
if [[ -f "$HERE/../edition" ]]; then
    INSTALLED_ROOT="$(dirname "$HERE")"
    EDITION="$(<"$INSTALLED_ROOT/edition")"
fi
for arg in "$@"; do
    [[ "$arg" == "--hd" ]] && EDITION=hd
done
case "$EDITION" in
    standard) PRODUCT_ID="9ndh0f2vhzx2"; TITLE="MyWhoosh"; SLUG="mywhoosh-linux" ;;
    hd) PRODUCT_ID="9nvdcph3xdz2"; TITLE="MyWhoosh HD"; SLUG="mywhoosh-hd-linux" ;;
    *) echo "unknown edition $EDITION" >&2; exit 1 ;;
esac

ROOT="${MYWHOOSH_ROOT:-${INSTALLED_ROOT:-$HOME/Games/$SLUG}}"
GAME="$ROOT/game"
PFX="$ROOT/pfx"
LOGS="$ROOT/logs"
WINRT="$ROOT/winrt"
CACHE="$ROOT/cache"
BIN="$ROOT/bin"
EXE_REL="MyWhoosh/Binaries/Win64/MyWhoosh-Win64-Shipping.exe"
EXE="$GAME/$EXE_REL"
WINRT_DLLS=(Windows.dll System.Runtime.WindowsRuntime.dll MyWhooshShim.dll)
APPS="${MYWHOOSH_APPS:-$HOME/.local/share/applications}"
OSMOL="$HOME/.local/bin/osmolcontrol"

# Pinned downloads. Bump deliberately, after a test ride.
PROTON_NAME="${MYWHOOSH_PROTON:-GE-Proton11-9}"
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/$PROTON_NAME-x86_64"
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$PROTON_NAME/$PROTON_NAME-x86_64"
UMU_URL="https://github.com/Open-Wine-Components/umu-launcher/releases/download/1.4.4/umu-launcher-1.4.4-zipapp.tar"
UMU_SHA256="eb590691841f7fad3fc3ad8fd5db4ccb87849fe7948e62b28ece7a4ee48cc851"
UMU="$ROOT/umu/umu-run"
SHIM_URL="https://github.com/Dj0ulo/mywhoosh-linux/releases/download/v0.1.3/mywhoosh-bleshim-v0.1.3.tar.gz"
SHIM_SHA256="c79487e9baea2e7a770a7f878a788ae01c6977cd1ab382ce122bdd8e17cdabed"
# Fetches the game package from Microsoft's Store servers (MIT, reviewed at this commit). It
# skips TLS certificate checks; files are checked against Microsoft's SHA-256 digests and the
# package carries Microsoft's signature.
STORE_DL_URL="https://raw.githubusercontent.com/Dj0ulo/ms-store-download/e74e26a894e0338b75803ad31ea86fc41e84d3f1/ms_store_download.py"
STORE_DL_SHA256="a528d2dbf25d3f635e9c62df59a92419fddf77329bd344106b3cf4a19fbc5224"
STORE_DL="$CACHE/ms_store_download.py"

say() { printf '[mywhoosh] %s\n' "$*" >&2; }
die() { say "error: $*"; notify "$TITLE: $*"; exit 1; }
# Desktop notification: launched from a menu there is no terminal to read.
notify() { command -v notify-send >/dev/null && notify-send -a "$TITLE" "$TITLE" "$*" 2>/dev/null || true; }

# Download $1 to $2 unless it is already there with SHA-256 $3.
fetch() {
    local url="$1" dest="$2" sha="$3"
    if [[ -f "$dest" ]] && echo "$sha  $dest" | sha256sum -c --quiet 2>/dev/null; then
        return
    fi
    say "downloading $(basename "$dest")"
    curl -fsSL --retry 3 -o "$dest.part" "$url" || die "download failed: $url"
    echo "$sha  $dest.part" | sha256sum -c --quiet || die "checksum mismatch: $url"
    mv "$dest.part" "$dest"
}

need() {
    local missing=() tool
    for tool in curl python3 tar sha256sum sha512sum; do
        command -v "$tool" >/dev/null || missing+=("$tool")
    done
    ((${#missing[@]} == 0)) || die "missing programs: ${missing[*]} (run install.sh, it installs them)"
}

proton_env() {
    [[ -x "$PROTON_DIR/proton" ]] || die "Proton $PROTON_NAME missing; run: $0 install"
    [[ -x "$UMU" ]] || die "umu missing; run: $0 install"
    export WINEPREFIX="$PFX" PROTONPATH="$PROTON_DIR" GAMEID="umu-mywhoosh" STORE="none"
    # wine-mono searches this Windows path for assemblies the game references.
    export MONO_PATH="Z:$WINRT"
}

# A wineserver left over from a crashed session keeps the prefix locked; the next start then
# exits after a few seconds without a window.
stop_stale() {
    if [[ -d "$PFX" && -x "$PROTON_DIR/files/bin/wineserver" ]]; then
        WINEPREFIX="$PFX" "$PROTON_DIR/files/bin/wineserver" -k 2>/dev/null || true
    fi
}

install_proton() {
    [[ -x "$PROTON_DIR/proton" ]] && { say "Proton $PROTON_NAME already installed"; return; }
    local tarball="$CACHE/$PROTON_NAME-x86_64.tar.gz"
    say "downloading $PROTON_NAME (about 560 MB)"
    curl -fL --retry 3 -o "$CACHE/$PROTON_NAME.sha512sum" "$PROTON_URL.sha512sum"
    curl -fL --retry 3 -C - -o "$tarball" "$PROTON_URL.tar.gz"
    (cd "$CACHE" && sha512sum -c --quiet "$PROTON_NAME.sha512sum") || die "Proton checksum mismatch"
    mkdir -p "$(dirname "$PROTON_DIR")"
    tar -xzf "$tarball" -C "$(dirname "$PROTON_DIR")"
    [[ -x "$PROTON_DIR/proton" ]] || die "Proton archive did not unpack to $PROTON_DIR"
    rm -f "$tarball"
}

# umu runs Proton inside the Steam runtime. The pinned zipapp needs only python3, so every
# distribution gets the same launcher.
install_umu() {
    local tarball="$CACHE/umu.tar"
    fetch "$UMU_URL" "$tarball" "$UMU_SHA256"
    rm -rf "$ROOT/umu.new" && mkdir -p "$ROOT/umu.new"
    tar -xf "$tarball" -C "$ROOT/umu.new"
    local run
    run="$(find "$ROOT/umu.new" -name umu-run -type f | head -n 1)"
    [[ -n "$run" ]] || die "umu archive lacks umu-run"
    rm -rf "$ROOT/umu" && mkdir -p "$ROOT/umu"
    mv "$run" "$UMU" && chmod +x "$UMU"
    rm -rf "$ROOT/umu.new"
}

install_shim() {
    local tarball="$CACHE/bleshim.tar.gz" unpacked="$CACHE/bleshim"
    fetch "$SHIM_URL" "$tarball" "$SHIM_SHA256"
    rm -rf "$unpacked" && mkdir -p "$unpacked" "$WINRT"
    tar -xzf "$tarball" -C "$unpacked"
    local dll found
    for dll in "${WINRT_DLLS[@]}" blehelper.py; do
        found="$(find "$unpacked" -name "$dll" | head -n 1)"
        [[ -n "$found" ]] || die "shim archive lacks $dll"
        cp "$found" "$WINRT/"
    done
}

installed_version() {
    grep -oE 'Identity[^>]*Version="[0-9.]+"' "$GAME/AppxManifest.xml" 2>/dev/null \
        | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1 || true
}

# Version of the main x64 package the Store offers now, e.g. 6.2.3.0.
store_version() {
    fetch "$STORE_DL_URL" "$STORE_DL" "$STORE_DL_SHA256"
    timeout 90 python3 -I "$STORE_DL" "$PRODUCT_ID" 2>/dev/null \
        | grep -oE 'FileName:.*_([0-9]+\.){3}[0-9]+_x64' | grep -oE '([0-9]+\.){3}[0-9]+' | head -n 1
}

# Make an unpacked Store package runnable under Proton.
prepare_game() {
    local dir="$1" win64="$1/MyWhoosh/Binaries/Win64"
    # The package names the game binary MyWhoosh.exe; the root launcher starts it as
    # MyWhoosh-Win64-Shipping.exe.
    if [[ ! -f "$dir/$EXE_REL" && -f "$win64/MyWhoosh.exe" ]]; then
        mv "$win64/MyWhoosh.exe" "$dir/$EXE_REL"
    fi
    [[ -f "$dir/$EXE_REL" ]] || die "no $EXE_REL after unpacking; is this the $TITLE package?"
    local bonjour
    bonjour="$(find "$dir" -iname bonjoursdksetup.exe | head -n 1)"
    if [[ -n "$bonjour" ]]; then
        mv "$bonjour" "$bonjour.disabled"
    fi
}

# Download the current Store package into $1.
download_game() {
    local dest="$1"
    fetch "$STORE_DL_URL" "$STORE_DL" "$STORE_DL_SHA256"
    rm -rf "$dest" && mkdir -p "$dest"
    python3 -I "$STORE_DL" "$PRODUCT_ID" --download "$CACHE/store" --extract "$dest" --extract-flat \
        || { rm -rf "$dest" "$CACHE/store"; die "game download failed (network?)"; }
    rm -rf "$CACHE/store"
    prepare_game "$dest"
}

install_game() {
    local src="${1:-}"
    if [[ -z "$src" ]]; then
        local size="about 4 GB"
        [[ "$EDITION" == hd ]] && size="about 15 GB"
        say "downloading $TITLE from Microsoft's Store servers ($size, this takes a while)"
        download_game "$GAME"
    elif [[ -d "$src" ]]; then
        say "copying game files from $src"
        cp -a --reflink=auto "$src" "$GAME"
        prepare_game "$GAME"
    elif [[ -f "$src" ]]; then
        say "unpacking $src"
        mkdir -p "$GAME"
        python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
            "$src" "$GAME"
        prepare_game "$GAME"
    else
        die "$src not found"
    fi
    say "$TITLE $(installed_version) installed"
}

cmd_update() {
    local have want
    have="$(installed_version)"
    want="$(store_version || true)"
    if [[ -z "$want" ]]; then
        say "could not check for updates (offline?); keeping $have"
        return 0
    fi
    if [[ "$(printf '%s\n%s\n' "$have" "$want" | sort -V | tail -n 1)" == "$have" ]]; then
        say "$TITLE $have is up to date"
        return 0
    fi
    say "updating $TITLE $have -> $want"
    notify "Updating to $want. This downloads several GB; the game starts when it is done."
    download_game "$GAME.new"
    rm -rf "$GAME.old"
    mv "$GAME" "$GAME.old" && mv "$GAME.new" "$GAME"
    rm -rf "$GAME.old"
    say "$TITLE updated to $(installed_version)"
    notify "Updated to $(installed_version)."
}

desktop_entry() {
    local file="$1" name="$2" comment="$3" exec="$4" icon="$5" categories="$6"
    cat >"$file" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=$comment
Exec=$exec
Icon=$icon
Categories=$categories
Terminal=false
EOF
    chmod +x "$file"
}

desktop_dir() {
    local dir
    dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    [[ -n "$dir" && "$dir" != "$HOME" ]] || dir="$HOME/Desktop"
    echo "$dir"
}

# Menu entries everywhere; desktop icons where the desktop shows them (not GNOME).
install_shortcuts() {
    mkdir -p "$APPS"
    local game_entry="$APPS/$SLUG.desktop" osmol_entry="$APPS/osmolcontrol.desktop"
    desktop_entry "$game_entry" "$TITLE" "Indoor cycling (MyWhoosh under Proton)" "\"$BIN/mywhoosh.sh\" run" \
        "$GAME/Assets/MYWHOOSH-Square150x150Logo.png" "Game;"
    if [[ -x "$OSMOL" ]]; then
        desktop_entry "$osmol_entry" "OsmolControl" "Trainer and controller bridge with virtual shifting" \
            "\"$OSMOL\"" "input-gaming" "Utility;"
    fi
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true
    local session="${XDG_CURRENT_DESKTOP:-}"
    if [[ "${session^^}" == *GNOME* && "${session^^}" != *CINNAMON* ]]; then
        say "shortcut added to the application menu (GNOME shows no desktop icons)"
        return
    fi
    local desk
    desk="$(desktop_dir)"
    mkdir -p "$desk"
    local entry copy
    for entry in "$game_entry" "$osmol_entry"; do
        [[ -f "$entry" ]] || continue
        copy="$desk/$(basename "$entry")"
        cp "$entry" "$copy" && chmod +x "$copy"
        # Cinnamon (Nemo) and others launch desktop files only once they are marked trusted.
        command -v gio >/dev/null && gio set "$copy" metadata::trusted true 2>/dev/null || true
    done
    say "shortcuts added to the desktop ($desk) and the application menu"
}

cmd_install() {
    local src="${MYWHOOSH_FROM:-}" mode=direct
    while (($#)); do
        case "$1" in
            --from) src="${2:-}"; shift ;;
            --hd) ;;
            --dircon) mode=dircon ;;
            --dircon=*) mode="dircon ${1#--dircon=}" ;;
            *) die "unknown option $1" ;;
        esac
        shift
    done
    [[ ! -e "$GAME" ]] || die "$GAME exists; run '$0 uninstall' first to reinstall from scratch"
    need
    mkdir -p "$ROOT" "$LOGS" "$CACHE" "$BIN"
    echo "$EDITION" >"$ROOT/edition"
    echo "$mode" >"$ROOT/bluetooth"
    # The installed copy runs from $BIN, independent of where this script came from.
    install -m 755 "$HERE/mywhoosh.sh" "$HERE/ble-bridge.py" "$BIN/"
    install_proton
    install_umu
    install_shim
    install_game "$src"
    cmd_reset_prefix
    install_shortcuts
    cmd_doctor || true
}

cmd_reset_prefix() {
    proton_env
    stop_stale
    rm -rf "$PFX"
    mkdir -p "$PFX" "$LOGS"
    say "preparing Windows environment (first time downloads the Steam runtime, a few minutes)"
    "$UMU" wineboot -u >"$LOGS/prefix-$(date +%Y%m%d-%H%M%S).log" 2>&1 \
        || die "prefix creation failed; see $LOGS"
}

cmd_run() {
    proton_env
    [[ -f "$EXE" ]] || die "game not installed; run: $0 install"
    if grep -q 'Services.*Bonjour Service' "$PFX/system.reg" 2>/dev/null; then
        die "Bonjour is installed in the prefix and will crash MyWhoosh; run: $0 reset-prefix"
    fi
    mkdir -p "$LOGS"
    [[ "${MYWHOOSH_NO_UPDATE:-}" == 1 ]] || cmd_update || say "update failed; starting the installed version"
    stop_stale
    local mode target
    read -r mode target <"$ROOT/bluetooth" 2>/dev/null || mode=direct
    local log
    log="$LOGS/run-$(date +%Y%m%d-%H%M%S).log"
    say "starting $TITLE $(installed_version) ($mode Bluetooth), log: $log"
    echo "edition=$EDITION version=$(installed_version) bluetooth=$mode proton=$PROTON_NAME" >"$log"
    if [[ "$mode" == dircon ]]; then
        if ! pgrep -x osmolcontrol >/dev/null && [[ -x "$OSMOL" ]]; then
            say "starting OsmolControl"
            setsid "$OSMOL" >/dev/null 2>&1 &
        fi
        local name="DirCon Trainer"
        [[ -x "$OSMOL" ]] && name="OsmolControl"
        python3 -I "$HERE/ble-bridge.py" --name "$name" ${target:+--dircon "$target"} >>"$log" 2>&1 &
    else
        # System python: blehelper needs the distribution's dbus and gi modules.
        python3 "$WINRT/blehelper.py" >>"$log" 2>&1 &
    fi
    local bridge=$!
    local status=0
    (cd "$(dirname "$EXE")" && "$UMU" "$EXE") >>"$log" 2>&1 || status=$?
    kill "$bridge" 2>/dev/null || true
    echo "exit status $status" >>"$log"
    say "$TITLE exited with status $status"
    # Keep the last 20 logs.
    ls -1t "$LOGS"/run-*.log 2>/dev/null | tail -n +21 | xargs -r rm -f
    return "$status"
}

cmd_doctor() {
    local ok=1
    check() { if eval "$2" >/dev/null 2>&1; then say "ok    $1"; else say "FAIL  $1"; ok=0; fi; }
    say "$TITLE in $ROOT"
    check "Proton $PROTON_NAME" "[[ -x '$PROTON_DIR/proton' ]]"
    check "umu" "[[ -x '$UMU' ]]"
    check "game files ($(installed_version))" "[[ -f '$EXE' ]]"
    check "prefix" "[[ -d '$PFX/drive_c' ]]"
    check "WinRT assemblies" "[[ -f '$WINRT/Windows.dll' && -f '$WINRT/MyWhooshShim.dll' ]]"
    check "no Bonjour in the prefix" "! grep -q 'Services.*Bonjour Service' '$PFX/system.reg'"
    check "Bonjour installer disabled" "! find '$GAME' -iname bonjoursdksetup.exe | grep -q ."
    local mode=direct
    read -r mode _ <"$ROOT/bluetooth" 2>/dev/null || true
    if [[ "$mode" == dircon ]]; then
        check "DirCon bridge" "[[ -f '$HERE/ble-bridge.py' ]]"
        check "OsmolControl (optional)" "[[ -x '$OSMOL' ]]"
    else
        check "Bluetooth helper" "[[ -f '$WINRT/blehelper.py' ]] && python3 -c 'import dbus, gi'"
    fi
    check "Bluetooth service" "systemctl is-active --quiet bluetooth"
    if [[ "$mode" == dircon ]]; then
        check "network connection (DirCon serves on the LAN address)" \
            "ip -4 -o addr show scope global | grep -q inet"
    fi
    [[ $ok == 1 ]]
}

cmd_uninstall() {
    stop_stale
    rm -rf "$ROOT"
    local desk
    desk="$(desktop_dir)"
    rm -f "$APPS/$SLUG.desktop" "$desk/$SLUG.desktop"
    say "removed $ROOT and its shortcuts (Proton and OsmolControl kept for other installs)"
}

cmd="${1:-}"
(($#)) && shift
case "$cmd" in
    install) cmd_install "$@" ;;
    run) cmd_run ;;
    update) cmd_update ;;
    doctor) cmd_doctor ;;
    reset-prefix) cmd_reset_prefix ;;
    uninstall) cmd_uninstall ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
esac
