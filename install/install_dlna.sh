#!/bin/bash
set -e

echo "Installing DLNA Renderer dependencies..."
apt-get update
# Install gmrender-resurrect (available in Bookworm) and GStreamer plugins
apt-get install -y gmediarender gstreamer1.0-alsa gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-tools

echo "DLNA Renderer installed."
