#!/bin/bash
# Oni.sh
# Oni by Bungie for Portmaster
#
# Runtime output logged to $GAMEDIR/oni.log

# Get control and device info
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
source $controlfolder/device_info.txt

# armhf PipeWire client plumbing
if [[ "$CFW_NAME" = "mu"* ]]; then
    export SPA_PLUGIN_DIR=/usr/lib32/spa-0.2
    export PIPEWIRE_MODULE_DIR=/usr/lib32/pipewire-0.3
    export ALSA_PLUGIN_DIR=/usr/lib32/alsa-lib
fi

export PORT_32BIT=Y
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

# If for some reason portmaster functions failed to import, create overrides
if ! declare -F pm_message >/dev/null; then
    pm_message() {
        echo "$@"
    }
fi
if ! declare -F pm_show_error >/dev/null; then
    pm_show_error() {
        echo "$@"
    }
fi
if ! declare -F PortMasterDialogExit >/dev/null; then
    PortMasterDialogExit() {
        echo -n
    }
fi

__missing_reqs() {
    for i in "$@"; do
        [[ "$0" != "$i" ]] && __no_req "$i" && echo "$i is required to perform this function." && return 0
    done
    return 1
}

__no_req() {
    return $([[ "$(type $1 2>/dev/null)" == '' ]])
}

http_get() {
    if ! __missing_reqs "curl" "tee"; then
        curl -fsSL "$1" | tee "$2" >/dev/null
        { ! [ -f "$2" ] || [[ $(cat "$2" 2>/dev/null) == '' ]]; } && return 1
        return 0
    else
        if ! __no_req "wget"; then
            wget "$1" -O "$2"
            { ! [ -f "$2" ] || [[ $(cat "$2" 2>/dev/null) == '' ]]; } && return 1
            return 0
            fi
    fi
    pm_show_error "curl or wget is required to perform this function." && return 1
}

get_bin() {
    pm_message "Downloading Oni binary"
    http_get "https://github.com/Cronocide/oni-armhf/releases/download/v1.1/oni" "$GAMEDIR/oni"
    if [ $? -ne 0 ]; then
        pm_message "Failed to download Oni binary"
        return 1
    else
        pm_message "Downloaded Oni binary"
    fi
}

get_gl4es() {
    pm_message "Downloading missing gl4es"
    [ ! -d "$GAMEDIR/gl4es.armhf/" ] && mkdir -p "$GAMEDIR/gl4es.armhf/"
    http_get "https://github.com/Cronocide/oni-pm/raw/refs/heads/trunk/oni/gl4es.armhf/libGL.so.1" "$GAMEDIR/gl4es.armhf/libGL.so.1"
    if [ $? -ne 0 ]; then
        pm_message "Failed to download missing gl4es. Please reinstall the port"
        return 1
    else
        pm_message "Downloaded missing gl4es"
    fi
}

check_gamedir() {
    [ ! -d "$GAMEDIR/GameDataFolder" ] && return 1
    return 0
}

set_controls() {
    pm_message "Configuring default controls..."
    cat <<EOF > "$CONTROLS_MAP" || { pm_message "Unable to write $CONTROLS_MAP"; return 1; }
# Oni gptokeyb config

# D-pad as arrow keys
up = w
down = s
left = a
right = d

# Face buttons
a = c
b = mouse_left
x = leftctrl
y = space
a_hk =
b_hk =
x_hk = tab
y_hk = e

# Shoulder buttons
l1 = q
r1 = leftshift
l2 = f1
r2 = leftalt

# Menu buttons
back = esc
start = enter

# Left analog stick as mouse
right_analog_up = mouse_movement_up
right_analog_down = mouse_movement_down
right_analog_left = mouse_movement_left
right_analog_right = mouse_movement_right

# Mouse clicks via analog stick buttons
l3 = shiftleft
r3 = shiftleft

# Mouse and deadzone tuning
deadzone_mode = scaled_radial
deadzone = 1000
deadzone_scale = 8
deadzone_delay = 16
mouse_scale = 8192
EOF
}

install_port() {
    check_gamedir || { pm_show_error "Missing GameDataFolder; please copy to $GAMEDIR from an existing Oni installation"; return 1; }
    if [ ! -f "$GAMEDIR/oni" ] || [ -d "$GAMEDIR/oni" ]; then
        get_bin || { pm_show_error "Unable to download Oni binary from https://github.com/Cronocide/oni-armhf"; return 1; }
    fi
    if [ ! -s "$GAMEDIR/gl4es.armhf/libGL.so.1" ]; then
        get_gl4es || { pm_show_error "Missing $GAMEDIR/gl4es.armhf/libGL.so.1 and unable to download it. Please reinstall the port."; return 1; }
    fi
    if [ ! -s "$CONTROLS_MAP" ]; then
        set_controls || { pm_show_error "Please create a .gptk file at $CONTROLS_MAP"; return 1; }
    fi
}

# Find gamedir since testers extract Github source repo as 'oni-pm-trunk'
GAMEDIR="/$directory/ports/oni"
if [ ! -d "$GAMEDIR" ]; then
    GAMEDIR=$(realpath "$GAMEDIR"*)
    [ -f "$GAMEDIR/oni/port.json" ] && GAMEDIR="$GAMEDIR/oni"
    if [ ! -d "$GAMEDIR" ]; then
        pm_message "Unable to find port directory "$GAMEDIR", please name it 'oni' in your ports folder." && exit 1
    fi
fi

# Set drive and rom path defaults
export LD_LIBRARY_PATH="$GAMEDIR/gl4es.armhf:/usr/lib32:/usr/lib/arm-linux-gnueabihf:/lib/arm-linux-gnueabihf:/usr/lib/mali:/usr/lib:/lib:$LD_LIBRARY_PATH"
LOGFILE="$GAMEDIR/oni.log"

# perf: visibility ray-grid override (NxN rays/frame; engine default 16-20)
export ONI_RAYS=16
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export CONTROLS_MAP="$GAMEDIR/controls.gptk"

export LOGFILE="$GAMEDIR/oni.log"

cd $GAMEDIR

# Configure GL4ES
if [ -f "${controlfolder}/libgl_${CFW_NAME}.txt" ]; then 
  source "${controlfolder}/libgl_${CFW_NAME}.txt"
else
  source "${controlfolder}/libgl_default.txt"
fi

echo > "$LOGFILE"
echo "=== Oni starting at $(date) ===" >> "$LOGFILE"

# Verify or begin installation
install_port || { pm_message "Exiting"; exit 1; }

PortMasterDialogExit

# Start gptokeyb
$ESUDO chmod 666 /dev/uinput
$GPTOKEYB "oni" -c "$CONTROLS_MAP" &

pm_platform_helper oni 
./oni >> "$LOGFILE" 2>&1
EXIT_CODE=$?

echo "=== Oni exited with code $EXIT_CODE at $(date) ===" >> "$LOGFILE"

pm_finish
printf "\033c" > /dev/tty0
