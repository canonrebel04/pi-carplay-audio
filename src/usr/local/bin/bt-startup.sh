#!/bin/bash
sleep 5
bluetoothctl power on
bluetoothctl discoverable on
bluetoothctl pairable on
amixer set PCM 85%
