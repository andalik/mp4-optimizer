#!/bin/zsh

# Configuration
QUALITY_CRF=20                           # Quality (18-28, lower = better quality)
PRESET="medium"                          # Speed preset: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
THREADS=0                                # 0 = auto-detect number of threads
CPU_LIMIT=70                             # Maximum CPU percentage to use (10-100)
THERMAL_PAUSE=60                         # Pause in seconds between conversions (0 = disabled)
USE_CPULIMIT=true                        # Use cpulimit for precise CPU control (true/false)
ADAPTIVE_PRESET=false                    # Adjust preset based on system load (true/false)

# Configuration constants
readonly PROGRESS_BAR_WIDTH=50           # Progress bar width
readonly MAX_BASENAME_LENGTH=100         # Maximum allowed basename length for files
readonly MIN_CPU_LIMIT=10                # Minimum CPU limit
readonly MAX_CPU_LIMIT=100               # Maximum CPU limit
readonly MIN_CRF=0                       # Minimum CRF value
readonly MAX_CRF=51                      # Maximum CRF value
readonly SUCCESS_THRESHOLD_EXCELLENT=90  # Threshold for "excellent" success rate
readonly SUCCESS_THRESHOLD_GOOD=70       # Threshold for "good" success rate
readonly LOAD_THRESHOLD_HIGH=8           # High system load threshold
readonly LOAD_THRESHOLD_MEDIUM=6         # Medium system load threshold
readonly LOAD_THRESHOLD_LOW=3            # Low system load threshold

# Colors for output
RED='\033[1;31m'                         # Bright red
GREEN='\033[1;32m'                       # Bright green
YELLOW='\033[1;33m'                      # Bright yellow
BLUE='\033[1;34m'                        # Bright blue
MAGENTA='\033[1;35m'                     # Bright magenta
CYAN='\033[1;36m'                        # Bright cyan
WHITE='\033[1;37m'                       # Bright white
BLACK='\033[1;30m'                       # Bright black
GRAY='\033[0;90m'                        # Gray
BOLD='\033[1m'                           # Bold
DIM='\033[2m'                            # Dimmed
UNDERLINE='\033[4m'                      # Underlined
BLINK='\033[5m'                          # Blinking
REVERSE='\033[7m'                        # Reverse
NC='\033[0m'                             # Reset - No color

# Background colors
BG_BLACK='\033[40m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'

# File counters
total_files=0
converted_files=0
skipped_files=0
failed_files=0

# Global temp file variable for cleanup
TEMP_FILE_LIST=""


# Error log for processed files
ERROR_LOG_DIR="./mp4-optimizer-logs"
if ! mkdir -p "$ERROR_LOG_DIR" 2>/dev/null; then
    echo "${BOLD}${RED}❌ ${RED}Failed to create log directory: $ERROR_LOG_DIR${NC}" >&2
    exit 1
fi

# Cleanup function for signals
cleanup_on_exit() {
    local exit_code=${1:-1}
    
    # Determine if this is an interruption (non-zero exit code) or normal exit
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo "${BOLD}${YELLOW}🛑 Process interrupted! ${YELLOW}Cleanup in progress...${NC}"
        
        # Terminate any running child processes
        if [[ -n "$CURRENT_PID" ]]; then
            echo "${BOLD}${YELLOW}🛑 Terminating running processes...${NC}"
            kill -TERM "$CURRENT_PID" 2>/dev/null || true
            wait "$CURRENT_PID" 2>/dev/null || true
        fi
        
        # Remove partial output files if they exist (with race condition protection)
        local temp_output="$current_output"
        if [[ -n "$temp_output" && -f "$temp_output" ]]; then
            echo "${BOLD}${YELLOW}🗑️ Cleaning up: ${YELLOW}Removing partial file: $temp_output${NC}"
            rm -f "$temp_output" 2>/dev/null || true
        fi
        
        echo "${BOLD}${GREEN}✓ Cleanup complete${NC}"
    fi
    
    # Always clean up temporary file list on any exit
    if [[ -n "$TEMP_FILE_LIST" && -f "$TEMP_FILE_LIST" ]]; then
        rm -f "$TEMP_FILE_LIST" 2>/dev/null || true
    fi
    
    exit $exit_code
}

# Configure trap for termination signals
trap 'cleanup_on_exit $?' INT TERM
trap 'cleanup_on_exit $?' EXIT

# Calculate number of threads based on CPU limit
if [[ $THREADS -eq 0 ]]; then
    # Detect number of CPU cores
    if [[ "$OSTYPE" == darwin* ]]; then
        MAX_CORES=$(sysctl -n hw.ncpu 2>/dev/null)
        if [[ -z "$MAX_CORES" ]] || [[ ! "$MAX_CORES" =~ ^[0-9]+$ ]]; then
            echo "${BOLD}${YELLOW}⚠️ ${YELLOW}Failed to detect CPU cores, using fallback value${NC}" >&2
            MAX_CORES=4
        fi
    else
        MAX_CORES=$(nproc 2>/dev/null)
        if [[ -z "$MAX_CORES" ]] || [[ ! "$MAX_CORES" =~ ^[0-9]+$ ]]; then
            echo "${BOLD}${YELLOW}⚠️ ${YELLOW}Failed to detect CPU cores, using fallback value${NC}" >&2
            MAX_CORES=4
        fi
    fi
    
    # Calculate threads based on desired CPU percentage
    CALCULATED_THREADS=$(( MAX_CORES * CPU_LIMIT / 100 ))
    # Ensure at least 1 thread
    if [[ $CALCULATED_THREADS -lt 1 ]]; then
        CALCULATED_THREADS=1
    fi
    THREADS=$CALCULATED_THREADS
fi

# Function to check if cpulimit is installed
check_cpulimit() {
    if command -v cpulimit >/dev/null 2>&1; then
        return 0
    else
        echo "${BOLD}${YELLOW}⚠️ ${YELLOW}cpulimit not found - continuing with thread limiting only${NC}"
        echo "${DIM}cpulimit allows precise CPU usage control during conversions.${NC}"
        USE_CPULIMIT=false
        return 1
    fi
}

