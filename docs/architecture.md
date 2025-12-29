# **Technical Architecture for a Robust Automotive Audio Appliance: Implementation Strategy for Raspberry Pi 2**

## **1\. Executive Introduction: The Embedded Automotive Challenge**

The integration of consumer electronics into the automotive environment presents a unique convergence of constraints that distinguish it sharply from desktop or server computing. The objective of transforming a Raspberry Pi 2 into a high-fidelity, headless Bluetooth and WiFi audio receiver necessitates a rigorous architectural approach that prioritizes fault tolerance, signal integrity, and boot-time determinism. Unlike a home media server, a car audio appliance is subjected to "dirty" power—characterized by voltage sags during engine cranking and inductive spikes from the alternator—and, most critically, abrupt power termination when the ignition is cycled.

The user’s requirements specify a need for high bandwidth, multi-device concurrency (supporting both Bluetooth A2DP and WiFi streaming protocols like AirPlay or Spotify Connect), and absolute filesystem integrity without reliance on manual shutdown procedures. While the request suggests the use of the B-tree Filesystem (Btrfs) as a mechanism to prevent corruption, deep technical analysis suggests that while Btrfs offers data integrity verification, a read-only Overlay Filesystem (OverlayFS) architecture provides superior survivability for the specific vector of sudden power loss on SD card media.

Furthermore, the hardware limitations of the Raspberry Pi 2—specifically the shared bus architecture of the BCM2835 system-on-chip (SoC) and the localized electromagnetic interference (EMI) typical of its Pulse Width Modulation (PWM) audio output—require aggressive software mitigation strategies to achieve "high audio quality." This report delineates a comprehensive engineering plan to deploy a headless Linux audio stack using BlueALSA and ALSA mixing (dmix), bypassing the overhead of PulseAudio or PipeWire to maximize the limited resources of the ARM Cortex-A7 processor, ensuring a seamless, audiophile-grade experience in a hostile physical environment.

## **2\. Storage Subsystem and Data Integrity Analysis**

The primary failure mode for Raspberry Pi-based automotive projects is SD card corruption. Flash memory controllers in consumer SD cards utilize a Translation Layer (FTL) to manage wear leveling and block mapping. When power is cut during a write operation—whether it be a log file update, a swap partition write, or a metadata commit—the FTL can be left in an inconsistent state, rendering the card unbootable.

### **2.1. Theoretical Evaluation of Btrfs in Embedded Systems**

The user’s query explicitly considers Btrfs (B-tree Filesystem) as a solution for preventing corruption. Btrfs is a modern Copy-on-Write (CoW) filesystem that fundamentally alters how data is committed to disk.1 In traditional journaling filesystems like Ext4, metadata changes are recorded in a journal before being committed to the main filesystem, allowing for replay after a crash. However, standard journaling does not protect against data corruption within the file itself, nor does it solve the "write hole" phenomenon inherent in certain RAID configurations, though less relevant to single-disk setups.

Btrfs addresses this through CoW: data is never overwritten in place. When a file is modified, the new data is written to a free block, and the metadata pointers are updated to point to the new location only after the write is confirmed.1 This atomic update mechanism implies that the filesystem should always be in a consistent state; either the old version exists, or the new version exists, but never a corrupted hybrid. Additionally, Btrfs calculates checksums for data and metadata, allowing the system to detect silent data corruption upon reading.2

However, applying Btrfs to a Raspberry Pi 2 in a car reveals significant limitations. First, while Btrfs can *detect* corruption, it cannot *repair* it automatically on a single drive without a redundant copy (RAID 1), meaning a detected checksum error simply results in an I/O error, potentially crashing the audio application.1 Second, the "scrub" and "balance" maintenance operations required to keep Btrfs healthy are I/O intensive, potentially causing audio dropouts on the Pi 2’s limited bus bandwidth. Finally, while CoW protects filesystem structures, it does not prevent the SD card's internal controller from becoming corrupted if power is lost during an internal block erase cycle.

### **2.2. The Superiority of the OverlayFS Architecture**

For an appliance that functions as a "receiver"—where the state is static and no local music library requires persistent storage—the industry standard for maximizing reliability is the Overlay Filesystem (OverlayFS).3 This approach differs fundamentally from simply mounting a partition as read-only.

