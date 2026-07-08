#!/bin/bash
# Oni.sh
# Oni by Bungie for Portmaster
#
# All output logged to $GAMEDIR/oni.log

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
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

# Set drive and rom path defaults
GAMEDIR="/$directory/ports/oni"
LOGFILE="$GAMEDIR/oni.log"
export LD_LIBRARY_PATH="$GAMEDIR/gl4es.armhf:/usr/lib32:$LD_LIBRARY_PATH"
export LIBGL_ES=2 LIBGL_GL=21 LIBGL_FB=3
echo "$LD_LIBRARY_PATH" >> "$LOGFILE"

# Configure GL4ES
export ONI_GLES=1
export LIBGL_ES=2
export LIBGL_GL=21
export LIBGL_LOGSHADERERROR=1
export LIBGL_NOHIGHP=1
export LIBGL_NOPSA=1
export LIBGL_FBOMAKECURRENT=0
export LIBGL_FBOUNBIND=0

# Configure gptokeyb
export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"
export SDL_AUDIODRIVER=alsa

# armhf PipeWire client plumbing (the 32-bit ALSA default routes via PipeWire;
# the baked plugin paths point at the aarch64 dirs, so override them)
export XDG_RUNTIME_DIR=/run
export SPA_PLUGIN_DIR=/usr/lib32/spa-0.2
export PIPEWIRE_MODULE_DIR=/usr/lib32/pipewire-0.3
export ALSA_PLUGIN_DIR=/usr/lib32/alsa-lib

# perf: visibility ray-grid override (NxN rays/frame; engine default 16-20)
export ONI_RAYS=16
export SDL_VIDEODRIVER=mali
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export CONTROLS_MAP="$GAMEDIR/controls.gptk"

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

get_bin() {
  pm_message "Downloading Oni binary"
  wget "https://github.com/Cronocide/oni-armhf/releases/download/v1.1/oni" -O "$GAMEDIR/oni"
  if [ $? -ne 0 ]; then
    pm_message "Failed to download Oni binary"
    return 1
  else
    pm_message "Downloaded Oni binary"
  fi
}

check_gamedir() {
  [ ! -d "$GAMEDIR/GameDataFolder" ] && return 1
  return 0
}

set_controls() {
  pm_message "Configuring default controls..."
  [ ! -d $(dirname "$CONTROLS_MAP") ] && mkdir -p $(dirname "$CONTROLS_MAP")
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
  if [ ! -s "$GAMEDIR/oni" ]; then
    get_bin || { pm_show_error "Unable to download Oni binary from https://github.com/Cronocide/oni-armhf"; return 1; }
  fi
  if [ ! -s "$CONTROLS_MAP" ]; then
    set_controls || { pm_show_error "Please create a .gptk file at $CONTROLS_MAP"; return 1; }
  fi
}

cd $GAMEDIR

echo > "$LOGFILE"
echo "=== Oni starting at $(date) ===" >> "$LOGFILE"
free -m >> "$LOGFILE" 2>&1
echo "===" >> "$LOGFILE"

# Record CPU governor setting and restore on exit
GOVERNOR_SETTING=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
echo "performance" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Verify or being installation
install_port || { pm_message "Exiting"; exit 1; }

PortMasterDialogExit

# Start gptokeyb
$ESUDO chmod 666 /dev/uinput
$GPTOKEYB "oni" -c "$CONTROLS_MAP" &

nice -n -10 ./oni >> "$LOGFILE" 2>&1 &
ONI_PID=$!

wait $ONI_PID 2>/dev/null
EXIT_CODE=$?


echo "=== Oni exited with code $EXIT_CODE at $(date) ===" >> "$LOGFILE"
echo "$GOVERNOR_SETTING" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

$ESUDO kill -9 $(pidof gptokeyb)
$ESUDO systemctl restart oga_events &
printf "\033c" > /dev/tty0