# Function to adjust preset based on system load
get_adaptive_preset() {
    local load_avg load_int
    
    if [[ "$ADAPTIVE_PRESET" != "true" ]]; then
        echo "$PRESET"
        return
    fi
    
    # Get system load
    if [[ "$OSTYPE" == darwin* ]]; then
        load_avg=$(uptime 2>/dev/null | awk -F'load averages:' '{print $2}' | awk '{print $1}' | tr -d ',')
    else
        load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    fi
    
    # Fallback if uptime command fails
    if [[ -z "$load_avg" ]]; then
        load_avg="1.0"  # Safe fallback
    fi
    
    # Convert to integer (remove decimal point)
    load_int=$(printf '%.0f' "$load_avg" 2>/dev/null)
    if [[ -z "$load_int" ]]; then
        load_int=1  # Fallback
    fi
    
    # Adjust preset based only on system load
    if [[ $load_int -gt $LOAD_THRESHOLD_HIGH ]]; then
        echo "slow"      # System under stress
    elif [[ $load_int -gt $LOAD_THRESHOLD_MEDIUM ]]; then
        echo "medium"    # System moderately loaded
    elif [[ $load_int -lt $LOAD_THRESHOLD_LOW ]]; then
        echo "fast"      # System with available resources
    else
        echo "$PRESET"   # Use default preset
    fi
}

# Function to validate configuration parameters
validate_config() {
    local errors=0
    
    # Validate CRF (must be between MIN_CRF-MAX_CRF)
    if [[ ! "$QUALITY_CRF" =~ ^[0-9]+$ ]] || [[ $QUALITY_CRF -lt $MIN_CRF ]] || [[ $QUALITY_CRF -gt $MAX_CRF ]]; then
        echo "${BOLD}${RED}❌ ${RED}QUALITY_CRF must be between $MIN_CRF and $MAX_CRF (current: $QUALITY_CRF)${NC}"
        ((errors++))
    fi
    
    # Validate preset
    valid_presets=("ultrafast" "superfast" "veryfast" "faster" "fast" "medium" "slow" "slower" "veryslow")
    if [[ ! " ${valid_presets[@]} " =~ " ${PRESET} " ]]; then
        echo "${BOLD}${RED}❌ ${RED}Invalid PRESET: $PRESET${NC}"
        echo "${DIM}Valid presets: ${valid_presets[*]}${NC}"
        ((errors++))
    fi
    
    # Validate CPU_LIMIT (must be between MIN_CPU_LIMIT-MAX_CPU_LIMIT)
    if [[ ! "$CPU_LIMIT" =~ ^[0-9]+$ ]] || [[ $CPU_LIMIT -lt $MIN_CPU_LIMIT ]] || [[ $CPU_LIMIT -gt $MAX_CPU_LIMIT ]]; then
        echo "${BOLD}${RED}❌ ${RED}CPU_LIMIT must be between $MIN_CPU_LIMIT and $MAX_CPU_LIMIT (current: $CPU_LIMIT)${NC}"
        ((errors++))
    fi
    
    # Validate THERMAL_PAUSE (must be non-negative)
    if [[ ! "$THERMAL_PAUSE" =~ ^[0-9]+$ ]] || [[ $THERMAL_PAUSE -lt 0 ]]; then
        echo "${BOLD}${RED}❌ ${RED}THERMAL_PAUSE must be a non-negative number (current: $THERMAL_PAUSE)${NC}"
        ((errors++))
    fi
    
    # Check if ffmpeg is installed
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "${BOLD}${RED}❌ ${RED}FFmpeg not found - please install FFmpeg${NC}"
        echo "${DIM}Install with: brew install ffmpeg${NC}"
        ((errors++))
    fi
    
    # Check if there are MP4 files to process
    local mp4_count=0
    while IFS= read -r -d '' file; do
        if [[ "$file" != *"_ffmpeg.mp4" ]]; then
            ((mp4_count++))
            break  # We only need to know if there's at least one
        fi
    done < <(find . -name "*.mp4" -type f -print0 2>/dev/null)
    
    if [[ $mp4_count -eq 0 ]]; then
        echo "${BOLD}${YELLOW}⚠️ ${YELLOW}No MP4 files found in the current directory${NC}"
    fi
    
    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "${BOLD}${RED}❌ Found $errors configuration error(s)${NC}"
        echo "${BOLD}${RED}Please correct these issues before continuing${NC}"
        exit 1
    fi
    
    return 0
}

# Validate configuration before proceeding
validate_config

# Check cpulimit if enabled
if [[ "$USE_CPULIMIT" == "true" ]]; then
    check_cpulimit
fi

# Helper function to get file size in bytes (cross-platform)
get_file_size() {
    local file="$1"
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [[ -z "$size" ]] || [[ ! "$size" =~ ^[0-9]+$ ]]; then
        echo "0"  # Fallback for files that can't be stat'd
    else
        echo "$size"
    fi
}

