#!/bin/bash
set -e

NODE=$1
shift

LOCK_DIR=".buildir.lock"
DONE_FILE=".build.lock.done"

# Use mkdir for atomic lock acquisition (works on macOS and Linux)
if mkdir "$LOCK_DIR" 2>/dev/null; then
    # We are the builder
    rm -f "$DONE_FILE"
    echo "Building release..."
    MIX_ENV=tiny mix release --overwrite
    echo "Build complete"
    
    # Signal completion
    touch "$DONE_FILE"
    
    # Remove the lock directory
    rmdir "$LOCK_DIR"
else
    # Not the builder — wait until build is complete
    echo "Waiting for build to complete..."
    
    # Wait for the done file to appear
    while [ ! -f "$DONE_FILE" ]; do
        sleep 0.5
    done
    
    # Small delay to ensure file is fully written
    sleep 0.2
    echo "Build detected as complete"
fi

./run_node.sh "$NODE" "$@"
