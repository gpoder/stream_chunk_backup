#!/usr/bin/env bash
#
# =============================================================================
# stream_chunk_backup.sh
# =============================================================================
#
# Streaming, chunked backup script for very large directories on low-disk hosts.
#
# FEATURES
# --------
# - Streams directories into a TAR archive
# - Splits the stream into fixed-size chunks (default: 5G)
# - Writes chunks directly to a mounted destination (S3 / Garage / FUSE)
# - NEVER creates full archives locally
# - Shows real-time throughput using pv
#
# DESIGNED FOR
# ------------
# - Mail-in-a-Box (MIAB) servers
# - Low free disk environments
# - Object storage mounts (Garage, rclone, s3fs, etc.)
#
# OUTPUT
# ------
# DEST_BASE/
#   <source-name>/
#     <source-name>.tar.part_001
#     <source-name>.tar.part_002
#     ...
#
# RESTORE
# -------
#   cat <source>.tar.part_* | tar -xpf -
#
# REQUIREMENTS
# ------------
# - bash
# - tar
# - split (coreutils)
# - pv   (for live speed / ETA)
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# DEFAULTS
# -----------------------------------------------------------------------------

DEFAULT_CHUNK_SIZE="5G"
DEFAULT_LOG_DIR="/var/log"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DEFAULT_LOGFILE="$DEFAULT_LOG_DIR/stream_chunk_backup_$TIMESTAMP.log"

SRC_DIRS=()
DEST_BASE=""
CHUNK_SIZE="$DEFAULT_CHUNK_SIZE"
LOGFILE="$DEFAULT_LOGFILE"
CONFIG_FILE=""

# -----------------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------------

show_help() {
cat <<'EOF'
Usage:
  stream_chunk_backup.sh [options] --src DIR [--src DIR ...]

Required:
  --dest DIR            Destination base directory (must be mounted & writable)
  --src DIR             Source directory to back up (repeatable)

Optional:
  --chunk-size SIZE     Chunk size (default: 5G)
                        Examples: 1G, 5G, 10G
  --log FILE            Log file path
                        Default: /var/log/stream_chunk_backup_<timestamp>.log
  --config FILE         Load options from config file
  -h, --help            Show this help and exit

Description:
  Streams large directories into TAR archives, splits them into fixed-size
  chunks, and writes them directly to the destination directory.

  This script is safe for very large datasets and systems with little free disk
  space. No intermediate archive files are created.

Examples:

  Basic usage:
    sudo ./stream_chunk_backup.sh \
      --dest /mnt/garage/Backups/MIAB \
      --src /home/user-data \
      --src /mnt/disk1 \
      --src /mnt/disk2

  Custom chunk size:
    sudo ./stream_chunk_backup.sh \
      --dest /mnt/backup \
      --src /data \
      --chunk-size 10G

  Using a config file:
    sudo ./stream_chunk_backup.sh --config backup.conf

Restore example:
  cat user-data.tar.part_* | tar -xpf -

Notes:
  - Must run as root (script will re-run with sudo if needed)
  - Destination must already be mounted
  - Designed for object storage mounts (S3 / Garage / FUSE)

EOF
}

# -----------------------------------------------------------------------------
# CONFIG FILE LOADING
# -----------------------------------------------------------------------------

load_config() {
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
}

# -----------------------------------------------------------------------------
# ARGUMENT PARSING
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)
            SRC_DIRS+=("$2")
            shift 2
            ;;
        --dest)
            DEST_BASE="$2"
            shift 2
            ;;
        --chunk-size)
            CHUNK_SIZE="$2"
            shift 2
            ;;
        --log)
            LOGFILE="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# VALIDATION
# -----------------------------------------------------------------------------

if [[ -n "$CONFIG_FILE" ]]; then
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    load_config
fi

if [[ ${#SRC_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: At least one --src directory is required"
    show_help
    exit 1
fi

if [[ -z "$DEST_BASE" ]]; then
    echo "ERROR: --dest is required"
    show_help
    exit 1
fi

# -----------------------------------------------------------------------------
# PRIVILEGES
# -----------------------------------------------------------------------------

ensure_sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo "Re-running with sudo..."
        exec sudo bash "$0" "$@"
    fi
}

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# -----------------------------------------------------------------------------
# CORE FUNCTION
# -----------------------------------------------------------------------------

stream_backup() {
    local src="$1"
    local name
    name="$(basename "$src")"
    local dest="$DEST_BASE/$name"

    echo "[$(timestamp)] Streaming $src → $dest (chunk size: $CHUNK_SIZE)" | tee -a "$LOGFILE"
    mkdir -p "$dest"

    if ! command -v pv >/dev/null 2>&1; then
        echo "ERROR: pv not installed. Install with: sudo apt install pv" | tee -a "$LOGFILE"
        exit 1
    fi

    tar -c "$src" 2>>"$LOGFILE" \
      | pv -brt \
      | split -b "$CHUNK_SIZE" \
          --numeric-suffixes=1 \
          --suffix-length=3 \
          --filter='
              out="'"$dest"'/'"$name"'.tar.part_$FILE"
              echo "Writing $out" >&2
              cat > "$out"
          ' \
          -

    echo "[$(timestamp)] Completed $src" | tee -a "$LOGFILE"
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

ensure_sudo "$@"

echo "=== STREAM CHUNK BACKUP STARTED $(timestamp) ===" | tee -a "$LOGFILE"
echo "Log file: $LOGFILE" | tee -a "$LOGFILE"
echo "Destination: $DEST_BASE" | tee -a "$LOGFILE"

mkdir -p "$DEST_BASE"

for src in "${SRC_DIRS[@]}"; do
    if [[ -d "$src" ]]; then
        stream_backup "$src"
    else
        echo "[$(timestamp)] WARNING: $src not found, skipping" | tee -a "$LOGFILE"
    fi
done

echo "=== BACKUP COMPLETED $(timestamp) ===" | tee -a "$LOGFILE"