# Function to show elegant header
show_header() {
    clear
    echo "${BOLD}${BLUE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo "${BOLD}${BLUE}┃${NC}         ${BOLD}${RED} __  __ ___ _ _     ___       _   _       _            ${NC}"
    echo "${BOLD}${BLUE}┃${NC}         ${BOLD}${RED}|  \/  | _ \ | |   / _ \ _ __| |_(_)_ __ (_)______ _ _ ${NC}"
    echo "${BOLD}${BLUE}┃${NC}         ${BOLD}${RED}| |\/| |  _/_  _| | (_) | '_ \  _| | '  \| |_ / -_) '_|${NC}"
    echo "${BOLD}${BLUE}┃${NC}         ${BOLD}${RED}|_|  |_|_|   |_|   \___/| .__/\__|_|_|_|_|_/__\___|_|  ${NC}"
    echo "${BOLD}${BLUE}┃${NC}         ${BOLD}${RED}                        |_|                 by Andalik ${NC}"
    echo "${BOLD}${BLUE}┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩${NC}"
    echo "${BOLD}${BLUE}│${NC} ${WHITE}🔄 Converts MP4 videos to HEVC format for smaller file sizes${NC}"
    echo "${BOLD}${BLUE}│${NC} ${WHITE}    while preserving video quality.${NC}"
    echo "${BOLD}${BLUE}│${NC} ${WHITE}   Preserves audio quality and ensures Apple device compatibility${NC}"
    echo "${BOLD}${BLUE}│${NC} ${WHITE}    with optimized streaming support.${NC}"
    echo "${BOLD}${BLUE}│${NC} ${NC}"
    echo "${BOLD}${BLUE}│${NC} ${YELLOW}⚙️  Settings:${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Quality (CRF): ${GREEN}$QUALITY_CRF${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Preset: ${GREEN}$PRESET${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Threads: ${GREEN}$THREADS${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} CPU Limit: ${GREEN}${CPU_LIMIT}%${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Thermal Pause: ${GREEN}${THERMAL_PAUSE}s${NC}"
    if [[ "$USE_CPULIMIT" == "true" ]] && command -v cpulimit >/dev/null 2>&1; then
        echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} CPU Control: ${GREEN}cpulimit active${NC}"
    fi
    echo "${BOLD}${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Starting log
show_header

# Function to ask user for sorting order
ask_sort_order() {
    echo "${BOLD}${CYAN}🔤 Sort files by:${NC}" >&2
    echo "   ${WHITE}1)${NC} Alphabetical ascending ${DIM}(0-9, A-Z)${NC}" >&2
    echo "   ${WHITE}2)${NC} Alphabetical descending ${DIM}(Z-A, 9-0)${NC}" >&2
    echo "   ${WHITE}3)${NC} Size ascending ${DIM}(smaller → larger)${NC}" >&2
    echo "   ${WHITE}4)${NC} Size descending ${DIM}(larger → smaller)${NC}" >&2
    echo "" >&2
    printf "${BOLD}Select [1-4]:${NC} " >&2
    
    local choice
    if ! read -r choice </dev/tty 2>/dev/null; then
        echo "${BOLD}${YELLOW}⚠️ ${YELLOW}No input available, using default${NC}" >&2
        echo "alpha_asc"
        return
    fi
    
    case "$choice" in
        1) echo "alpha_asc" ;;
        2) echo "alpha_desc" ;;
        3) echo "size_asc" ;;
        4) echo "size_desc" ;;
        *)
            echo "${YELLOW}⚠️ Invalid choice. Defaulting to alphabetical order.${NC}" >&2
            echo "alpha_asc"
            ;;
    esac
}

# Function to discover and count MP4 files
discover_mp4_files() {
    local -a mp4_files=()
    local processable_count=0
    
    echo "${CYAN}🔍 Searching for MP4 files...${NC}"
    
    # Find all MP4 files, excluding already converted ones
    while IFS= read -r -d '' file; do
        if [[ "$file" != *"_ffmpeg.mp4" ]]; then
            mp4_files+=("$file")
            ((processable_count++))
        fi
    done < <(find . -name "*.mp4" -type f -print0 2>/dev/null)
    
    echo "${GREEN}   ✓ Search completed${NC}"
    
    # If there are no files to process, return
    if [[ ${#mp4_files[@]} -eq 0 ]]; then
        echo ""
        echo "${BOLD}${YELLOW}⚠️ WARNING:${NC} ${YELLOW}No MP4 files found for conversion.${NC}"
        echo "${DIM}(Files with _ffmpeg.mp4 suffix are ignored as they were already converted)${NC}"
        echo ""
        total_processable=0
        # Create secure temporary file
        TEMP_FILE_LIST=$(mktemp -t "hevcbatch_files_XXXXXX.tmp" 2>/dev/null)
        if [[ -z "$TEMP_FILE_LIST" ]] || [[ ! -f "$TEMP_FILE_LIST" ]]; then
            echo "${BOLD}${RED}❌ ${RED}Failed to create temporary file${NC}" >&2
            exit 1
        fi
        return
    fi
    
    echo "${GREEN}   ✓ Found ${BOLD}$processable_count${NC}${GREEN} MP4 file(s) to process${NC}"
    
    # Ask user for sorting order
    echo ""
    local sort_order=$(ask_sort_order)
    echo ""
    
    # Sort files according to user choice
    case "$sort_order" in
        "alpha_asc")
            echo "${CYAN}📂 Sorting files: ${WHITE}Alphabetical ascending${NC}"
            local old_IFS="$IFS"
            IFS=$'\n' mp4_files=($(printf '%s\n' "${mp4_files[@]}" | sort))
            IFS="$old_IFS"
            ;;
        "alpha_desc")
            echo "${CYAN}📂 Sorting files: ${WHITE}Alphabetical descending${NC}"
            local old_IFS="$IFS"
            IFS=$'\n' mp4_files=($(printf '%s\n' "${mp4_files[@]}" | sort -r))
            IFS="$old_IFS"
            ;;
        "size_asc" | "size_desc")
            local sort_flag="-n"  # Numerical sort for ascending
            if [[ "$sort_order" == "size_asc" ]]; then
                echo "${CYAN}📂 Sorting files: ${WHITE}Size ascending (smaller → larger)${NC}"
            else
                echo "${CYAN}📂 Sorting files: ${WHITE}Size descending (larger → smaller)${NC}"
                sort_flag="-nr"  # Numerical reverse for descending
            fi
            # Create temporary array with size and filename
            local -a files_with_size=()
            for file in "${mp4_files[@]}"; do
                local size=$(get_file_size "$file")
                files_with_size+=("${size}:${file}")
            done
            # Sort and extract only the filenames
            local old_IFS="$IFS"
            IFS=$'\n' mp4_files=($(printf '%s\n' "${files_with_size[@]}" | sort -t: -k1 $sort_flag | cut -d: -f2-))
            IFS="$old_IFS"
            ;;
    esac
    
    echo ""
    
    # Export results via global variables
    total_processable=$processable_count
    # Save file list to temporary file for second pass
    # Create secure temporary file
    TEMP_FILE_LIST=$(mktemp -t "hevcbatch_files_XXXXXX.tmp" 2>/dev/null)
    if [[ -z "$TEMP_FILE_LIST" ]] || [[ ! -f "$TEMP_FILE_LIST" ]]; then
        echo "${BOLD}${RED}❌ ${RED}Failed to create temporary file${NC}" >&2
        exit 1
    fi
    
    if ! printf '%s\0' "${mp4_files[@]}" > "$TEMP_FILE_LIST" 2>/dev/null; then
        echo "${BOLD}${RED}❌ ${RED}Failed to write to temporary file${NC}" >&2
        rm -f "$TEMP_FILE_LIST" 2>/dev/null
        exit 1
    fi
}