In a strict read-only mount (e.g., adding ro to /etc/fstab), applications that expect to write temporary data (like DHCP clients, Bluetooth pairing agents, or loggers) will crash or fail to start. OverlayFS solves this by stacking two filesystems:

1. **Lower Directory (Physical Media):** The SD card partition containing the OS is mounted read-only. This physically prevents the kernel from sending write commands to the flash controller, effectively neutralizing the risk of filesystem corruption caused by power cuts.5  
2. **Upper Directory (Volatile RAM):** A tmpfs RAM disk is created at boot.  
3. **Merged Directory:** The system presents a unified view to the OS. Writes are intercepted and stored in the RAM layer.

This architecture ensures that if power is cut, the "writes" (logs, temp files) simply vanish from RAM, while the underlying SD card remains in its pristine, uncorrupted state.7 This is statistically safer than Btrfs alone because it eliminates the electrical activity of writing to the card entirely during operation.

### **2.3. Partitioning Strategy for Bluetooth Persistence**

A purely read-only system presents a challenge for Bluetooth pairing. When a new phone pairs, the Bluetooth daemon (BlueZ) stores the link key in /var/lib/bluetooth. If this directory is in the volatile RAM layer of the OverlayFS, the pairing will be lost upon reboot, forcing the user to re-pair every time the car starts.8

To resolve this, we recommend a hybrid partitioning scheme:

| Partition ID | Filesystem | Mount Point | Attributes | Function |
| :---- | :---- | :---- | :---- | :---- |
| mmcblk0p1 | FAT32 | /boot | Read-Only | Stores kernel, bootloader, and hardware configuration. |
| mmcblk0p2 | Ext4/Btrfs | / (Root) | Read-Only (Overlay) | Contains the OS and immutable software stack. |
| mmcblk0p3 | Ext4 | /mnt/data | Read-Write (Noatime) | Small (e.g., 512MB) partition for persistent config. |

The directory /var/lib/bluetooth is then replaced with a symbolic link pointing to /mnt/data/bluetooth. This ensures that while the OS remains frozen and safe, the critical pairing keys are persisted to disk. Given that pairing events occur rarely (only when adding a new device), the window of vulnerability for corruption on this specific partition is negligible compared to the system logs and swap files that constantly thrash the disk in a standard setup.8

## **3\. Audio Subsystem Architecture**

The user requirement for "high audio quality" on a Raspberry Pi 2 presents a physical challenge. The onboard 3.5mm jack on the Pi 2 is driven by a Pulse Width Modulation (PWM) engine on the BCM2835 SoC, rather than a dedicated Digital-to-Analog Converter (DAC) chip. In its default configuration, this output is notorious for a high noise floor, audible hiss, and poor frequency response, particularly when powered by a noisy automotive 12V-to-5V converter.10

### **3.1. Firmware-Level Audio Optimization**

While an external I2S DAC HAT is the absolute gold standard for high fidelity 12, the audio quality of the onboard jack can be significantly improved through firmware reconfiguration. The standard driver uses a basic PWM algorithm that introduces quantization noise in the audible spectrum.

Research indicates that enabling the Sigma-Delta Modulator (SDM) significantly mitigates this. By adding the parameter audio\_pwm\_mode=2 to /boot/config.txt, the firmware switches to a noise-shaping algorithm that pushes quantization noise into higher frequencies, which are then attenuated by the board’s analog low-pass filter.13 This results in a cleaner signal with approximately 14-bit effective resolution, a vast improvement over the default 11-bit behavior. Additionally, setting disable\_audio\_dither=1 can prevent the constant low-level white noise (hiss) that occurs when the audio stream is idle but the amplifier is active.11

It is critical to note that without audio\_pwm\_mode=2, "high quality" is unattainable on the onboard jack. With it, the quality becomes "acceptable" for automotive use, though still inferior to a $15 external DAC.

### **3.2. The Backend Dilemma: PipeWire vs. BlueALSA**

Modern Linux audio distributions are converging on **PipeWire**, a low-latency multimedia server that unifies the capabilities of PulseAudio and JACK.16 PipeWire offers excellent support for Bluetooth A2DP codecs (LDAC, aptX HD) out of the box and handles routing graphs dynamically.

