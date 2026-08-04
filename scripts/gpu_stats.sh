#!/bin/bash

# Simple GPU stats script
# Tries to detect NVIDIA, then AMD, then Intel.

if command -v nvidia-smi &> /dev/null; then
    # NVIDIA
    usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
    temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
    echo "{\"text\": \"$usage%  $temp°C\", \"tooltip\": \"NVIDIA GPU\"}"
elif [ -f "/sys/class/drm/card1/device/gpu_busy_percent" ]; then
    # AMD (newer kernels) - Card 1
    usage=$(cat /sys/class/drm/card1/device/gpu_busy_percent)
    echo "{\"text\": \"$usage%\", \"tooltip\": \"AMD GPU (card1)\"}"
elif [ -f "/sys/class/drm/card0/device/gpu_busy_percent" ]; then
    # AMD (newer kernels) - Card 0 fallback
    usage=$(cat /sys/class/drm/card0/device/gpu_busy_percent)
    echo "{\"text\": \"$usage%\", \"tooltip\": \"AMD GPU (card0)\"}"
elif command -v intel_gpu_top &> /dev/null; then
    # Intel (requires permissions, usually not easy to read without sudo)
    # Placeholder
    echo "{\"text\": \"Intel\", \"tooltip\": \"Intel GPU (install intel-gpu-tools)\"}"
else
    echo "{\"text\": \"GPU?\", \"tooltip\": \"No GPU stats available\"}"
fi
