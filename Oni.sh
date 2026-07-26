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
# PortMasterDialog/PortMasterDialogInit drive the on-screen progress bar via
# $PM_PIPE; stub them too so http_get_progress works when run outside PortMaster.
if ! declare -F PortMasterDialog >/dev/null; then
    PortMasterDialog() {
        echo -n
    }
fi
if ! declare -F PortMasterDialogInit >/dev/null; then
    PortMasterDialogInit() {
        echo -n
    }
fi

######################################### FUNCTIONS #########################################

# Auto-scale a raw byte count into a human-readable string like "5.2MB" or "1.2GB"
__pretty_size() {
    __missing_reqs "awk" && return 1
    local bytes="${1:-0}" unit num
    for unit in yb zb eb pb tb gb mb kb; do
            num=$(b2$unit "$bytes" 2>/dev/null | cut -d' ' -f1)
            if awk -v n="${num:-0}" 'BEGIN { exit !(n + 0 >= 1) }'; then
                    echo "${num}${unit^^}"
                    return
            fi
    done
    echo "${bytes}B"
}

__missing_reqs() {
    for i in "$@"; do
        [[ "$0" != "$i" ]] && __no_req "$i" && echo "$i is required to perform this function." && return 0
    done
    return 1
}

__no_req() {
    return $([[ "$(type $1 2>/dev/null)" == '' ]])
}

# Total byte size of a URL, via a HEAD request; empty if it can't be determined
http_get_size() {
    if ! __no_req "curl"; then
        curl -fsSIL "$1" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1) == "content-length" { size = $2 } END { print size }'
    elif ! __no_req "wget"; then
        wget --spider --server-response -O /dev/null "$1" 2>&1 | tr -d '\r' | awk -F': ' 'tolower($1) == "content-length" { size = $2 } END { print size }'
    fi
}

# Downloads "$1" to "$2", driving the PortMaster progress bar with "$3" as
# the label. Falls back to a plain curl/wget if the progress dialog isn't available.
http_get() {
    local url="$1" dest="$2" message="${3:-Downloading}"

    if __missing_reqs "curl" "wget"; then
        pm_show_error "curl or wget is required to perform this function." && return 1
    fi

    local total current pid result pretty_total label
    total=$(http_get_size "$url")
    pretty_total=""
    [ -n "$total" ] && [ "$total" -gt 0 ] 2>/dev/null && pretty_total=$(__pretty_size "$total")

    [ -e "$PM_PIPE" ] || { PortMasterDialogInit "no-harbour"; PortMasterDialog "messages_begin"; }

    echo -n > "$dest"
    if ! __no_req "curl"; then
        curl -fsSL "$url" -o "$dest" &
    else
        wget -q "$url" -O "$dest" &
    fi
    pid=$!

    # The "data" fmt arg is ignored by PortMaster's fifo handler, so the
    # human-readable size is baked into the label instead of using it.
    while kill -0 "$pid" 2>/dev/null; do
        current=$(wc -c < "$dest" 2>/dev/null)
        if [ -n "$pretty_total" ]; then
            label="$message ($(__pretty_size "${current:-0}") / $pretty_total)"
        else
            label="$message ($(__pretty_size "${current:-0}"))"
        fi
        PortMasterDialog "progress" "$label" "${current:-0}" "${total:-0}" "data"
        sleep 0.5
    done
    wait "$pid"
    result=$?

    PortMasterDialog "progress_clear"

    { [ "$result" -ne 0 ] || [ ! -s "$dest" ]; } && return 1
    return 0
}

