#!/usr/bin/env bash
set -euo pipefail
# Synthetic, non-sensitive audio for the on-device integration tests.
# Requires ffmpeg; never used by the app itself.
task_output="${1:-build/audio-fixtures}"
mkdir -p "$task_output"
ffmpeg -hide_banner -loglevel error -y -f lavfi \
  -i 'sine=frequency=440:sample_rate=48000:duration=150' \
  -c:a libmp3lame -b:a 64k "$task_output/source.mp3"
ffmpeg -hide_banner -loglevel error -y -f lavfi \
  -i 'sine=frequency=440:sample_rate=48000:duration=150' \
  -c:a aac -b:a 64k "$task_output/source.m4a"
