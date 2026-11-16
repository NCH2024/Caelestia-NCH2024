#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WITH_SDDM=0
WITH_POLKIT=0
INSTALL_PKGS=0

for arg in "$@"; do
    case "$arg" in
        --with-sddm) WITH_SDDM=1 ;;
        --with-polkit) WITH_POLKIT=1 ;;
        --with-pkgs) INSTALL_PKGS=1 ;;
        --all) WITH_SDDM=1; WITH_POLKIT=1; INSTALL_PKGS=1 ;;
        -h|--help)
            cat <<USAGE
Usage: ./install.sh [OPTIONS]
  --with-pkgs     Install recommended Arch/CachyOS runtime dependencies via pacman
  --with-sddm     Install & activate the Caelestia SDDM login theme
  --with-polkit   Configure passwordless pkexec for optimization/update UI actions
  --all           Enable all of the above
USAGE
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

TS="$(date +%Y%m%d-%H%M%S)"
backup_if_exists() {
    local target="$1"
    if [[ -e "$target" && ! -L "$target" ]]; then
        echo "[Backup] $target -> ${target}.bak-${TS}"
        mv "$target" "${target}.bak-${TS}"
    fi
}

if (( INSTALL_PKGS == 1 )); then
    echo "[1/5] Installing runtime dependencies via pacman..."
    sudo pacman -S --needed --noconfirm \
        hyprland quickshell-git caelestia-cli \
        power-profiles-daemon pipewire wireplumber \
        ananicy-cpp pacman-contrib bluez networkmanager \
        sddm qt6-5compat grim foot ydotool python || true
    if pacman -Si scx-scheds scx-tools >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm scx-scheds scx-tools || true
    fi
fi

echo "[2/5] Installing Quickshell, Hyprland & Caelestia user configs..."
mkdir -p "$HOME/.config/quickshell" "$HOME/.config/caelestia" "$HOME/.config/hypr"

backup_if_exists "$HOME/.config/quickshell/caelestia"
cp -a "$REPO_DIR/config/quickshell/caelestia" "$HOME/.config/quickshell/"

backup_if_exists "$HOME/.config/hypr"
mkdir -p "$HOME/.config/hypr"
cp -a "$REPO_DIR/config/hypr/." "$HOME/.config/hypr/"

for f in shell.json hypr-user.lua hypr-vars.lua equalizer.json extra.json optimizer.json ai_automation.json; do
    if [[ -f "$REPO_DIR/config/caelestia/$f" ]]; then
        [[ -f "$HOME/.config/caelestia/$f" ]] && cp -a "$HOME/.config/caelestia/$f" "$HOME/.config/caelestia/${f}.bak-${TS}"
        cp -a "$REPO_DIR/config/caelestia/$f" "$HOME/.config/caelestia/$f"
    fi
done

echo "[3/5] Detecting GPU & hardware layout..."
igpu_card=""
dgpu_card=""
for c in /dev/dri/by-path/*-card; do
    [[ -e "$c" ]] || continue
    drv=$(basename "$(readlink -f "/sys/class/drm/$(basename "$(readlink -f "$c")")/device/driver" 2>/dev/null)" 2>/dev/null || true)
    case "$drv" in
        amdgpu|i915|xe) [[ -z "$igpu_card" ]] && igpu_card="$c" ;;
        nvidia) [[ -z "$dgpu_card" ]] && dgpu_card="$c" ;;
    esac
done

if [[ -n "$igpu_card" && -n "$dgpu_card" ]]; then
    echo "  -> Hybrid iGPU+NVIDIA detected ($igpu_card:$dgpu_card)"
    cat >> "$HOME/.config/hypr/hyprland/env.lua" <<ENV

-- Auto-configured iGPU-first Wayland compositing for hybrid Optimus laptops
hl.env("AQ_DRM_DEVICES", "${igpu_card}:${dgpu_card}")
ENV
elif [[ -n "$igpu_card" ]]; then
    sed -i 's/"gpuType": "Nvidia"/"gpuType": "None"/' "$HOME/.config/caelestia/shell.json" || true
fi

echo "[4/5] Installing hardware telemetry & optimizer CLI helpers (/usr/local/bin)..."
sudo install -m 0755 "$REPO_DIR/bin/caelestia-optimize" /usr/local/bin/caelestia-optimize
sudo install -m 0755 "$REPO_DIR/bin/caelestia-telemetry" /usr/local/bin/caelestia-telemetry

if (( WITH_SDDM == 1 )); then
    echo "[Optional] Installing Caelestia SDDM login theme..."
    sudo mkdir -p /usr/share/sddm/themes /etc/sddm.conf.d
    sudo rm -rf /usr/share/sddm/themes/caelestia
    sudo cp -a "$REPO_DIR/sddm-theme/caelestia" /usr/share/sddm/themes/caelestia
    sudo install -m 0644 "$REPO_DIR/system/sddm-10-caelestia.conf" /etc/sddm.conf.d/10-caelestia.conf
fi

if (( WITH_POLKIT == 1 )); then
    echo "[Optional] Installing Polkit rule for user '$USER'..."
    sudo mkdir -p /etc/polkit-1/rules.d
    sed "s/@@TARGET_USER@@/$USER/g" "$REPO_DIR/system/polkit-10-caelestia.rules.template" \
        | sudo tee /etc/polkit-1/rules.d/10-caelestia.rules >/dev/null
    sudo chmod 0644 /etc/polkit-1/rules.d/10-caelestia.rules
fi

echo "[5/5] Enabling core services..."
sudo systemctl enable --now power-profiles-daemon.service >/dev/null 2>&1 || true
sudo systemctl enable --now fstrim.timer >/dev/null 2>&1 || true
sudo systemctl enable --now ananicy-cpp.service >/dev/null 2>&1 || true
systemctl list-unit-files scx_loader.service >/dev/null 2>&1 && sudo systemctl enable --now scx_loader.service >/dev/null 2>&1 || true

echo ""
echo "Installation complete! Reload shell with:"
echo "  pkill -x qs; caelestia shell -d"
