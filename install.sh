#!/usr/bin/env bash
# MyWhoosh for Linux: the one script to run.
#
#   curl -fsSL https://raw.githubusercontent.com/Parapeth962/mywhoosh-linux-installer/main/install.sh | bash
#   ./install.sh [--hd | --standard] [--direct | --dircon[=HOST:PORT]]
#
# Installs the few system packages it needs (apt, dnf or pacman; asks for your password once),
# downloads MyWhoosh from Microsoft's servers and prepares it to run under Proton, with
# Bluetooth, shortcuts and automatic updates. Run it as your normal user, not with sudo.
set -euo pipefail

REPO="Parapeth962/mywhoosh-linux-installer"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
say() { printf '  %s\n' "$*"; }
die() { printf '\n\033[31mProblem: %s\033[0m\n' "$*" >&2; exit 1; }
ask() { local answer; read -r -p "  $1 " answer </dev/tty; echo "$answer"; }

[[ $EUID -ne 0 ]] || die "run this as your normal user, without sudo (it asks for the password itself)"
[[ "$(uname -m)" == x86_64 ]] || die "only 64-bit PCs (x86_64) are supported"

# Started through curl | bash: fetch the rest of the installer first.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /nonexistent)"
if [[ ! -f "$HERE/mywhoosh.sh" ]]; then
    command -v curl >/dev/null && command -v tar >/dev/null || die "please install curl and tar first"
    tmp="$(mktemp -d)"
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp" \
        || die "could not download the installer"
    exec bash "$tmp/${REPO#*/}-main/install.sh" "$@"
fi

bold "MyWhoosh for Linux - installer"

edition="" mode=""
for arg in "$@"; do
    case "$arg" in
        --hd) edition=hd ;;
        --standard) edition=standard ;;
        --direct) mode=direct ;;
        --dircon | --dircon=*) mode="$arg" ;;
        *) die "unknown option $arg" ;;
    esac
done

if [[ -z "$edition" ]]; then
    bold "Which MyWhoosh do you want?"
    say "1) MyWhoosh      - recommended, runs on most PCs (download about 4 GB)"
    say "2) MyWhoosh HD   - nicer graphics, needs a strong graphics card (about 15 GB)"
    case "$(ask "Type 1 or 2 and press Enter [1]:")" in
        2) edition=hd ;;
        *) edition=standard ;;
    esac
fi
if [[ -z "$mode" ]]; then
    if [[ -x "$HOME/.local/bin/osmolcontrol" ]]; then
        mode=--dircon
        say "OsmolControl found: MyWhoosh will use it as its trainer."
    else
        bold "How do your trainer and sensors connect?"
        say "1) Bluetooth, directly from MyWhoosh   - most people choose this"
        say "2) Through a DirCon bridge app running on this PC (qdomyos-zwift, OsmolControl, ...)"
        case "$(ask "Type 1 or 2 and press Enter [1]:")" in
            2) mode=--dircon ;;
            *) mode=direct ;;
        esac
    fi
fi

need_gb=8
[[ "$edition" == hd ]] && need_gb=20
free_gb=$(( $(df -Pk "$HOME" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
((free_gb >= need_gb)) || die "not enough disk space: $need_gb GB needed in your home folder, $free_gb GB free"

bold "Step 1/2: system packages"
if command -v apt-get >/dev/null; then
    packages=(python3 python3-dbus python3-gi curl ca-certificates tar libnotify-bin bluez
              mesa-vulkan-drivers xdg-user-dirs)
    refresh=(sudo apt-get update)
    install_cmd=(sudo apt-get install -y)
elif command -v dnf >/dev/null; then
    packages=(python3 python3-dbus python3-gobject curl ca-certificates tar libnotify bluez
              mesa-vulkan-drivers xdg-user-dirs)
    refresh=()
    install_cmd=(sudo dnf install -y)
elif command -v pacman >/dev/null; then
    packages=(python python-dbus python-gobject curl ca-certificates tar libnotify bluez bluez-utils
              xdg-user-dirs)
    refresh=()
    install_cmd=(sudo pacman -S --needed --noconfirm)
else
    die "this Linux has neither apt, dnf nor pacman; install python3 (with dbus and gi), curl, tar and bluez yourself, then rerun"
fi
say "Installing: ${packages[*]}"
say "Your password may be asked for (this is sudo, the normal way to install software)."
((${#refresh[@]} == 0)) || "${refresh[@]}"
"${install_cmd[@]}" "${packages[@]}" || die "installing system packages failed"
if ! systemctl is-active --quiet bluetooth; then
    say "Turning on the Bluetooth service"
    sudo systemctl enable --now bluetooth || say "Could not start Bluetooth; check that your PC has it switched on"
fi

bold "Step 2/2: MyWhoosh (the longest part)"
flags=()
[[ "$edition" == hd ]] && flags+=(--hd)
[[ "$mode" == --dircon* ]] && flags+=("$mode")
"$HERE/mywhoosh.sh" install "${flags[@]}"

title="MyWhoosh"
root="$HOME/Games/mywhoosh-linux"
if [[ "$edition" == hd ]]; then
    title="MyWhoosh HD"
    root="$HOME/Games/mywhoosh-hd-linux"
fi
bold "Done! Start \"$title\" from your desktop or application menu."
if [[ "$mode" == direct ]]; then
    cat <<EOF
  Pairing: in MyWhoosh open Device Connection -> BLE and pick your trainer, heart-rate strap
  or controller. Do not connect them to any other app at the same time.
EOF
else
    cat <<EOF
  Pairing: start your DirCon app first (OsmolControl starts by itself; press "Start ride").
  In MyWhoosh open Device Connection -> BLE -> Power Source and pick the bridged trainer.
EOF
fi
cat <<EOF

  Updates are automatic: when MyWhoosh releases a new version, the next start downloads it.
  Something wrong? Run:  $root/bin/mywhoosh.sh doctor
EOF
