#!/bin/bash
set -e

NODE=$1
shift

LOCK_FILE=".build.lock"

# Open lock file on fd 9
exec 9>"$LOCK_FILE"

# Try to acquire EXCLUSIVE lock (builder election)
if flock --nonblock --exclusive 9; then
    # We are the builder
    echo "Building release..."
    MIX_ENV=tiny mix release --overwrite
    echo "Build complete"

    # Release the lock
    flock --unlock 9
else
    # Not the builder — block and wait until the builder releases the lock
    echo "Waiting for build to complete..."
    flock --shared 9
fi


./run_node.sh "$NODE" "$@"
