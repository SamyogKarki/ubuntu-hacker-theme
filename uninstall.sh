#!/usr/bin/env bash
# Ubuntu Hacker Theme: remove everything install.sh added and put your old settings back.
# User-level only, no sudo. Packages installed with apt are left in place (see the end message).
set -uo pipefail

DATA="$HOME/.local/share/ubuntu-hacker-theme"
RESTORE="$DATA/restore-gsettings.sh"
CREATED="$DATA/created-files"
BACKUP="$DATA/backup"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
UUIDS=(hacker-panel@ubuntu-hacker-theme hacker-tools@ubuntu-hacker-theme)

G=$'\e[1;32m' D=$'\e[0;32m' R=$'\e[1;31m' N=$'\e[0m'
step() { printf '%s[*]%s %s\n' "$G" "$N" "$1"; }

((EUID != 0)) || { printf '%s[x]%s Run this as your normal user, not with sudo.\n' "$R" "$N" >&2; exit 1; }
[[ -d $DATA ]] || { echo "Ubuntu Hacker Theme doesn't seem to be installed for $USER; nothing to do."; exit 0; }

step "Stopping the Matrix screen saver"
systemctl --user disable --now hacker-matrix-saver.service >/dev/null 2>&1
pkill -f '^hacker-matrix-saver ' 2>/dev/null

step "Turning off the theme's extensions"
current=$(gsettings get org.gnome.shell enabled-extensions)
gsettings set org.gnome.shell enabled-extensions "$(python3 - "$current" "${UUIDS[@]}" <<'EOF'
import ast, sys
raw = sys.argv[1].removeprefix("@as ")
items = ast.literal_eval(raw) if raw.strip() else []
print(repr([u for u in items if u not in sys.argv[2:]]))
EOF
)"
for uuid in "${UUIDS[@]}"; do
  rm -rf "${EXT_DIR:?}/$uuid"
done

step "Restoring your previous settings"
if [[ -f $RESTORE ]]; then
  while IFS= read -r line; do
    eval "$line" 2>/dev/null || printf '    %scould not restore: %s%s\n' "$D" "$line" "$N"
  done < "$RESTORE"
fi

step "Removing theme files and restoring files they replaced"
if [[ -f $CREATED ]]; then
  while IFS= read -r path; do
    [[ -n $path && $path == "$HOME"/* ]] || continue
    rm -f -- "$path"
    if [[ -e $BACKUP$path ]]; then
      mkdir -p "$(dirname "$path")"
      cp -a -- "$BACKUP$path" "$path"
    fi
  done < "$CREATED"
fi
rm -rf "$HOME/.local/share/icons/Papirus-Hacker" "$HOME/.local/share/icons/Hacker-Cursor" "$HOME/.local/share/sounds/hacker"
systemctl --user daemon-reload >/dev/null 2>&1
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1

step "Removing the terminal block from ~/.bashrc"
[[ -f $HOME/.bashrc ]] && sed -i '/^# >>> hacker-theme >>>$/,/^# <<< hacker-theme <<<$/d' "$HOME/.bashrc"

rm -rf "$DATA"

cat <<EOF

${G}[+] Ubuntu Hacker Theme removed.${N}

${D}Log out and back in to finish (the top bar and dock reload at login), and
open a new terminal for the normal prompt.

The packages the theme used are still installed, since other apps may need
them. To remove them too:
  sudo apt remove papirus-icon-theme fonts-jetbrains-mono fonts-ibm-plex cmatrix fastfetch bat eza btop${N}
EOF