# Discover MP4 files and count total
discover_mp4_files

# Current file counter
current_file=0

# Function to create progress bar
draw_progress_bar() {
    local current=$1
    local total=$2
    local width=$PROGRESS_BAR_WIDTH
    
    # Protection against division by zero
    if [[ $total -eq 0 ]]; then
        printf "${CYAN}[%*s]${NC} ${BOLD}0%%${NC} (${BLUE}%d${NC}/${BLUE}%d${NC})\n" $width "" $current $total | tr ' ' '░'
        return
    fi
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "${CYAN}["
    printf "%*s" $filled | tr ' ' '█'  # Full block
    printf "%*s" $empty | tr ' ' '░'   # Empty block
    printf "]${NC} ${BOLD}%d%%${NC} (${BLUE}%d${NC}/${BLUE}%d${NC})\n" $percentage $current $total
}




# Function to analyze video file properties
analyze_video_file() {
    local file="$1"
    
    # Check if ffprobe is available
    if ! command -v ffprobe >/dev/null 2>&1; then
        echo "${BOLD}${RED}❌ ${RED}ffprobe not available - skipping file analysis${NC}" >&2
        return 1
    fi
    
    # Get comprehensive video information using ffprobe
    local probe_output
    probe_output=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>/dev/null)
    
    if [[ -z "$probe_output" ]]; then
        echo "${BOLD}${YELLOW}⚠️ ${YELLOW}Could not analyze file: $file${NC}" >&2
        return 1
    fi
    
    # Initialize global array
    declare -gA CURRENT_FILE_ANALYSIS
    
    # Use a simple and reliable approach to find video and audio streams
    local video_section=$(echo "$probe_output" | grep -B 5 -A 30 '"codec_type": "video"' | head -40)
    local audio_section=$(echo "$probe_output" | grep -B 5 -A 20 '"codec_type": "audio"' | head -30)
    
    # Extract video stream information
    CURRENT_FILE_ANALYSIS[codec_name]=$(echo "$video_section" | grep '"codec_name"' | head -1 | cut -d'"' -f4)
    CURRENT_FILE_ANALYSIS[codec_tag_string]=$(echo "$video_section" | grep '"codec_tag_string"' | head -1 | cut -d'"' -f4)
    CURRENT_FILE_ANALYSIS[width]=$(echo "$video_section" | grep '"width"' | head -1 | cut -d':' -f2 | tr -d ' ,')
    CURRENT_FILE_ANALYSIS[height]=$(echo "$video_section" | grep '"height"' | head -1 | cut -d':' -f2 | tr -d ' ,')
    CURRENT_FILE_ANALYSIS[bit_rate]=$(echo "$video_section" | grep '"bit_rate"' | head -1 | cut -d':' -f2 | tr -d ' ,"')
    CURRENT_FILE_ANALYSIS[r_frame_rate]=$(echo "$video_section" | grep '"r_frame_rate"' | head -1 | cut -d'"' -f4)
    CURRENT_FILE_ANALYSIS[pix_fmt]=$(echo "$video_section" | grep '"pix_fmt"' | head -1 | cut -d'"' -f4)
    CURRENT_FILE_ANALYSIS[profile]=$(echo "$video_section" | grep '"profile"' | head -1 | cut -d'"' -f4)
    CURRENT_FILE_ANALYSIS[level]=$(echo "$video_section" | grep '"level"' | head -1 | cut -d':' -f2 | tr -d ' ,')
    
    # Extract audio stream information
    CURRENT_FILE_ANALYSIS[audio_codec]=$(echo "$audio_section" | grep '"codec_name"' | head -1 | cut -d'"' -f4)
    CURRENT_FILE_ANALYSIS[audio_bit_rate]=$(echo "$audio_section" | grep '"bit_rate"' | head -1 | cut -d':' -f2 | tr -d ' ,"')
    CURRENT_FILE_ANALYSIS[channels]=$(echo "$audio_section" | grep '"channels"' | head -1 | cut -d':' -f2 | tr -d ' ,')
    
    # Extract format information
    CURRENT_FILE_ANALYSIS[duration]=$(echo "$probe_output" | grep '"duration"' | head -1 | cut -d'"' -f4)
    CURRENT_FILE_ANALYSIS[size]=$(echo "$probe_output" | grep '"size"' | head -1 | cut -d'"' -f4)
    CURRENT_FILE_ANALYSIS[format_name]=$(echo "$probe_output" | grep '"format_name"' | head -1 | cut -d'"' -f4)
    
    # Get encoder information if available
    CURRENT_FILE_ANALYSIS[encoder]=$(echo "$probe_output" | grep '"encoder"' | head -1 | cut -d'"' -f4)
    
    # Check faststart status
    check_faststart "$file"
    CURRENT_FILE_ANALYSIS[faststart]=$?
    
    return 0
}

# Function to check if MP4 has faststart (moov atom at beginning)
check_faststart() {
    local file="$1"
    
    # Use ffprobe to check atom order
    local atom_order=$(ffprobe -v trace -i "$file" 2>&1 | grep -E "type:'(mdat|moov)'" | head -2)
    
    # Check if moov appears before mdat
    if echo "$atom_order" | grep -q "type:'moov'" && echo "$atom_order" | head -1 | grep -q "type:'moov'"; then
        return 0  # Faststart enabled
    else
        return 1  # Faststart not enabled
    fi
}

