#!/usr/bin/env bash
# build.sh — Build m4p-spec.pdf using Docker.
set -euo pipefail

IMAGE="m4p-spec-builder"
OUTPUT="m4p-spec.pdf"

usage() {
    cat <<EOF
Usage: ./build.sh [--skip-figures]

Options:
  --skip-figures   Reuse existing rendered diagrams/markdown and skip render.js
EOF
}

SKIP_FIGURES=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-figures)
            SKIP_FIGURES=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

docker build -t "$IMAGE" .
if [ "$SKIP_FIGURES" -eq 1 ]; then
    docker run --rm -v "$(pwd):/spec" "$IMAGE" sh -c "ln -sfn /opt/node_modules node_modules && bash scripts/build-pdf.sh --skip-figures"
else
    docker run --rm -v "$(pwd):/spec" "$IMAGE"
fi

if [ -f "$OUTPUT" ]; then
    echo "Done: $OUTPUT"
else
    echo "ERROR: PDF was not created" >&2
    exit 1
fi
