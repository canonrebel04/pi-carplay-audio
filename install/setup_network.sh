#!/bin/bash
# Network Setup Script
# Usage: ./setup_network.sh "Home_SSID" "Home_Password" "Hotspot_SSID" "Hotspot_Password"

HOME_SSID=${1:-"MyHomeWiFi"}
HOME_PASS=${2:-"password123"}
HOTSPOT_SSID=${3:-"CarPlay-Pi"}
HOTSPOT_PASS=${4:-"CarPlay1234"}

echo "Configuring NetworkManager..."
sudo nmcli con add type wifi ifname wlan0 con-name "Home_WiFi" ssid "$HOME_SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOME_PASS" connection.autoconnect yes connection.autoconnect-priority 100
# Hotspot: Manual IP (DHCP handled by dnsmasq)
sudo nmcli con add type wifi ifname wlan1 con-name "Car_Hotspot" ssid "$HOTSPOT_SSID" mode ap wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PASS" ipv4.method manual ipv4.addresses 192.168.50.1/24 connection.autoconnect yes
echo "Done. Profiles created."