# Function to display formatted file analysis
display_file_analysis() {
    local file="$1"
    local basename=$(basename "$file" .mp4)
    
    # Check if analysis data is available
    if [[ -z "${CURRENT_FILE_ANALYSIS[codec_name]}" ]]; then
        echo "${BOLD}${YELLOW}⚠️ ${YELLOW}No analysis data available${NC}"
        return 1
    fi
    
    echo ""
    echo "${BOLD}${CYAN}📊 Analyzing source file...${NC}"
    
    # File size information
    local file_size_mb=""
    if [[ -n "${CURRENT_FILE_ANALYSIS[size]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[size]}" =~ ^[0-9]+$ ]]; then
        file_size_mb=$(( CURRENT_FILE_ANALYSIS[size] / 1024 / 1024 ))
        echo "   ${WHITE}📁 File:${NC} $(basename "$file") ${CYAN}(${file_size_mb} MB)${NC}"
    else
        local file_size_du=$(du -h "$file" 2>/dev/null | cut -f1)
        echo "   ${WHITE}📁 File:${NC} $(basename "$file") ${CYAN}(${file_size_du:-"Unknown"})${NC}"
    fi
    
    # Video codec information
    local codec_display="${CURRENT_FILE_ANALYSIS[codec_name]:-"unknown"}"
    local codec_tag="${CURRENT_FILE_ANALYSIS[codec_tag_string]:-""}"
    if [[ -n "$codec_tag" ]] && [[ "$codec_tag" != "null" ]]; then
        codec_display="$codec_display ($codec_tag)"
    fi
    
    local resolution="${CURRENT_FILE_ANALYSIS[width]:-"?"}x${CURRENT_FILE_ANALYSIS[height]:-"?"}"
    local fps="${CURRENT_FILE_ANALYSIS[r_frame_rate]:-"?"}"
    if [[ "$fps" =~ ^[0-9]+/[0-9]+$ ]]; then
        # Convert fraction to decimal (e.g., 30000/1001 to ~29.97)
        local num_fps=$(echo "$fps" | cut -d'/' -f1)
        local den_fps=$(echo "$fps" | cut -d'/' -f2)
        if [[ $den_fps -ne 0 ]]; then
            fps=$(( num_fps / den_fps ))
        fi
    fi
    echo "   ${WHITE}🎬 Video:${NC} $codec_display → ${CYAN}${resolution} @ ${fps}fps${NC}"
    
    # Bitrate information
    local bitrate_display="Unknown"
    if [[ -n "${CURRENT_FILE_ANALYSIS[bit_rate]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[bit_rate]}" =~ ^[0-9]+$ ]]; then
        local bitrate_kbps=$(( CURRENT_FILE_ANALYSIS[bit_rate] / 1000 ))
        bitrate_display="${bitrate_kbps} kbps"
    fi
    echo "   ${WHITE}💾 Bitrate:${NC} ${CYAN}$bitrate_display${NC}"
    
    # Encoder information
    if [[ -n "${CURRENT_FILE_ANALYSIS[encoder]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[encoder]}" != "null" ]]; then
        echo "   ${WHITE}🎨 Encoder:${NC} ${CYAN}${CURRENT_FILE_ANALYSIS[encoder]}${NC}"
    fi
    
    # Profile and level
    local profile_info=""
    if [[ -n "${CURRENT_FILE_ANALYSIS[profile]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[profile]}" != "null" ]]; then
        profile_info="${CURRENT_FILE_ANALYSIS[profile]}"
        if [[ -n "${CURRENT_FILE_ANALYSIS[level]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[level]}" != "null" ]]; then
            profile_info="$profile_info @ L${CURRENT_FILE_ANALYSIS[level]}"
        fi
        echo "   ${WHITE}🔧 Profile:${NC} ${CYAN}$profile_info${NC}"
    fi
    
    # Pixel format
    if [[ -n "${CURRENT_FILE_ANALYSIS[pix_fmt]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[pix_fmt]}" != "null" ]]; then
        echo "   ${WHITE}📐 Pixel Format:${NC} ${CYAN}${CURRENT_FILE_ANALYSIS[pix_fmt]}${NC}"
    fi
    
    # Faststart status
    local faststart_status=""
    local faststart_color=""
    if [[ "${CURRENT_FILE_ANALYSIS[faststart]}" == "0" ]]; then
        faststart_status="✅ Enabled"
        faststart_color="$GREEN"
    else
        faststart_status="❌ Not enabled"
        faststart_color="$RED"
    fi
    echo "   ${WHITE}⚡ Faststart:${NC} ${faststart_color}$faststart_status${NC}"
    
    # Audio information
    local audio_display="Unknown"
    if [[ -n "${CURRENT_FILE_ANALYSIS[audio_codec]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[audio_codec]}" != "null" ]]; then
        audio_display="${CURRENT_FILE_ANALYSIS[audio_codec]}"
        if [[ -n "${CURRENT_FILE_ANALYSIS[audio_bit_rate]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[audio_bit_rate]}" =~ ^[0-9]+$ ]]; then
            local audio_kbps=$(( CURRENT_FILE_ANALYSIS[audio_bit_rate] / 1000 ))
            audio_display="$audio_display ${audio_kbps} kbps"
        fi
        if [[ -n "${CURRENT_FILE_ANALYSIS[channels]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[channels]}" =~ ^[0-9]+$ ]]; then
            audio_display="$audio_display, ${CURRENT_FILE_ANALYSIS[channels]} channels"
        fi
    fi
    echo "   ${WHITE}🔊 Audio:${NC} ${CYAN}$audio_display${NC}"
    
    # Duration
    local duration_display="Unknown"
    if [[ -n "${CURRENT_FILE_ANALYSIS[duration]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[duration]}" != "null" ]]; then
        # Convert seconds to HH:MM:SS format
        local duration_sec="${CURRENT_FILE_ANALYSIS[duration]%.*}"  # Remove decimal part
        if [[ "$duration_sec" =~ ^[0-9]+$ ]]; then
            local hours=$((duration_sec / 3600))
            local minutes=$(((duration_sec % 3600) / 60))
            local seconds=$((duration_sec % 60))
            duration_display=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
        else
            duration_display="${CURRENT_FILE_ANALYSIS[duration]}"
        fi
    fi
    echo "   ${WHITE}⏱️ Duration:${NC} ${CYAN}$duration_display${NC}"
    
    echo ""
    
    # Analysis and recommendations
    analyze_conversion_potential "$file"
}

