# Raspberry Pi Car Audio System (Headless & Ro-FS)

Turn your Raspberry Pi into a robust, audiophile-grade car audio receiver.
Features **Bluetooth (A2DP)** and **AirPlay (Shairport-Sync)** with seamless mixing, **Dual-Band WiFi** (Simultaneous AP + Client), and a **Read-Only Filesystem** that survives abrupt power cuts.

## Features

-   **Robust Power Handling**: Uses OverlayFS (Read-Only Root) to prevent SD card corruption.
-   **Universal Connectivity**:
    -   **Bluetooth 4.0+**: Auto-pairing, high-quality A2DP streaming.
    -   **AirPlay**: Lossless WiFi streaming for iOS devices.
    -   **Audio Mixing**: Intelligent `dmix` configuration allows simultaneous playback.
-   **Dual-Network Capability**:
    -   **wlan0**: Connects to Home WiFi (for updates/ssh).
    -   **wlan1**: Broadcasts dedicated **Hotspot (CarPlay-Pi)** for AirPlay access on the road.
    -   *Note: Requires two WiFi interfaces (Built-in + USB Dongle).*
-   **Audiophile Ready**: Supports I2S DACs (PCM5102a) and optimizes gain staging.

## FAQ

### 1. Does AirPlay really support Lossless WiFi streaming?
**Yes.** AirPlay transmits audio using the ALAC (Apple Lossless) codec over WiFi, which is significantly higher quality than Bluetooth SBC/AAC. However, the final quality depends on your Raspberry Pi's DAC (see "Hardware Requirements").

### 2. Can I get similar WiFi streaming on Android?
Android does not have a native system-wide equivalent to AirPlay.
**Solution:** Use **Spotify Connect**.
-   Install `raspotify` on the Pi (`curl -sL https://dtcooper.github.io/raspotify/install.sh | sh`).
-   This allows any Android phone to stream high-bitrate Spotify directly to the Pi over WiFi.

### 3. Why do I need the Hotspot?
The Hotspot (`CarPlay-Pi`) is **mandatory for AirPlay**.
-   AirPlay requires your phone and the Pi to be on the **same WiFi network**.
-   In a car, there is no router. The Pi *becomes* the router so your iPhone can "see" it.
-   **Bluetooth users do NOT need the hotspot.**

## Hardware Requirements

-   **Raspberry Pi**: Pi 2, 3, 4, or Zero 2 W.
-   **MicroSD Card**: 8GB+ (Class 10).
-   **WiFi**:
    -   1x Onboard (Client Mode).
    -   1x USB WiFi Adapter (Hotspot Mode).
-   **Bluetooth Dongle**: CSR 4.0 (Recommended).
-   **Power Supply**: High-quality 5V USB Car Charger (2.4A+).
-   **Optional**: PCM5102a DAC (Recommended for HiFi audio).

## File Structure

```
.
├── src/
│   ├── usr/local/bin/      # Startup scripts (bt-agent, volume-sync)
│   ├── etc/
│   │   ├── systemd/        # Service definitions (BlueALSA, Bluetooth overrides)
│   │   ├── asound.conf     # ALSA dmix mixer configuration
│   │   └── shairport-sync.conf
└── docs/
    └── architecture.md     # Detailed setup notes
```

## Installation

1.  **Flash OS**: Raspberry Pi OS Lite (Bookworm).
2.  **Copy Configs**: Deploy `src/` to `/`.
3.  **Install Dependencies**:
    ```bash
    sudo apt install git bluez-alsa-utils shairport-sync network-manager python3-dbus
    sudo ./install/install_dsp.sh  # Installs CamillaDSP
    ```
4.  **Enable OverlayFS**: `sudo raspi-config nonint enable_overlayfs`
5.  **Configure Network**:
    -   Set `wlan0` to your Home SSID.
    -   Set `wlan1` to Hotspot Mode (`ipv4.method shared`).

## License

MIT License. See [LICENSE](LICENSE) for details.
