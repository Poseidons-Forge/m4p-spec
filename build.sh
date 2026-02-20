#!/usr/bin/env bash
# build.sh — Build m4p-spec.pdf using Docker.
set -euo pipefail

IMAGE="m4p-spec-builder"
OUTPUT="m4p-spec.pdf"

docker build -t "$IMAGE" .
docker run --rm -v "$(pwd):/spec" "$IMAGE"

if [ -f "$OUTPUT" ]; then
    echo "Done: $OUTPUT"
else
    echo "ERROR: PDF was not created" >&2
    exit 1
fi