# Function to analyze conversion potential and provide recommendations
analyze_conversion_potential() {
    local file="$1"
    local recommendations=()
    local expected_savings=""
    local warning_color="$GREEN"
    local analysis_icon="💡"
    
    # Check if already HEVC
    if [[ "${CURRENT_FILE_ANALYSIS[codec_name]}" == "hevc" ]]; then
        recommendations+=("Already HEVC format")
        expected_savings="minimal compression gain expected"
        warning_color="$YELLOW"
        analysis_icon="⚠️"
        
        # Check if already has hvc1 tag
        if [[ "${CURRENT_FILE_ANALYSIS[codec_tag_string]}" == "hvc1" ]]; then
            recommendations+=("Already has hvc1 tag for Apple compatibility")
        else
            recommendations+=("Will add hvc1 tag for better Apple compatibility")
        fi
    else
        recommendations+=("Currently ${CURRENT_FILE_ANALYSIS[codec_name]:-"unknown"} → will benefit from HEVC")
        expected_savings=""
    fi
    
    # Check faststart status
    if [[ "${CURRENT_FILE_ANALYSIS[faststart]}" != "0" ]]; then
        recommendations+=("Missing faststart → will improve streaming performance")
    else
        recommendations+=("Already has faststart enabled")
    fi
    
    # Check bitrate - low bitrate files might not compress well
    if [[ -n "${CURRENT_FILE_ANALYSIS[bit_rate]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[bit_rate]}" =~ ^[0-9]+$ ]]; then
        local bitrate_kbps=$(( CURRENT_FILE_ANALYSIS[bit_rate] / 1000 ))
        if [[ $bitrate_kbps -lt 1000 ]]; then
            recommendations+=("Low bitrate detected → conversion may increase file size")
            expected_savings="file size may increase due to low original bitrate"
            warning_color="$RED"
            analysis_icon="⚠️"
        fi
    fi
    
    echo "   ${analysis_icon} ${BOLD}Analysis:${NC} ${warning_color}${expected_savings}${NC}"
    for rec in "${recommendations[@]}"; do
        echo "      ${WHITE}•${NC} $rec"
    done
}

# Function to determine if conversion should be skipped based on analysis
should_skip_conversion() {
    # No analysis data available - should not skip
    if [[ -z "${CURRENT_FILE_ANALYSIS[codec_name]}" ]]; then
        return 1  # Don't skip
    fi
    
    local skip_reasons=0
    
    # Check if already HEVC with hvc1 tag and faststart enabled
    if [[ "${CURRENT_FILE_ANALYSIS[codec_name]}" == "hevc" ]]; then
        ((skip_reasons++))
        
        # If already has hvc1 tag, even more reason to skip
        if [[ "${CURRENT_FILE_ANALYSIS[codec_tag_string]}" == "hvc1" ]]; then
            ((skip_reasons++))
        fi
        
        # If already has faststart, even more reason to skip
        if [[ "${CURRENT_FILE_ANALYSIS[faststart]}" == "0" ]]; then
            ((skip_reasons++))
        fi
    fi
    
    # Check for very low bitrate (likely already compressed)
    if [[ -n "${CURRENT_FILE_ANALYSIS[bit_rate]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[bit_rate]}" =~ ^[0-9]+$ ]]; then
        local bitrate_kbps=$(( CURRENT_FILE_ANALYSIS[bit_rate] / 1000 ))
        if [[ $bitrate_kbps -lt 800 ]]; then
            ((skip_reasons++))
        fi
    fi
    
    # If we have 2 or more reasons to skip, recommend skipping
    if [[ $skip_reasons -ge 2 ]]; then
        return 0  # Should skip
    else
        return 1  # Don't skip
    fi
}

