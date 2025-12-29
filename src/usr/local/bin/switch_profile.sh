#!/bin/bash
# Usage: switch_profile.sh [headphones|car]

PROFILE=$1
CONFIG_DIR="/etc/camilladsp"

if [[ "$PROFILE" == "headphones" ]]; then
    echo "Switching to HEADPHONES profile (+12dB Gain, EQ)..."
    ln -sf "$CONFIG_DIR/headphones.yml" "$CONFIG_DIR/active_config.yml"
elif [[ "$PROFILE" == "car" ]]; then
    echo "Switching to CAR profile (0dB Gain, Flat)..."
    ln -sf "$CONFIG_DIR/car.yml" "$CONFIG_DIR/active_config.yml"
else
    echo "Usage: $0 [headphones|car]"
    exit 1
fi

echo "Restarting DSP..."
systemctl restart camilladsp
systemctl status camilladsp --no-pager
