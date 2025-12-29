# Raspberry Pi Car Audio System (Headless & Ro-FS)

Turn your Raspberry Pi into a robust, audiophile-grade car audio receiver.
Features **Bluetooth (A2DP)** and **AirPlay (Shairport-Sync)** with seamless mixing, automatic network switching, and a **Read-Only Filesystem** that survives abrupt power cuts.

## Features

-   **Robust Power Handling**: Uses OverlayFS (Read-Only Root) to prevent SD card corruption when the car turns off.
-   **Universal Connectivity**:
    -   **Bluetooth 4.0+**: Auto-pairing, high-quality A2DP streaming.
    -   **AirPlay**: Lossless WiFi streaming for iOS devices.
    -   **Audio Mixing**: Intelligent `dmix` configuration allows simultaneous/mixed playback (no "resource busy" errors).
-   **Network Intelligence**:
    -   Connects to known Home WiFi when parked.
    -   Automatically broadcasts a **Hotspot (CarPlay-Pi)** when driving.
-   **Audiophile Ready**: Supports I2S DACs (PCM5102a, Hifiberry) and optimizes internal PWM audio gain.

## Hardware Requirements

-   **Raspberry Pi**: Pi 2, 3, 4, or Zero 2 W.
-   **MicroSD Card**: 8GB+ (Class 10 recommended).
-   **Bluetooth Dongle**: CSR 4.0 (Recommended for better range/driver support than onboard).
-   **Power Supply**: High-quality 5V USB Car Charger (2.4A+).
-   **Optional**: PCM5102a DAC or USB Sound Card (for better audio quality).

## File Structure

```
.
├── src/
│   ├── usr/local/bin/      # Startup scripts (bt-agent, volume-sync)
│   ├── etc/
│   │   ├── systemd/        # Service definitions (BlueALSA, Bluetooth overrides)
│   │   ├── NetworkManager/ # Dispatcher scripts for Hotspot switching
│   │   ├── asound.conf     # ALSA dmix mixer configuration
│   │   └── shairport-sync.conf
└── docs/
    └── architecture.md     # Detailed setup and architectural notes
```

## Installation

1.  **Flash OS**: Install **Raspberry Pi OS Lite** (Bookworm).
2.  **Copy Configs**:
    -   Copy contents of `src/etc` to `/etc`.
    -   Copy `src/usr/local/bin` to `/usr/local/bin`.
3.  **Install Dependencies**:
    ```bash
    sudo apt install git bluez-alsa-utils shairport-sync network-manager python3-dbus
    ```
4.  **Enable OverlayFS** (Crucial step for Car use):
    ```bash
    sudo raspi-config nonint enable_overlayfs
    ```
5.  **Reboot**: The system is now read-only and road-ready.

## License

MIT License. See [LICENSE](LICENSE) for details.
