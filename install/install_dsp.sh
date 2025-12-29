#!/bin/bash
set -e

# Version to install
VERSION="v2.0.3"
ARCH="armv7" # Pi 3/4/Zero2W (32-bit) running armhf OS
URL="https://github.com/HEnquist/camilladsp/releases/download/${VERSION}/camilladsp-linux-${ARCH}.tar.gz"

echo "Downloading CamillaDSP ${VERSION}..."
wget -O /tmp/camilladsp.tar.gz "$URL"

echo "Installing..."
tar -xzvf /tmp/camilladsp.tar.gz -C /tmp/
sudo mv /tmp/camilladsp /usr/local/bin/
sudo chmod +x /usr/local/bin/camilladsp

echo "Cleanup..."
rm /tmp/camilladsp.tar.gz

echo "CamillaDSP installed to /usr/local/bin/camilladsp"