# Function to process a single file
process_single_file() {
    local file="$1"
    local current_file_num="$2"
    local total_files="$3"
    
    # Define output file
    local dir=$(dirname "$file" 2>/dev/null)
    local basename=$(basename "$file" .mp4 2>/dev/null)
    
    # Validate dirname and basename results
    if [[ -z "$dir" ]]; then
        dir="."  # Fallback to current directory
    fi
    if [[ -z "$basename" ]]; then
        echo "   ${BOLD}${RED}❌ ${RED}Failed to process filename: $file${NC}" >&2
        return 1
    fi
    local output="${dir}/${basename}_ffmpeg.mp4"
    current_output="$output"  # For cleanup in case of interruption
    
    # Specific error log file for this file (sanitize basename)
    local safe_basename=$(echo "$basename" | tr -cd '[:alnum.]._-' | head -c $MAX_BASENAME_LENGTH)
    if [[ -z "$safe_basename" ]]; then
        safe_basename="unknown_file_$(date +%s)"
    fi
    local error_log="$ERROR_LOG_DIR/${safe_basename}_error.log"
    
    # Check if already exists
    if [[ -f "$output" ]]; then
        echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "${BOLD}${YELLOW}⏭️ Skipping ${WHITE}$basename${NC} ${DIM}(already converted)${NC}"
        draw_progress_bar $current_file_num $total_files
        ((skipped_files++))
        return 1  # Returns 1 to indicate it was skipped
    fi

    echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "${BOLD}${GREEN}🎥 Converting ${WHITE}$basename${NC}"
    draw_progress_bar $current_file_num $total_files
    
    # Analyze video file before conversion
    if analyze_video_file "$file"; then
        display_file_analysis "$file"
        
        # Check if conversion is recommended and proceed automatically
        if should_skip_conversion; then
            echo "${BOLD}${YELLOW}⚠️  This file may not benefit from conversion, but proceeding anyway.${NC}"
            echo "${BOLD}${GREEN}▶️  Continuing with conversion...${NC}"
        fi
        echo ""
    else
        echo "${BOLD}${YELLOW}⚠️ ${YELLOW}Could not analyze file properties - proceeding with conversion${NC}"
        echo ""
    fi
    
    # Get adaptive preset
    local current_preset=$(get_adaptive_preset)
    if [[ "$current_preset" != "$PRESET" ]]; then
        echo "   ${BOLD}${CYAN}🔧 Using adaptive preset: ${CYAN}$current_preset${NC} ${DIM}(was: $PRESET)${NC}"
    fi
    
    # Get original file information
    local original_size=$(du -h "$file" 2>/dev/null | cut -f1)
    if [[ -z "$original_size" ]]; then
        original_size="unknown"  # Fallback if du fails
    fi
    
    # Log conversion start with analysis data
    echo "$(date): Starting conversion from $file to $output" > "$error_log"
    echo "Original file analysis:" >> "$error_log"
    if [[ -n "${CURRENT_FILE_ANALYSIS[codec_name]}" ]]; then
        echo "  Video codec: ${CURRENT_FILE_ANALYSIS[codec_name]:-"unknown"} (${CURRENT_FILE_ANALYSIS[codec_tag_string]:-"no tag"})" >> "$error_log"
        echo "  Resolution: ${CURRENT_FILE_ANALYSIS[width]:-"?"}x${CURRENT_FILE_ANALYSIS[height]:-"?"}" >> "$error_log"
        echo "  Bitrate: ${CURRENT_FILE_ANALYSIS[bit_rate]:-"unknown"} bps" >> "$error_log"
        echo "  Profile: ${CURRENT_FILE_ANALYSIS[profile]:-"unknown"}" >> "$error_log"
        echo "  Pixel format: ${CURRENT_FILE_ANALYSIS[pix_fmt]:-"unknown"}" >> "$error_log"
        echo "  Audio codec: ${CURRENT_FILE_ANALYSIS[audio_codec]:-"unknown"}" >> "$error_log"
        echo "  Duration: ${CURRENT_FILE_ANALYSIS[duration]:-"unknown"}" >> "$error_log"
        if [[ "${CURRENT_FILE_ANALYSIS[faststart]}" == "0" ]]; then
            echo "  Faststart: enabled" >> "$error_log"
        else
            echo "  Faststart: not enabled" >> "$error_log"
        fi
        if [[ -n "${CURRENT_FILE_ANALYSIS[encoder]}" ]] && [[ "${CURRENT_FILE_ANALYSIS[encoder]}" != "null" ]]; then
            echo "  Original encoder: ${CURRENT_FILE_ANALYSIS[encoder]}" >> "$error_log"
        fi
    else
        echo "  Analysis: failed to extract file properties" >> "$error_log"
    fi
    echo "" >> "$error_log"
    
    # Execute conversion
    local ffmpeg_exit_code=0
    execute_ffmpeg_conversion "$file" "$output" "$error_log" "$current_preset"
    ffmpeg_exit_code=$?
    
    # Log conversion result
    echo "$(date): FFmpeg finished with exit code: $ffmpeg_exit_code" >> "$error_log"
    
    # Process conversion result
    process_conversion_result "$file" "$output" "$error_log" "$ffmpeg_exit_code" "$original_size" "$basename"
    
    current_output=""  # Clear after processing
    return 0  # Returns 0 to indicate it was processed (converted)
}

# Function to execute FFmpeg conversion
execute_ffmpeg_conversion() {
    local input_file="$1"
    local output_file="$2"
    local error_log="$3"
    local current_preset="$4"
    
    # Escape filenames for protection against command injection
    local escaped_input=$(printf '%q' "$input_file")
    local escaped_output=$(printf '%q' "$output_file")
    local escaped_error_log=$(printf '%q' "$error_log")
    
    # Build FFmpeg command array for safe execution
    local ffmpeg_cmd=(
        "ffmpeg"
        "-nostdin"
        "-y"
        "-i" "$input_file"
        "-c:v" "libx265"
        "-preset" "$current_preset"
        "-crf" "$QUALITY_CRF"
        "-pix_fmt" "yuv420p"
        "-tag:v" "hvc1"
        "-c:a" "copy"
        "-movflags" "+faststart"
        "-threads" "$THREADS"
        "-hide_banner"
        "-loglevel" "error"
        "-stats"
        "$output_file"
    )

    echo "${BOLD}${CYAN}⚙️ Encoding...${NC}"
    if [[ "$USE_CPULIMIT" == "true" ]] && command -v cpulimit >/dev/null 2>&1; then
        # Use cpulimit for precise CPU control
        local cpulimit_cmd=("cpulimit" "-l" "$CPU_LIMIT" "--")
        "${cpulimit_cmd[@]}" "${ffmpeg_cmd[@]}" 2>&1 | \
        grep --line-buffered -E "(^x265|^frame=)" | tee -a "$error_log"
        return ${PIPESTATUS[1]}
    else
        # Execute normal conversion with limited threads
        "${ffmpeg_cmd[@]}" 2>&1 | \
        grep --line-buffered -E "(^x265|^frame=)" | tee -a "$error_log"
        return ${PIPESTATUS[1]}
    fi
}