However, for a Raspberry Pi 2 (ARM Cortex-A7, 1GB RAM), the full PipeWire stack introduces significant overhead. The user reports and forums indicate that PipeWire on older Pi hardware can lead to high CPU usage and occasional audio dropouts ("xruns") when the system is under load, such as during concurrent WiFi scanning.17 Furthermore, PipeWire’s complexity makes it harder to debug in a headless "black box" appliance scenario.

**BlueALSA (BlueZ-ALSA)** is the recommended architectural choice for this project. BlueALSA is a purpose-built proxy that exposes Bluetooth audio connections directly as ALSA PCM devices, bypassing the need for a sound server like PulseAudio entirely.18

* **Efficiency:** BlueALSA operates with minimal CPU overhead, crucial for the Pi 2\.  
* **Stability:** It is a mature, "set-it-and-forget-it" solution widely used in embedded audio distributions.8  
* **Direct Control:** It allows direct manipulation of the ALSA buffer parameters, enabling precise latency tuning that is often abstracted away in PulseAudio.

### **3.3. Mixing Architecture: The ALSA dmix Plugin**

A critical requirement is the support for "multiple devices" and concurrent streaming. In a standard ALSA configuration, the hardware device (hw:0,0) is strictly exclusive. If the Bluetooth daemon locks the hardware to play audio, the AirPlay daemon (Shairport-Sync) will fail to start playback, throwing a "Device or resource busy" error.19

To satisfy the user's need for seamless switching between Spotify (WiFi) and Phone Audio (Bluetooth), we must implement a software mixer. The ALSA **dmix (Direct Mixing)** plugin performs this function at the kernel level.19

The architecture requires defining a virtual PCM device in /etc/asound.conf that utilizes the dmix plugin. Both Shairport-Sync and BlueALSA are then configured to output audio to this plug:dmix virtual device rather than the hardware directly. The dmix plugin handles the summation of sample streams, sample rate conversion (if the sources differ, e.g., 44.1kHz vs 48kHz), and buffer management.22

Latency Considerations:  
The use of dmix introduces a buffer. For video synchronization this could be problematic, but for audio streaming, it is beneficial as it provides protection against underruns. We recommend configuring a period\_time of 100,000 microseconds in the dmix definition to ensure stability over the WiFi/Bluetooth radio links, which may experience transient packet loss.23

## **4\. Network Connectivity and Automation Strategy**

In a vehicle, network conditions are highly variable. The Pi cannot rely on a static home router. It must function as a client (Station Mode) when parked near the home for updates, but transition to a Host (Access Point Mode) or connect to a phone's Hotspot while mobile.

### **4.1. NetworkManager for Dynamic Switching**

Raspberry Pi OS Bookworm utilizes **NetworkManager** (NM) as the default network controller, replacing the older dhcpcd.24 NM is ideally suited for this automotive use case because it supports connection priority and auto-connect logic natively.

We define two primary connection profiles:

1. **Home\_WiFi (Priority 100):** Configured to connect to the user's home network. High priority ensures that if the car is in the driveway, the Pi connects to the home LAN, allowing the user to SSH in for maintenance or file transfers.25  
2. **Car\_Hotspot (Priority 50):** A profile where the Pi acts as an Access Point (AP) or connects to the user's phone hotspot.

However, standard WiFi interfaces cannot operate as both a Client and an AP simultaneously on the Pi's hardware without significant instability (virtual interfaces like uap0 often conflict with scanning).27 Therefore, the system must perform a "failover" transition.

### **4.2. Automating Fallback with Dispatcher Scripts**

To automate the transition without user intervention, we utilize NetworkManager's **Dispatcher Script** functionality. Scripts placed in /etc/NetworkManager/dispatcher.d/ are executed automatically upon network events (e.g., interface UP/DOWN).29

**The Failover Logic:**

1. **Boot Phase:** NetworkManager attempts to connect to "Home\_WiFi" (Priority 100).  
2. **Timeout:** If the home network is absent, the connection fails.  
3. **Dispatcher Trigger:** A script (e.g., 10-autohotspot) detects the failure state or the lack of an active connection on wlan0.  
4. **Action:** The script issues the command nmcli connection up Car\_AP, forcing the Pi to broadcast its own SSID.  
5. **Reversion:** Periodically, or via a manual trigger (GPIO button), the system can scan for the home network and revert if available.30

