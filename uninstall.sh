#!/usr/bin/env bash
set -euo pipefail

echo "Removing system-level Caelestia Remake helpers & rules..."
sudo rm -f /usr/local/bin/caelestia-optimize /usr/local/bin/caelestia-telemetry
sudo rm -f /etc/sddm.conf.d/10-caelestia.conf
sudo rm -f /etc/polkit-1/rules.d/10-caelestia.rules
sudo rm -rf /usr/share/sddm/themes/caelestia

echo "System helpers removed. User backups (if any) remain in ~/.config/*.bak-*"