get_bin() {
    pm_message "Downloading Oni binary"
    http_get "https://github.com/Cronocide/oni-armhf/releases/download/v1.1/oni" "$GAMEDIR/oni" "Downloading Oni binary"
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
    http_get "https://github.com/Cronocide/oni-pm/raw/refs/heads/trunk/oni/gl4es.armhf/libGL.so.1" "$GAMEDIR/gl4es.armhf/libGL.so.1" "Downloading missing gl4es"
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
export LIBGL_FBOMAKECURRENT=0 LIBGL_FBOUNBIND=0 LIBGL_NOHIGHP=1 LIBGL_NOPSA=1

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

# START DEBUG BLOCK                                                                                                                                              
{                                                                                                                                                                                                                         
echo "----- DEBUG: system -----"                                                                                                                                                                                        
uname -a                                                                                                                                                                                                                
[ -f /etc/os-release ] && grep -E "^(NAME|VERSION)=" /etc/os-release                                                                                                                                                    
echo "CFW_NAME=$CFW_NAME DEVICE_NAME=$DEVICE_NAME DEVICE_ARCH=$DEVICE_ARCH"                                                                                                                                             
echo "DISPLAY_WIDTH=$DISPLAY_WIDTH DISPLAY_HEIGHT=$DISPLAY_HEIGHT"                                                                                                                                                      
                                                                                                                                                                                                                        
echo "----- DEBUG: launch environment -----"                                                                                                                                                                            
env | grep -E '^(LIBGL|SDL|ONI|LD_LIBRARY_PATH|XDG|SPA|PIPEWIRE|ALSA|WAYLAND|DISPLAY|PORT_32BIT)' | sort                                                                                                                
                                                                                                                                                                                                                        
echo "----- DEBUG: port files -----"                                                                                                                                                                                    
echo "GAMEDIR=$GAMEDIR PWD=$PWD"                                                                                                                                                                                        
ls -la "$GAMEDIR/oni" "$GAMEDIR/gl4es.armhf/" 2>&1                                                                                                                                                                      
command -v md5sum >/dev/null && md5sum "$GAMEDIR/gl4es.armhf/libGL.so.1" 2>&1                                                                                                                                           
                                                                                                                                                                                                                        
echo "----- DEBUG: which libraries the loader binds -----"                                                                                                                                                              
ldd ./oni 2>&1                                                                                                                                                                                                          
                                                                                                                                                                                                                        
echo "----- DEBUG: system 32-bit GL/EGL/GBM libs -----"                                                                                                                                                                 
for d in /usr/lib/arm-linux-gnueabihf /lib/arm-linux-gnueabihf /usr/lib32 /usr/lib/mali; do                                                                                                                             
    [ -d "$d" ] && { echo "== $d"; ls -la "$d" 2>/dev/null | grep -Ei 'mali|gles|egl|libgl|gbm' ; }                                                                                                                       
done                                                                                                                                                                                                                    
                                                                                                                                                                                                                        
echo "----- DEBUG: display/GPU state -----"                                                                                                                                                                             
ls -la /dev/dri/ 2>&1                                                                                                                                                                                                   
ls /dev/fb* 2>&1                                                                                                                                                                                                        
lsmod 2>/dev/null | grep -Ei 'mali|panfrost|bifrost|rockchip'                                                                                                                                                           
                                                                                                                                                                                                                        
echo "----- DEBUG: end preflight -----"                                                                                                                                                                                 
} >> "$LOGFILE" 2>&1                                                                                                                                                                                                      
                                                                                                                                                                                                                        
# Framebuffer sampler: is anything actually being presented? (heuristic)                                                                                                                                                  
(                                                                                                                                                                                                                         
sleep 25                                                                                                                                                                                                                
if [ -r /dev/fb0 ]; then                                                                                                                                                                                                
    A=$(dd if=/dev/fb0 bs=65536 count=4 2>/dev/null | cksum)                                                                                                                                                              
    sleep 3                                                                                                                                                                                                               
    B=$(dd if=/dev/fb0 bs=65536 count=4 2>/dev/null | cksum)                                                                                                                                                              
    Z=$(dd if=/dev/fb0 bs=65536 count=4 2>/dev/null | tr -d '\0' | wc -c)                                                                                                                                                 
    echo "DEBUG fb0 sample: A=$A B=$B nonzero_bytes=$Z" >> "$LOGFILE"                                                                                                                                                     
else                                                                                                                                                                                                                    
    echo "DEBUG fb0 sample: /dev/fb0 not readable" >> "$LOGFILE"                                                                                                                                                          
fi                                                                                                                                                                                                                      
) &                                                                                                                                                                                                                       
# END DEBUG BLOCK                                                                        

echo "=== Oni exited with code $EXIT_CODE at $(date) ===" >> "$LOGFILE"

pm_finish
printf "\033c" > /dev/tty0
