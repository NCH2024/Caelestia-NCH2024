# Caelestia × NCH2024 Remake

A heavily customized, hardware-aware remake of **Caelestia Shell** (`Quickshell` + `Hyprland`) with a unified **Nexus Control Center**, **Top-Hover Smart Optimization Dashboard**, **Adaptive Thermal & Fan Control**, **CachyOS `sched-ext` Integration**, **10-Band PipeWire Studio Equalizer**, and a matching **SDDM Login Theme**.

Maintained by **[NCH2024](https://github.com/NCH2024)** on top of upstream Caelestia.

---

## Key Features Added in This Remake

1. **Top-Hover `Optimization` Tab (before Weather)**
   - Designed cleanly for everyday users with zero technical clutter:
     - **PC Health Ring** (`0–100`), RAM & storage summary, and 1-click **Boost & Clean Now** (drops page cache, compacts memory, cleans broken pacman `download-*` folders & old `paccache`, vacuums journald logs, clears thumbnails, resets failed systemd units, and runs `fstrim`).
     - **3-Tap Smart Performance Presets**: **Quiet** (`power-saver` + `scx_bpfland` PowerSave), **Everyday** (`balanced` cool tuning + `scx_lavd` Auto), **Max Speed** (`performance` + CPU Turbo + `scx_lavd` Gaming).
     - **Max Fan Cooling** toggle + **Automatic Care** switches (*Cool & quiet balanced tuning*, *Auto-free RAM >85%*, *Update cache cleanup*).
2. **Adaptive Balanced Cooling & Anti-Heat Optimization**
   - Prevents laptops (especially AMD Ryzen + NVIDIA Optimus) from idling hot (`balance_performance` 4 GHz spikes with 0 RPM fans).
   - Uses `balance_power` EPP + `80%` max frequency cap in Balanced mode, plus a gentle hysteresis fan floor (`auto-cool` via `dell_smm`) when temps climb `≥ 61°C`.
   - Avoids waking sleeping NVIDIA dGPUs during telemetry polling (`runtime_status` check before calling `nvidia-smi`).
3. **Nexus Settings Control Center (`Mod + Comma` / Tray / Quick Settings)**
   - **Power, Fans & Care:** `scx_loader` (`EEVDF`, `LAVD`, `Bpfland`, `Cosmos`, `Rusty`), NVMe I/O scheduler (`kyber`, `none`, `mq-deadline`, `adios`), CPU Turbo Boost toggle, idle/DPMS/sleep timeouts, Dual-GPU live readout, and manual CPU/GPU Fan Boost sliders.
   - **Studio 10-Band Equalizer:** Runs PipeWire filter-chain stably as a user systemd unit (`caelestia-eq.service`) with presets & instant sink switching.
   - **Seamless Updates & Hardware Drivers:** Non-blocking GUI progress bar (`pkexec` + `TaskRunner`) with expandable terminal logs only when requested.
   - **About Page (`Caelestia × NCH2024`):** Features both the animated Caelestia emblem and clickable **NCH2024** GitHub attribution.
4. **Unified SDDM Theme & Clean Logout**
   - Matching Caelestia SDDM greeter theme (`sddm-theme/caelestia`) and reliable Hyprland session exit (`hyprctl dispatch exit`).

---

## Prerequisites (Arch / CachyOS)

Recommended core packages before running the installer:

```bash
# Official / CachyOS repositories
sudo pacman -S --needed hyprland quickshell-git caelestia-cli \
  power-profiles-daemon pipewire wireplumber ananicy-cpp \
  pacman-contrib bluez networkmanager sddm qt6-5compat

# Optional (for CachyOS sched-ext CPU schedulers: LAVD, Bpfland, Cosmos, Rusty)
sudo pacman -S --needed scx-scheds scx-tools
```

> **Note:** On non-CachyOS Arch derivatives, install `quickshell-git` and `caelestia-cli` from the AUR (`paru -S quickshell-git caelestia-cli`) if not present in your pacman repos.

---

## Quick Installation

```bash
git clone https://github.com/NCH2024/Caelestia-NCH2024.git
cd Caelestia-NCH2024
chmod +x install.sh bin/*

# Standard user install (configs + /usr/local/bin/caelestia-{optimize,telemetry}):
./install.sh

# Full install (also installs SDDM theme & passwordless Polkit rule for $USER):
./install.sh --with-sddm --with-polkit
```

Existing configs in `~/.config/quickshell/caelestia`, `~/.config/hypr`, and `~/.config/caelestia` are automatically backed up with a timestamp (`*.bak-YYYYMMDD-HHMMSS`).

After installing, reload or log into Hyprland:

```bash
pkill -x qs; caelestia shell -d
```

---

## Adapting to Different Hardware Configurations

Because this remake was tuned on an **AMD Ryzen 5 5600H + NVIDIA RTX 3050 (Dell G15 5515)** laptop running **CachyOS**, follow the notes below if your hardware differs:

### 1. GPU Configuration (Single GPU vs Hybrid Optimus)
- **Hybrid Laptops (AMD/Intel iGPU + NVIDIA dGPU):**
  - `install.sh` automatically detects `/dev/dri/by-path/*-card` and appends `hl.env("AQ_DRM_DEVICES", "<igpu>:<dgpu>")` to `~/.config/hypr/hyprland/env.lua` so Hyprland composites on the iGPU and lets the NVIDIA GPU sleep in D3cold (`0 W`).
  - Ensure `nvidia-open` / `nvidia` RTD3 power management is enabled in `/etc/modprobe.d/` (`options nvidia NVreg_DynamicPowerManagement=0x02` if needed).
- **AMD-only or Intel-only Laptops / Desktops:**
  - In `~/.config/caelestia/shell.json`, set `"services": { "gpuType": "Amd" }` (or `"None"`).
  - Remove or comment out `AQ_DRM_DEVICES` in `~/.config/hypr/hyprland/env.lua` if you only have a single GPU.
- **NVIDIA Desktop (Single GPU):**
  - Do **not** set `AQ_DRM_DEVICES` to another card; in `~/.config/hypr/hyprland/env.lua` add standard NVIDIA Wayland env vars (`GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`) if your monitor is driven directly by NVIDIA.

### 2. CPU Vendor (`AMD Ryzen` vs `Intel Core`)
- `bin/caelestia-telemetry` automatically probes `k10temp`, `zenpower` (AMD), `coretemp` (Intel), and `acpitz` (ACPI fallback).
- On **Intel (`intel_pstate`)**, `energy_performance_preference` supports `power`, `balance_power`, `balance_performance`, and `performance`. If *Cool & quiet balanced tuning* feels too conservative on older Intel chips, toggle **Cool & quiet balanced tuning** off in the **Optimization** tab or adjust the `80%` frequency cap in `/usr/local/bin/caelestia-optimize`.
- If `sched-ext` (`scx_loader` / `scxctl`) is **not** installed (e.g., standard Linux kernel `< 6.12` without `scx-scheds`), the shell gracefully defaults to standard kernel **EEVDF** without errors.

### 3. Laptop Fan & Thermal Control
- **Dell G-Series / Alienware / Inspiron (`alienware_wmi` + `dell_smm`):** Supported out-of-the-box for both adaptive `auto-cool` and manual CPU/GPU % sliders.
- **ThinkPad (`thinkpad_hwmon`):** `caelestia-telemetry` reads fan RPM automatically. Manual fan sliders require `options thinkpad_acpi fan_control=1` or external tools like `thinkfan`.
- **ASUS / Lenovo Legion / Desktops:** `platform_profile` (`Power` / `Balanced` / `Performance`) works natively via `power-profiles-daemon`. Vendor-specific custom fan sliders (`dell_smm`) will safely no-op on non-Dell hardware without breaking other features.

### 4. Monitors, Resolution & Weather Location
- **Display Scale / Refresh Rate:** Edit monitor layout in `~/.config/hypr/hyprland/rules.lua` or `~/.config/caelestia/monitors/`, or configure directly inside **Nexus Settings → Display**.
- **Weather Location:** Set your latitude/longitude (`"weatherLocation": "lat,lon"`) in `~/.config/caelestia/shell.json` or via **Nexus Settings → Language & Region**.

### 5. Polkit Privileges (Optional Passwordless Actions)
- Clicking **Boost & Clean Now**, **Fan Boost**, or **System Updates** uses `pkexec`.
- If you prefer entering your password every time instead of seamless 1-click actions, **omit `--with-polkit`** when running `./install.sh` (or remove `/etc/polkit-1/rules.d/10-caelestia.rules`).

---

## Troubleshooting

- **Check live QML / Shell logs:**
  ```bash
  caelestia shell -l
  ```
- **Test optimization backend directly:**
  ```bash
  /usr/local/bin/caelestia-telemetry
  pkexec /usr/local/bin/caelestia-optimize thermal balanced
  ```
- **Reset Studio Equalizer if audio routing gets stuck:**
  ```bash
  systemctl --user stop caelestia-eq.service
  systemctl --user restart wireplumber pipewire
  ```
- **Uninstall system helpers:**
  ```bash
  ./uninstall.sh
  ```
