# Extends the official Open Terminal image with compiler toolchains it
# doesn't ship by default. Layered rather than replacing the base image, so
# you keep everything Open Terminal itself provides (the API server, its
# tool endpoints, pre-installed Python/data-science stack, etc.) and only
# add what's missing.
#
# NOTE: this assumes a Debian/Ubuntu base (apt-get). If the `cat
# /etc/os-release` check in the README shows something else (e.g. Alpine),
# swap the RUN line below for the matching package manager (apk add --no-cache
# build-base openjdk21-jdk instead).
FROM ghcr.io/open-webui/open-terminal:latest

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    default-jdk \
    && rm -rf /var/lib/apt/lists/*

# Drop back to the base image's own non-root user rather than staying root.
# "user" is a best guess based on the /home/user path this project already
# mounts the workspace into — VERIFY this before building:
#   docker inspect --format='{{.Config.User}}' ghcr.io/open-webui/open-terminal:latest
# and replace the line below if it reports something different (or remove
# this USER line entirely if the base image reports empty/root, meaning it
# runs as root by default).
USER user