This ensures that in the driveway, the Pi is a network citizen; on the road, it is the network master, allowing the phone to connect for AirPlay streaming.

## **5\. Bluetooth Implementation and User Experience**

### **5.1. Pairing and Discovery Mechanics**

Headless pairing is a common stumbling block. The BlueZ stack requires a "Agent" to handle PIN negotiation. For a car receiver, we require a "NoInputNoOutput" agent capability, allowing the phone to simply click "Connect" without the Pi needing to confirm a code.

This is achieved by running a Python script or a systemd service that registers a BlueZ Agent with capability \= "NoInputNoOutput". Additionally, to prevent unauthorized connections while driving, the "Discoverable" mode should not be perpetually on. A suggested enhancement is to use a GPIO pin connected to a dashboard button; pressing the button triggers a script that runs bluetoothctl discoverable on for 60 seconds, enabling pairing for a new passenger.8

### **5.2. AVRCP Volume Synchronization**

A critical "high quality" experience factor is volume control. Users expect their phone's volume buttons to control the car audio volume. This requires the **Audio/Video Remote Control Profile (AVRCP)**.

Standard bluealsa-aplay maps the incoming Bluetooth audio to the ALSA mixer. By using the \--a2dp-volume flag, BlueALSA intercepts AVRCP volume commands from the phone and applies them to the Raspberry Pi's hardware mixer (the PCM or Headphone control).32

However, a mapping issue exists: Bluetooth volume is 0-127 (linear), while ALSA dB scales are logarithmic. Simply passing the value can result in volume jumping from silent to extremely loud. BlueALSA handles this mapping, but the specific mixer control must be specified (e.g., \--mixer-name=PCM) to ensure the synchronization aligns with the specific gain curve of the Pi's audio output.32

## **6\. Comprehensive Implementation Plan**

This section details the step-by-step execution plan to build the appliance, synthesizing the filesystem, audio, and network components analyzed above.

### **Phase 1: System Hardening and Filesystem Prep**

1. **OS Installation:** Flash **Raspberry Pi OS Lite (Bookworm)**. The "Lite" version is mandatory to avoid the overhead of the X11 desktop environment/Wayland.18  
2. **Dependencies:** Install git, bluez-alsa-utils, shairport-sync, network-manager, and python3-dbus.34  
3. **Boot Config:**  
   * Edit /boot/firmware/config.txt: Add audio\_pwm\_mode=2 and disable\_audio\_dither=1.  
   * Disable onboard WiFi power saving to prevent AirPlay stuttering: dtoverlay=disable-wifi-pwr.  
4. **Partitioning:** Use gparted (on a separate PC) or fdisk to resize the root partition and create a 512MB ext4 partition labeled DATA at the end of the SD card.  
5. **Persistence Setup:**  
   * Mount the DATA partition to /mnt/data via /etc/fstab.  
   * Stop Bluetooth: systemctl stop bluetooth.  
   * Move /var/lib/bluetooth to /mnt/data/bluetooth.  
   * Symlink back: ln \-s /mnt/data/bluetooth /var/lib/bluetooth.

### **Phase 2: Audio Stack Configuration**

1. **ALSA Configuration:** Create /etc/asound.conf. Define a dmix slave with ipc\_key 1024 and period\_time 0 (letting driver choose) or 100000 for stability. Define a plug device named softvol to allow software volume control if the hardware mixer is insufficient.20  
2. **BlueALSA Service:**  
   * Create a systemd override or new service bluealsa-aplay.service.  
   * Command: /usr/bin/bluealsa-aplay \--profile-a2dp \--pcm-buffer-time=200000 \--mixer-name=PCM \--a2dp-volume.  
   * The buffer time of 200ms (200000) is crucial to absorb Bluetooth jitter in the automotive 2.4GHz spectrum.23  
3. **Shairport-Sync (AirPlay):**  
   * Edit /etc/shairport-sync.conf.  
   * Set backend to alsa.  
   * Set output\_device to default (which routes to dmix).  
   * Enable drift\_tolerance\_in\_seconds \= 0.002 to allow tighter sync with the phone.35

