#!/usr/bin/env bash
# Ubuntu Hacker Theme: black and neon-green desktop for Ubuntu 26.04 (GNOME 50).
#
# User-level only: this script never uses sudo and only writes inside your home folder.
# Every setting it changes is recorded first, so ./uninstall.sh can put things back.
#
# usage: ./install.sh [--name BANNER_NAME] [--force]
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DATA="$HOME/.local/share/ubuntu-hacker-theme"
RESTORE="$DATA/restore-gsettings.sh"
CREATED="$DATA/created-files"
BACKUP="$DATA/backup"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
UUIDS=(hacker-panel@ubuntu-hacker-theme hacker-tools@ubuntu-hacker-theme)
SUPPORTED_GNOME=50
PACKAGES=(papirus-icon-theme fonts-jetbrains-mono fonts-ibm-plex cmatrix fastfetch bat eza btop
          python3-pil gnome-session-canberra libglib2.0-bin ptyxis)

BANNER_NAME="${USER}"
FORCE=0

G=$'\e[1;32m' D=$'\e[0;32m' R=$'\e[1;31m' Y=$'\e[1;33m' N=$'\e[0m'
step() { printf '%s[*]%s %s\n' "$G" "$N" "$1"; }
note() { printf '%s    %s%s\n' "$D" "$1" "$N"; }
warn() { printf '%s[!]%s %s\n' "$Y" "$N" "$1"; }
die()  { printf '%s[x]%s %s\n' "$R" "$N" "$1" >&2; exit 1; }

usage() {
  cat <<EOF
Ubuntu Hacker Theme installer (user-level, no sudo)

  ./install.sh                  install, using your username for the terminal banner
  ./install.sh --name NEO       use NEO as the terminal banner text (up to 10 letters)
  ./install.sh --force          try anyway on a GNOME version other than $SUPPORTED_GNOME

Undo everything with ./uninstall.sh
EOF
}