# Function to process conversion result
process_conversion_result() {
    local input_file="$1"
    local output_file="$2"
    local error_log="$3"
    local exit_code="$4"
    local original_size="$5"
    local basename="$6"
    
    if [[ $exit_code -eq 0 ]]; then
        # Check if conversion was successful
        if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
            # Get new file size
            local new_size=$(du -h "$output_file" 2>/dev/null | cut -f1)
            if [[ -z "$new_size" ]]; then
                new_size="unknown"  # Fallback if du fails
            fi
            
            # Calculate savings (approximate)
            local original_bytes=$(get_file_size "$input_file")
            local new_bytes=$(get_file_size "$output_file")
            
            if [[ -n "$original_bytes" ]] && [[ -n "$new_bytes" ]] && [[ $original_bytes -gt 0 ]]; then
                local savings=$(( (original_bytes - new_bytes) * 100 / original_bytes ))
                if [[ $savings -gt 0 ]]; then
                    echo "${BOLD}${GREEN}✅ ${CYAN}$original_size${NC} → ${CYAN}$new_size${NC} ${BOLD}${GREEN}(saved ${savings}%)${NC}"
                    echo "$(date): Conversion successful. Savings: ${savings}%" >> "$error_log"
                elif [[ $savings -lt 0 ]]; then
                    local increase=$(( -savings ))
                    echo "${BOLD}${GREEN}✅ ${CYAN}$original_size${NC} → ${CYAN}$new_size${NC} ${BOLD}${YELLOW}(${increase}% larger)${NC}"
                    echo "$(date): Conversion successful. File increased by: ${increase}%" >> "$error_log"
                else
                    echo "${BOLD}${GREEN}✅ ${CYAN}$original_size${NC} → ${CYAN}$new_size${NC} ${BOLD}${CYAN}(same size)${NC}"
                    echo "$(date): Conversion successful. No size change." >> "$error_log"
                fi
            else
                echo "${BOLD}${GREEN}✅ ${CYAN}$original_size${NC} → ${CYAN}$new_size${NC}"
                echo "$(date): Conversion successful." >> "$error_log"
            fi
            
            # Preserve original file timestamps
            if ! touch -r "$input_file" "$output_file" 2>/dev/null; then
                echo "   ${BOLD}${YELLOW}⚠️ ${YELLOW}Warning: Could not preserve file timestamps${NC}" >&2
            fi
            
            # Remove error log if conversion successful
            rm -f "$error_log"
            
            ((converted_files++))
        else
            echo "   ${BOLD}${RED}❌ ${RED}Output file is empty or was not created${NC}"
            echo "$(date): ERROR - Output file is empty or was not created" >> "$error_log"
            echo "   ${DIM}Error log: $error_log${NC}"
            [[ -f "$output_file" ]] && rm -f "$output_file"
            ((failed_files++))
        fi
    else
        echo "   ${BOLD}${RED}❌ ${RED}Conversion failed (error code: $exit_code)${NC}"
        echo "$(date): ERROR - FFmpeg failed with exit code $exit_code" >> "$error_log"
        echo "   ${DIM}Error log: $error_log${NC}"
        [[ -f "$output_file" ]] && rm -f "$output_file"
        ((failed_files++))
    fi
}

# Function for thermal pause
thermal_pause() {
    local current_file="$1"
    local total_processable="$2"
    
    if [[ $THERMAL_PAUSE -gt 0 ]] && [[ $current_file -lt $total_processable ]]; then
        echo "\n${BOLD}${YELLOW}🌡️ Cooling down...${NC}"
        
        # Visual countdown counter
        for (( countdown=$THERMAL_PAUSE; countdown>0; countdown-- )); do
            printf "\r${YELLOW}⏳ ${BOLD}%02d${NC}${YELLOW}s remaining${NC}" $countdown
            sleep 1
        done
        printf "\r${GREEN}✓ Resuming...                         ${NC}\n"
    fi
}

# Process all discovered MP4 files
# Check if temp file exists before processing
if [[ -z "$TEMP_FILE_LIST" ]] || [[ ! -f "$TEMP_FILE_LIST" ]]; then
    echo "${BOLD}${RED}❌ ${RED}Temporary file list not found or corrupted${NC}" >&2
    exit 1
fi

while IFS= read -r -d '' file; do
    # Skip empty lines and validate file exists
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        echo "${BOLD}${YELLOW}⚠️ ${YELLOW}Skipping non-existent file: $file${NC}" >&2
        continue
    fi
    # Files already filtered in discover_mp4_files() function
    ((total_files++))
    ((current_file++))
    
    # Process file using dedicated function
    process_single_file "$file" "$current_file" "$total_processable"
    file_processed=$?
    
    # Thermal pause only if file was actually converted (not skipped)
    if [[ $file_processed -eq 0 ]]; then
        thermal_pause "$current_file" "$total_processable"
    fi
    
    echo ""
    
done < "$TEMP_FILE_LIST"

# Clean up temporary file
if [[ -n "$TEMP_FILE_LIST" ]] && [[ -f "$TEMP_FILE_LIST" ]]; then
    rm -f "$TEMP_FILE_LIST" 2>/dev/null
fi

# Function to show enhanced final report
local success_rate=0
local total_processed=$((converted_files + failed_files))

if [[ $total_processed -gt 0 ]]; then
    success_rate=$((converted_files * 100 / total_processed))
fi

echo "${WHITE}📁 Files processed:${NC} ${BOLD}${CYAN}$total_files${NC}"
echo ""
echo "${GREEN}✓${NC} ${BOLD}${GREEN}Converted successfully:${NC} ${BOLD}${GREEN}$converted_files${NC}"
echo "${YELLOW}⏭️${NC} ${BOLD}${YELLOW}Previously converted:${NC} ${BOLD}${YELLOW}$skipped_files${NC}"
echo "${RED}❌${NC} ${BOLD}${RED}Failed:${NC} ${BOLD}${RED}$failed_files${NC}"
echo ""

# Simple ASCII success rate chart
if [[ $success_rate -ge $SUCCESS_THRESHOLD_EXCELLENT ]]; then
    local status_color="$GREEN"
    local status_icon="🎆"
    local status_text="EXCELLENT"
elif [[ $success_rate -ge $SUCCESS_THRESHOLD_GOOD ]]; then
    local status_color="$YELLOW"
    local status_icon="😊"
    local status_text="GOOD"
else
    local status_color="$RED"
    local status_icon="⚠️"
    local status_text="WARNING"
fi

echo "${BOLD}Success Rate: ${status_color}${success_rate}% ${status_icon} ${status_text}${NC}"
echo ""

# Final message based on result
if [[ $converted_files -gt 0 ]]; then
    echo "${BOLD}${GREEN}🎉 Conversion complete! Converted files saved with '_ffmpeg.mp4' suffix${NC}"
elif [[ $skipped_files -gt 0 ]]; then
    echo "${BOLD}${YELLOW}📝 All files were already converted${NC}"
else
    echo "${BOLD}${RED}⚠️ No files to convert - please check for MP4 files in the directory${NC}"
fi