### **Phase 3: Network Automation**

1. **Profiles:** Use nmcli to define the Home connection (Priority 100\) and the Hotspot connection (Priority 50).  
2. **Dispatcher:** Write the script /etc/NetworkManager/dispatcher.d/99-autohotspot.  
   * Logic: IF wlan0 DOWN AND Home\_SSID NOT VISIBLE THEN nmcli con up Hotspot.  
   * Ensure the script is executable (chmod \+x) and owned by root.31

### **Phase 4: Finalizing the Appliance**

1. **OverlayFS Activation:**  
   * Use raspi-config command-line interface: sudo raspi-config nonint enable\_overlayfs.7  
   * Reboot.  
   * Verify: Run mount. The root / should be of type overlay.  
2. **Testing:**  
   * Power off via plug pull (simulate ignition cut).  
   * Power on. Verify Bluetooth keys persist (phone auto-reconnects).  
   * Verify audio works immediately.

## **7\. LLM Prompts for Configuration Generation**

The following prompts are designed to be fed into an LLM to generate the precise, syntax-perfect configuration files required for this architecture.

### **7.1. Prompt for asound.conf (The Mixer)**

"Generate a robust /etc/asound.conf file for a Raspberry Pi 2 running Debian Bookworm. The goal is to allow bluealsa (Bluetooth) and shairport-sync (AirPlay) to play audio simultaneously to the headphone jack (hw:0) using the dmix plugin.  
Requirements:

1. Define a pcm.dmixed slave using type dmix. Use ipc\_key 1024\. Set period\_time 0 and period\_size 1024\.  
2. Set the rate to 44100 to match AirPlay natively.  
3. Define a pcm.\!default device of type plug that points to the dmixed slave.  
4. Include a ctl.\!default block pointing to hw:0 so mixer commands work.  
5. Add comments explaining what ipc\_key does."

### **7.2. Prompt for NetworkManager Dispatcher Script**

"Write a bash script for /etc/NetworkManager/dispatcher.d/autohotspot for a Raspberry Pi.  
Context:  
The Pi has two NetworkManager connections: 'HomeWiFi' (client) and 'CarAP' (hotspot).  
Logic:

1. The script captures the interface name ($1) and action ($2).  
2. If the interface is wlan0 and the action is down (disconnected), scan for 'HomeWiFi'.  
3. If 'HomeWiFi' is not found, execute nmcli connection up CarAP.  
4. If the action is up and the connection is 'HomeWiFi', ensure 'CarAP' is down.  
   Style:  
   Use defensive bash programming (check for command existence). Add logging to /var/log/autohotspot.log so I can debug it."

### **7.3. Prompt for BlueALSA Systemd Unit**

"Create a systemd service file bluealsa-aplay.service to automatically route Bluetooth audio to ALSA.  
Requirements:

1. \[Unit\]: Requires bluetooth.service and bluealsa.service. After sound.target.  
2. \`\`: Restart on failure with a 5-second delay.  
3. ExecStart: Run /usr/bin/bluealsa-aplay.  
4. Flags:  
   * \--profile-a2dp (Audio only).  
   * \--pcm-buffer-time=250000 (High latency buffer for stability).  
   * \--mixer-name=PCM (Control the Pi's master volume).  
   * \--a2dp-volume (Sync phone volume).  
   * 00:00:00:00:00:00 (Listen to all MAC addresses).  
5. User: Run as root (required for system-wide ALSA access in headless mode)."

## **8\. Hardware and Electrical Considerations**

### **8.1. Power Management and Voltage Sag**

The Raspberry Pi 2 is sensitive to undervoltage. The "Lightning Bolt" icon (or kernel warnings in logs) indicates input voltage dropping below 4.63V. In a car, engine cranking can drop the 12V rail to 8V or lower.  
Requirement: Use a high-quality "Buck Converter" (Step-Down) regulator rated for 12V to 5.1V at 3A. Avoid generic cigarette lighter USB adapters, which often lack the capacitance to handle the millisecond-long voltage drops associated with bass hits in the audio system or starter motor engagement.37

### **8.2. Ground Loop Isolation**

Connecting the Pi's 3.5mm jack to the car's AUX input while both utilize the car's common chassis ground creates a ground loop. This manifests as a high-pitched "alternator whine" that varies with engine RPM.  
Solution: A Ground Loop Noise Isolator is mandatory. This passive device uses a 1:1 isolation transformer to decouple the DC grounds while passing the AC audio signal. It should be placed inline between the Pi and the car's AUX port. Note that this may slightly attenuate sub-bass frequencies (\<40Hz), but the trade-off for eliminating alternator whine is necessary.11

### **8.3. Safe Shutdown vs. Power Cut**

While OverlayFS protects the filesystem, abrupt power cuts prevent the "graceful" saving of state (e.g., last played track, volume level). If this feature is desired, the user must install a hardware **UPS HAT** (like the StromPi or a basic supercapacitor circuit) that triggers a GPIO interrupt upon detecting ignition loss, initiating a shutdown \-h now script. However, for a purely streaming receiver, the OverlayFS approach negates the *necessity* of this for survival, making it a "nice to have" rather than a requirement.1

## **9\. Conclusion**

The transformation of a Raspberry Pi 2 into an automotive audio appliance is a multidimensional engineering challenge that extends beyond simple software installation. It requires a holistic view of the storage layer (OverlayFS), the audio pipeline (BlueALSA \+ dmix \+ Firmware Optimization), and network logic (NetworkManager Dispatchers).

By rejecting Btrfs in favor of a strictly read-only OverlayFS root with a persistent data partition, we achieve a system that is statistically immune to power-cut corruption. By optimizing the specific PWM firmware parameters of the BCM2835 and utilizing the lightweight BlueALSA stack, we extract the maximum possible fidelity from the legacy hardware without overloading the CPU. This architecture delivers a robust, "invisible" receiver that integrates seamlessly with modern mobile devices while surviving the harsh reality of the automotive electrical environment.

#### **Works cited**

1. Is Btrfs 6.6 or 6.8 almost 100% robust against power outages? \- Reddit, accessed December 29, 2025, [https://www.reddit.com/r/btrfs/comments/1bq32oz/is\_btrfs\_66\_or\_68\_almost\_100\_robust\_against\_power/](https://www.reddit.com/r/btrfs/comments/1bq32oz/is_btrfs_66_or_68_almost_100_robust_against_power/)  
2. btrfs on a Raspberry Pi \- The Changelog, accessed December 29, 2025, [https://changelog.complete.org/archives/10852-btrfs-on-a-raspberry-pi](https://changelog.complete.org/archives/10852-btrfs-on-a-raspberry-pi)  
3. Running a Raspberry Pi with a read-only root filesystem, accessed December 29, 2025, [https://news.ycombinator.com/item?id=39869614](https://news.ycombinator.com/item?id=39869614)  
4. Read-only root filesystem for Raspbian Stretch (using overlay), accessed December 29, 2025, [https://github.com/JasperE84/root-ro](https://github.com/JasperE84/root-ro)  
5. Protect your Raspberry PI SD card, use Read-Only filesystem, accessed December 29, 2025, [https://hallard.me/raspberry-pi-read-only/](https://hallard.me/raspberry-pi-read-only/)  
6. Read-Only Raspberry Pi | Adafruit Learning System, accessed December 29, 2025, [https://learn.adafruit.com/read-only-raspberry-pi/overview](https://learn.adafruit.com/read-only-raspberry-pi/overview)  
7. Enable/disable OverlayFS from shell \- Raspberry Pi Forums, accessed December 29, 2025, [https://forums.raspberrypi.com/viewtopic.php?t=279530](https://forums.raspberrypi.com/viewtopic.php?t=279530)  
8. bablokb/pi-btaudio: Bluetooth Audio for headless Raspbian systems, accessed December 29, 2025, [https://github.com/bablokb/pi-btaudio](https://github.com/bablokb/pi-btaudio)  
9. Running a Raspberry Pi with a read-only root filesystem, accessed December 29, 2025, [https://www.dzombak.com/blog/2024/03/running-a-raspberry-pi-with-a-read-only-root-filesystem/](https://www.dzombak.com/blog/2024/03/running-a-raspberry-pi-with-a-read-only-root-filesystem/)  
10. Using a Raspberry Pi as a Bluetooth speaker with PipeWire \- Reddit, accessed December 29, 2025, [https://www.reddit.com/r/linux/comments/x43rrv/using\_a\_raspberry\_pi\_as\_a\_bluetooth\_speaker\_with/](https://www.reddit.com/r/linux/comments/x43rrv/using_a_raspberry_pi_as_a_bluetooth_speaker_with/)  
11. Audio HISS: disable\_audio\_dither or audio\_pwm\_mode???, accessed December 29, 2025, [https://forums.raspberrypi.com/viewtopic.php?t=202961](https://forums.raspberrypi.com/viewtopic.php?t=202961)  
12. Quality Audio for the Raspberry Pi on the cheap, accessed December 29, 2025, [http://raspberrypimaker.com/cheap-quality-audio-raspberry-pi/](http://raspberrypimaker.com/cheap-quality-audio-raspberry-pi/)  
13. Behind The Pin: How The Raspberry Pi Gets Its Audio | Hackaday, accessed December 29, 2025, [https://hackaday.com/2018/07/13/behind-the-pin-how-the-raspberry-pi-gets-its-audio/](https://hackaday.com/2018/07/13/behind-the-pin-how-the-raspberry-pi-gets-its-audio/)  
14. Audio output "hiss" when should be silent · Issue \#380 \- GitHub, accessed December 29, 2025, [https://github.com/raspberrypi/firmware/issues/380](https://github.com/raspberrypi/firmware/issues/380)  
15. Fixing the annoying static noise from my Raspberry Pi's 3.5mm jack, accessed December 29, 2025, [https://ritiek.github.io/2018/12/17/fixing-the-annoying-static-noise-from-my-raspberry-pis-3.5mm-jack/](https://ritiek.github.io/2018/12/17/fixing-the-annoying-static-noise-from-my-raspberry-pis-3.5mm-jack/)  
16. alsa vs pulseaudio vs jack vs pipewire : r/linuxaudio \- Reddit, accessed December 29, 2025, [https://www.reddit.com/r/linuxaudio/comments/1jkvwb6/alsa\_vs\_pulseaudio\_vs\_jack\_vs\_pipewire/](https://www.reddit.com/r/linuxaudio/comments/1jkvwb6/alsa_vs_pulseaudio_vs_jack_vs_pipewire/)  
17. SOLVED: Pipewire vs ALSA on AVLinux \- LinuxMusicians, accessed December 29, 2025, [https://linuxmusicians.com/viewtopic.php?t=28119](https://linuxmusicians.com/viewtopic.php?t=28119)  
18. Bluetooth audio on a headless Raspberry Pi using BlueAlsa, accessed December 29, 2025, [https://introt.github.io/docs/raspberrypi/bluealsa.html](https://introt.github.io/docs/raspberrypi/bluealsa.html)  
19. Shairport / Mopidy "Hand off" audio? how to switch from one to the ..., accessed December 29, 2025, [https://discourse.mopidy.com/t/shairport-mopidy-hand-off-audio-how-to-switch-from-one-to-the-other/5301](https://discourse.mopidy.com/t/shairport-mopidy-hand-off-audio-how-to-switch-from-one-to-the-other/5301)  
20. Mix bluetooth audio with local audio \- Toradex Community, accessed December 29, 2025, [https://community.toradex.com/t/mix-bluetooth-audio-with-local-audio/20343](https://community.toradex.com/t/mix-bluetooth-audio-with-local-audio/20343)  
21. \[SOLVED\] Alsa \- problem with mixing (dmix) multiple audio sources, accessed December 29, 2025, [https://bbs.archlinux.org/viewtopic.php?id=229286](https://bbs.archlinux.org/viewtopic.php?id=229286)  
22. ALSA Api: How to play two wave files simultaneously?, accessed December 29, 2025, [https://stackoverflow.com/questions/14398573/alsa-api-how-to-play-two-wave-files-simultaneously](https://stackoverflow.com/questions/14398573/alsa-api-how-to-play-two-wave-files-simultaneously)  
23. bluealsa-aplay(1) — bluez-alsa-utils — Debian testing, accessed December 29, 2025, [https://manpages.debian.org/testing/bluez-alsa-utils/bluealsa-aplay.1.en.html](https://manpages.debian.org/testing/bluez-alsa-utils/bluealsa-aplay.1.en.html)  
24. Raspberry Pi as an Access Point | The Maker Medic, accessed December 29, 2025, [https://themakermedic.com/posts/Pi-AP-Mode/](https://themakermedic.com/posts/Pi-AP-Mode/)  
25. Create a Wifi Hotspot on Raspberry Pi with NetworkManager · GitHub, accessed December 29, 2025, [https://gist.github.com/max-pfeiffer/9e8e76d190698cc8381b75399c1ded1d](https://gist.github.com/max-pfeiffer/9e8e76d190698cc8381b75399c1ded1d)  
26. How to manage available wireless network priority? \- Ask Ubuntu, accessed December 29, 2025, [https://askubuntu.com/questions/165679/how-to-manage-available-wireless-network-priority](https://askubuntu.com/questions/165679/how-to-manage-available-wireless-network-priority)  
27. Setting up a Wifi hotspot on a Raspberry Pi 3, turn off AP mode when ..., accessed December 29, 2025, [https://forum.snapcraft.io/t/setting-up-a-wifi-hotspot-on-a-raspberry-pi-3-turn-off-ap-mode-when-connected-to-home-network/6510](https://forum.snapcraft.io/t/setting-up-a-wifi-hotspot-on-a-raspberry-pi-3-turn-off-ap-mode-when-connected-to-home-network/6510)  
28. NetworkManager error in raspberry using Dispatcher.d events, accessed December 29, 2025, [https://unix.stackexchange.com/questions/799177/networkmanager-error-in-raspberry-using-dispatcher-d-events](https://unix.stackexchange.com/questions/799177/networkmanager-error-in-raspberry-using-dispatcher-d-events)  
29. NetworkManager-dispatcher, accessed December 29, 2025, [https://networkmanager.dev/docs/api/1.42.4/NetworkManager-dispatcher.html](https://networkmanager.dev/docs/api/1.42.4/NetworkManager-dispatcher.html)  
30. Raspberry Pi \- Auto WiFi Hotspot Switch ... \- Raspberry Connect, accessed December 29, 2025, [https://www.raspberryconnect.com/projects/65-raspberrypi-hotspot-accesspoints/158-raspberry-pi-auto-wifi-hotspot-switch-direct-connection](https://www.raspberryconnect.com/projects/65-raspberrypi-hotspot-accesspoints/158-raspberry-pi-auto-wifi-hotspot-switch-direct-connection)  
31. NetworkManager dispatcher script / wireguard / Newbie Corner ..., accessed December 29, 2025, [https://bbs.archlinux.org/viewtopic.php?id=272204](https://bbs.archlinux.org/viewtopic.php?id=272204)  
32. Max Volume output is Approx 50% of max volume from other devices, accessed December 29, 2025, [https://github.com/arkq/bluez-alsa/issues/515](https://github.com/arkq/bluez-alsa/issues/515)  
33. AVRCP Volume Control \- ESP32 Forum, accessed December 29, 2025, [https://esp32.com/viewtopic.php?t=13112](https://esp32.com/viewtopic.php?t=13112)  
34. Debian \-- Details of package bluez-alsa-utils in bookworm, accessed December 29, 2025, [https://packages.debian.org/bookworm/bluez-alsa-utils](https://packages.debian.org/bookworm/bluez-alsa-utils)  
35. Shairport-sync issues \- Raspberry Pi Forums, accessed December 29, 2025, [https://forums.raspberrypi.com/viewtopic.php?t=181723](https://forums.raspberrypi.com/viewtopic.php?t=181723)  
36. How to share Internet connection with WiFi hotspot \- \#7 by Loki, accessed December 29, 2025, [https://forums.puri.sm/t/tutorial-script-how-to-share-internet-connection-with-wifi-hotspot/13219/7?u=fralb5](https://forums.puri.sm/t/tutorial-script-how-to-share-internet-connection-with-wifi-hotspot/13219/7?u=fralb5)  
37. How to make RaspberryPi truly read-only, reliable and trouble-free, accessed December 29, 2025, [https://k3a.me/how-to-make-raspberrypi-truly-read-only-reliable-and-trouble-free/](https://k3a.me/how-to-make-raspberrypi-truly-read-only-reliable-and-trouble-free/)