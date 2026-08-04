#!/bin/bash

# Get current profile
current=$(powerprofilesctl get)

# Cycle to next profile
case $current in
    performance)
        next="balanced"
        icon=""
        text="Balanced"
        ;;
    balanced)
        next="power-saver"
        icon=""
        text="Power Saver"
        ;;
    power-saver)
        next="performance"
        icon=""
        text="Performance"
        ;;
    *)
        next="balanced"
        icon=""
        text="Balanced"
        ;;
esac

# If an argument is passed, switch to the next profile
if [ "$1" == "switch" ]; then
    powerprofilesctl set $next
    # Update variables for the new state
    current=$next
    case $current in
        performance)
            icon=""
            text="Performance"
            ;;
        balanced)
            icon=""
            text="Balanced"
            ;;
        power-saver)
            icon=""
            text="Power Saver"
            ;;
    esac
fi

# Output JSON for Waybar
echo "{\"text\": \"$text\", \"alt\": \"$current\", \"tooltip\": \"Current Profile: $text\", \"class\": \"$current\", \"percentage\": 100 }"
