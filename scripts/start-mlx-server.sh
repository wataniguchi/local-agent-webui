#!/bin/bash
# Runs mlx_lm.server as a long-lived process. Unlike scripts/start-agent-stack.sh
# (which is a one-shot "bring the stack up" action), this script IS the
# service — launchd keeps it alive via the KeepAlive setting in the paired
# plist, restarting it automatically if it exits or crashes. No "wait for
# something else to be ready" logic is needed here, since mlx_lm.server has
# no dependency on Docker or anything else in this project.

set -uo pipefail

# Homebrew on Apple Silicon installs to /opt/homebrew; launchd agents don't
# inherit your interactive shell's PATH the way Terminal does, so this
# needs the full path rather than relying on `mlx_lm.server` being found.
# On an Intel Mac, Homebrew instead uses /usr/local/bin — check with
# `which mlx_lm.server` in a terminal and update this if needed.
MLX_LM_BIN="/opt/homebrew/bin/mlx_lm.server"

# EDIT THESE if you want a different model or port than what this project
# is otherwise set up around (see README "Alternative: MLX backend").
MODEL="mlx-community/gemma-4-26b-a4b-it-4bit"
PORT=8081

LOG_DIR="$HOME/Library/Logs"
mkdir -p "$LOG_DIR"

if [ ! -x "$MLX_LM_BIN" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $MLX_LM_BIN not found. Run 'brew install mlx-lm' first, or run 'which mlx_lm.server' in a terminal and update MLX_LM_BIN in this script if Homebrew installs elsewhere on your Mac." >> "$LOG_DIR/local-agent-mlx-server.log"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting mlx_lm.server: model=$MODEL port=$PORT" >> "$LOG_DIR/local-agent-mlx-server.log"

# exec replaces this script's process with mlx_lm.server itself, so launchd
# tracks and manages the real server process directly — important for
# KeepAlive to correctly detect it exiting, and for
# `launchctl kickstart -k` to restart the actual server, not just a wrapper
# shell around it.
exec "$MLX_LM_BIN" --model "$MODEL" --port "$PORT"