while (($#)); do
  case $1 in
    --name) BANNER_NAME=${2:?--name needs a value}; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------- checks
preflight() {
  ((EUID != 0)) || die "Run this as your normal user, not with sudo. It only changes your own account."
  [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* ]] || die "This theme needs the GNOME desktop (Ubuntu's default)."
  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || die "Run this from a terminal inside your desktop session."

  local version major
  version=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*' | head -1) || true
  major=${version%%.*}
  if [[ $major != "$SUPPORTED_GNOME" ]]; then
    if ((FORCE)); then
      warn "GNOME ${version:-unknown} detected; this theme was built and tested on GNOME $SUPPORTED_GNOME (Ubuntu 26.04)."
      warn "Continuing because of --force. The top-bar extensions may not load on this version."
    else
      die "GNOME ${version:-unknown} detected, but this theme supports GNOME $SUPPORTED_GNOME (Ubuntu 26.04). Use --force to try anyway."
    fi
  fi

  local missing=()
  for pkg in "${PACKAGES[@]}"; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || missing+=("$pkg")
  done
  if ((${#missing[@]})); then
    printf '%s[x]%s Some packages this theme needs are missing. Install them with:\n\n' "$R" "$N" >&2
    printf '    sudo apt install %s\n\n' "${missing[*]}" >&2
    printf 'then run ./install.sh again.\n' >&2
    exit 1
  fi
}

# ---------------------------------------------------------------- bookkeeping
# Remember a setting's current value (only the first time, so re-running keeps the true original).
record() {
  local schema=$1 key=$2 line
  line=$(printf 'gsettings set %q %q' "$schema" "$key")
  grep -qF -- "$line " "$RESTORE" 2>/dev/null && return 0
  printf '%s %q\n' "$line" "$(gsettings get "$schema" "$key")" >> "$RESTORE"
}

set_key() {
  local schema=$1 key=$2 value=$3
  gsettings list-keys "$schema" 2>/dev/null | grep -qx "$key" || { note "(skipped $key: not available here)"; return 0; }
  record "$schema" "$key"
  gsettings set "$schema" "$key" "$value"
}

# Copy a file into place; an existing file that isn't ours is backed up and restored on uninstall.
place() {
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"
  if [[ -e $dst ]] && ! grep -qxF -- "$dst" "$CREATED" 2>/dev/null; then
    mkdir -p "$BACKUP$(dirname "$dst")"
    cp -a -- "$dst" "$BACKUP$dst"
  fi
  cp -- "$src" "$dst"
  grep -qxF -- "$dst" "$CREATED" 2>/dev/null || echo "$dst" >> "$CREATED"
}

generate() { python3 "$HERE/generators/$1" "${@:2}"; }

screen_size() {
  local size
  size=$(xrandr 2>/dev/null | grep -m1 -oE '[0-9]{3,5}x[0-9]{3,5}\s+[0-9.]+\*' | grep -oE '^[0-9]+x[0-9]+') || true
  echo "${size:-1920x1080}"
}

# ---------------------------------------------------------------- parts
install_look() {
  step "Wallpaper, dark mode and green accent"
  local wallpaper="$DATA/wallpaper.png"
  generate wallpaper.py "$wallpaper" "$(hostname)" "$(screen_size)"
  set_key org.gnome.desktop.background picture-uri "file://$wallpaper"
  set_key org.gnome.desktop.background picture-uri-dark "file://$wallpaper"
  set_key org.gnome.desktop.background picture-options zoom
  set_key org.gnome.desktop.screensaver picture-uri "file://$wallpaper"
  set_key org.gnome.desktop.interface color-scheme prefer-dark
  set_key org.gnome.desktop.interface accent-color green
  if [[ -d /usr/share/themes/Yaru-olive-dark ]]; then
    set_key org.gnome.desktop.interface gtk-theme Yaru-olive-dark
  fi

  step "Fonts: IBM Plex Sans for apps, JetBrains Mono for code"
  set_key org.gnome.desktop.interface font-name 'IBM Plex Sans 11'
  set_key org.gnome.desktop.interface document-font-name 'IBM Plex Sans 11'
  set_key org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 12'
  set_key org.gnome.desktop.wm.preferences titlebar-font 'IBM Plex Sans SemiBold 11'
}

install_icons() {
  step "Green icons (building from Papirus, takes a few seconds)"
  generate icons.py "$HOME/.local/share/icons/Papirus-Hacker" | sed "s/^/    /"
  gtk-update-icon-cache -f "$HOME/.local/share/icons/Papirus-Hacker" >/dev/null 2>&1 || true
  set_key org.gnome.desktop.interface icon-theme Papirus-Hacker

  step "Green mouse cursor"
  generate cursor.py "$HOME/.local/share/icons/Hacker-Cursor" | sed "s/^/    /"
  set_key org.gnome.desktop.interface cursor-theme Hacker-Cursor

  # Some snap apps point at a fixed image instead of the icon theme; give them green launchers.
  local -A snap_icons=(
    [firefox_firefox]=firefox
    [snap-store_snap-store]=org.gnome.Software
    [desktop-security-center_desktop-security-center]=preferences-system-privacy
    [firmware-updater_firmware-updater-app]=org.gnome.Firmware
  )
  local id src
  for id in "${!snap_icons[@]}"; do
    src="/var/lib/snapd/desktop/applications/$id.desktop"
    [[ -f $src ]] || continue
    sed "s|^Icon=.*|Icon=${snap_icons[$id]}|" "$src" > "$DATA/$id.desktop"
    place "$DATA/$id.desktop" "$HOME/.local/share/applications/$id.desktop"
  done
}

install_sounds() {
  step "Retro beep sound effects"
  generate sounds.py "$HOME/.local/share/sounds/hacker" | sed "s/^/    /"
  set_key org.gnome.desktop.sound theme-name hacker
  set_key org.gnome.desktop.sound event-sounds true
  cat > "$DATA/hacker-login-sound.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Hacker login sound
Comment=Plays the "access granted" chirp after logging in
Exec=sh -c "sleep 3; canberra-gtk-play -i desktop-login"
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
  place "$DATA/hacker-login-sound.desktop" "$HOME/.config/autostart/hacker-login-sound.desktop"
}

install_terminal() {
  step "Terminal colours, prompt, banner and tools"
  place "$HERE/assets/config/hacker-green.palette" "$HOME/.local/share/org.gnome.Ptyxis/palettes/hacker-green.palette"
  local uuid
  uuid=$(gsettings get org.gnome.Ptyxis default-profile-uuid 2>/dev/null | tr -d "'") || true
  if [[ -n $uuid ]]; then
    set_key "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$uuid/" palette hacker-green
    set_key "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$uuid/" opacity 0.92
  fi
  set_key org.gnome.Ptyxis use-system-font false
  set_key org.gnome.Ptyxis font-name 'JetBrains Mono 13'
  set_key org.gnome.Ptyxis cursor-shape block
  set_key org.gnome.Ptyxis cursor-blink-mode on
  set_key org.gnome.Ptyxis interface-style dark

  generate banner.py "$BANNER_NAME" "$DATA/hacker-banner.txt"
  place "$DATA/hacker-banner.txt" "$HOME/.config/fastfetch/hacker-banner.txt"
  place "$HERE/assets/config/fastfetch.jsonc" "$HOME/.config/fastfetch/config.jsonc"
  place "$HERE/assets/config/btop-hacker.theme" "$HOME/.config/btop/themes/hacker.theme"
  if [[ -f $HOME/.config/btop/btop.conf ]]; then
    cp "$HOME/.config/btop/btop.conf" "$DATA/btop.conf"
    sed -i 's/^color_theme = .*/color_theme = "hacker"/' "$DATA/btop.conf"
  else
    printf 'color_theme = "hacker"\ntheme_background = True\n' > "$DATA/btop.conf"
  fi
  place "$DATA/btop.conf" "$HOME/.config/btop/btop.conf"

  # .bashrc: back it up once, then (re)write our marked block at the end
  local rc="$HOME/.bashrc"
  [[ -f $DATA/bashrc.before ]] || cp "$rc" "$DATA/bashrc.before" 2>/dev/null || touch "$DATA/bashrc.before"
  if [[ -f $rc ]]; then
    sed -i '/^# >>> hacker-theme >>>$/,/^# <<< hacker-theme <<<$/d' "$rc"
  fi
  # start on a fresh line if the file doesn't already end with one
  if [[ -s $rc && $(tail -c1 "$rc") != "" ]]; then echo >> "$rc"; fi
  cat "$HERE/assets/config/bashrc-block.sh" >> "$rc"
}

install_saver() {
  step "Matrix screen saver (after 3 minutes idle)"
  place "$HERE/assets/config/hacker-matrix-saver" "$HOME/.local/bin/hacker-matrix-saver"
  chmod +x "$HOME/.local/bin/hacker-matrix-saver"
  place "$HERE/assets/config/hacker-matrix-saver.service" "$HOME/.config/systemd/user/hacker-matrix-saver.service"
  systemctl --user daemon-reload
  systemctl --user enable --now hacker-matrix-saver.service >/dev/null 2>&1 \
    || warn "Could not start the screen saver service; it will start at your next login."
}

install_extensions() {
  step "Top bar, dock and notification styling, live stats and F12 drop-down terminal"
  local uuid
  for uuid in "${UUIDS[@]}"; do
    rm -rf "${EXT_DIR:?}/$uuid"
    mkdir -p "$EXT_DIR"
    cp -r "$HERE/assets/extensions/$uuid" "$EXT_DIR/$uuid"
    if [[ -d $EXT_DIR/$uuid/schemas ]]; then
      glib-compile-schemas "$EXT_DIR/$uuid/schemas"
    fi
  done
  set_key org.gnome.shell disable-user-extensions false
  # add our extensions to the enabled list without disturbing anything else in it
  local current
  current=$(gsettings get org.gnome.shell enabled-extensions)
  gsettings set org.gnome.shell enabled-extensions "$(python3 - "$current" "${UUIDS[@]}" <<'EOF'
import ast, sys
raw = sys.argv[1].removeprefix("@as ")
items = ast.literal_eval(raw) if raw.strip() else []
for uuid in sys.argv[2:]:
    if uuid not in items:
        items.append(uuid)
print(repr(items))
EOF
)"

  step "Dock: black background with green running indicators"
  local dock=org.gnome.shell.extensions.dash-to-dock
  set_key $dock custom-background-color true
  set_key $dock background-color '#000000'
  set_key $dock transparency-mode FIXED
  set_key $dock background-opacity 0.85
  set_key $dock running-indicator-style SEGMENTED
  set_key $dock custom-theme-customize-running-dots true
  set_key $dock custom-theme-running-dots-color '#00ff66'
  set_key $dock custom-theme-running-dots-border-color '#00ff66'
  set_key $dock custom-theme-running-dots-border-width 0
}

install_brave() {
  local src
  for src in /var/lib/snapd/desktop/applications/brave_brave.desktop /usr/share/applications/brave-browser.desktop; do
    [[ -f $src ]] && break
  done
  [[ -f $src ]] || return 0
  step "Brave browser: black and green theme"
  # Snap Brave can only read non-hidden folders in your home, so the theme can't live under ~/.local
  local theme="$HOME/brave-hacker-theme"
  place "$HERE/assets/config/brave-theme-manifest.json" "$theme/manifest.json"
  local name
  name=$(basename "$src")
  # Brave only allows a local theme through this start-up option, so its launcher passes it every time
  sed -e "s|^\(Exec=[^ ]*\)|\1 --load-extension=$theme|" -e 's|^Icon=.*|Icon=brave-browser|' "$src" > "$DATA/$name"
  place "$DATA/$name" "$HOME/.local/share/applications/$name"
  note "Restart Brave from the dock or app grid to see it."
}

# ---------------------------------------------------------------- main
main() {
  preflight
  mkdir -p "$DATA"
  touch "$RESTORE" "$CREATED"
  printf '%s\n' "${G}>> Installing Ubuntu Hacker Theme for $USER${N}"

  install_look
  install_icons
  install_sounds
  install_terminal
  install_saver
  install_extensions
  install_brave
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

  date -Iseconds > "$DATA/installed"
  cat <<EOF

${G}[+] ACCESS GRANTED. Theme installed.${N}

${D}Log out and back in to finish: the top bar, dock outline, live stats and
F12 drop-down terminal only load at login. Open a new terminal to see the
new prompt.

Undo everything at any time with ./uninstall.sh${N}
EOF
}

main
