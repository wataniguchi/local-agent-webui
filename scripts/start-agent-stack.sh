#!/bin/bash
# Waits for the Docker daemon to be ready, then runs `docker compose up -d`
# for this project. Intended to be triggered by a launchd LaunchAgent at
# login — see ../launchagent/README for setup.
#
# Safe to run repeatedly: `docker compose up -d` is idempotent, it just
# leaves already-running containers alone.

set -uo pipefail

# EDIT THIS if you saved the project somewhere other than your home directory
PROJECT_DIR="$HOME/local-agent-webui"

LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/local-agent-webui.log"
mkdir -p "$LOG_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log "Startup script triggered, waiting for Docker daemon..."

# Poll for up to ~3 minutes. Docker Desktop takes a while to bring its VM
# and daemon up after login, especially right after a reboot.
ready=false
for i in $(seq 1 90); do
    if docker info >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 2
done

if [ "$ready" != "true" ]; then
    log "Docker daemon never became ready after ~3 minutes — giving up."
    exit 1
fi

log "Docker daemon ready. Bringing up the stack in $PROJECT_DIR..."

if [ ! -d "$PROJECT_DIR" ]; then
    log "ERROR: $PROJECT_DIR does not exist. Edit PROJECT_DIR in this script."
    exit 1
fi

cd "$PROJECT_DIR" || exit 1
docker compose up -d >> "$LOG_FILE" 2>&1
status=$?

if [ $status -eq 0 ]; then
    log "docker compose up -d completed successfully."
else
    log "docker compose up -d FAILED with exit code $status — see above for details."
fi

exit $status
