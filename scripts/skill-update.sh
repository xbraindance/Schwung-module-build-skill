#!/bin/bash

###############################################################################
# Schwung Module Creator Skill Auto-Update Script
#
# This script checks GitHub for updates to the skill and applies them
# automatically. It's triggered via a Claude Code hook before skill execution.
#
# Usage:
#   ./scripts/skill-update.sh
#   (called automatically by Claude Code hook)
###############################################################################

set -e

# Configuration
GITHUB_RAW_URL="https://raw.githubusercontent.com/xbraindance/Schwung-Module-Creator-skill/main/skill.md"
LOCAL_SKILL_PATH="$HOME/.claude/skills/schwung-module-creator/SKILL.md"
CACHE_DIR="$HOME/.cache/schwung-skill"
CACHE_FILE="$CACHE_DIR/last_check.txt"
CHECK_INTERVAL=3600  # Check every hour (in seconds)

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Function: Check if we should perform an update check
should_check_for_updates() {
    if [ ! -f "$CACHE_FILE" ]; then
        return 0  # First run, always check
    fi

    local last_check=$(cat "$CACHE_FILE")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_check))

    if [ $time_diff -ge $CHECK_INTERVAL ]; then
        return 0  # Interval passed, check again
    fi
    return 1  # Too soon, skip check
}

# Function: Download remote skill version
fetch_remote_version() {
    if ! command -v curl &> /dev/null; then
        echo "[skill-update] curl not found, skipping update check"
        return 1
    fi

    curl -sf "$GITHUB_RAW_URL" 2>/dev/null || return 1
}

# Function: Compare versions using hash
get_file_hash() {
    if command -v sha256sum &> /dev/null; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        md5sum "$1" | awk '{print $1}'
    fi
}

# Function: Apply update
apply_update() {
    local remote_content="$1"

    if [ ! -d "$(dirname "$LOCAL_SKILL_PATH")" ]; then
        mkdir -p "$(dirname "$LOCAL_SKILL_PATH")"
    fi

    # Backup current version
    if [ -f "$LOCAL_SKILL_PATH" ]; then
        cp "$LOCAL_SKILL_PATH" "$LOCAL_SKILL_PATH.backup"
    fi

    # Write new version
    echo "$remote_content" > "$LOCAL_SKILL_PATH"

    echo "[skill-update] ✅ Skill updated from GitHub"
    return 0
}

# Main execution
main() {
    # Update cache timestamp
    echo $(date +%s) > "$CACHE_FILE"

    # Check if we should perform an update
    if ! should_check_for_updates; then
        return 0
    fi

    # Fetch remote version
    remote_content=$(fetch_remote_version) || {
        echo "[skill-update] ⚠️  Could not fetch remote version, skipping update"
        return 0
    }

    # If local skill doesn't exist yet, install it
    if [ ! -f "$LOCAL_SKILL_PATH" ]; then
        apply_update "$remote_content"
        return 0
    fi

    # Compare hashes
    local remote_hash=$(echo "$remote_content" | get_file_hash /dev/stdin 2>/dev/null || echo "")
    local local_hash=$(get_file_hash "$LOCAL_SKILL_PATH" 2>/dev/null || echo "")

    if [ "$remote_hash" != "$local_hash" ] && [ -n "$remote_hash" ]; then
        apply_update "$remote_content"
        return 0
    fi

    # Already up to date
    return 0
}

main
