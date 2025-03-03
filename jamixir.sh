#!/bin/bash

# Initialize variables
ACTION=""
USE_HOST=false
ARGS=""
CONTAINER_ENGINE=""

# Function to display usage
usage() {
    echo "Usage: $0 [-b|--build] [-t|--test] [-H|--host] [-h|--help] [-- <additional args>]"
    echo "  -b, --build   Build the project"
    echo "  -t, --test    Run tests"
    echo "  -H, --host    Use host tools instead of Docker/Podman"
    echo "  -h, --help    Display this help message"
    echo "  -- <args>     Pass additional arguments"
    exit 1
}

# Detect container engine
detect_container_engine() {
    if command -v docker &> /dev/null; then
        if command -v docker-compose &> /dev/null; then
            CONTAINER_ENGINE="docker-compose"
        else
            CONTAINER_ENGINE="docker compose"
        fi
    elif command -v podman &> /dev/null; then
        if command -v podman-compose &> /dev/null; then
            CONTAINER_ENGINE="podman-compose"
        else
            CONTAINER_ENGINE="podman compose"
        fi
    else
        echo "Error: Neither Docker nor Podman found"
        exit 1
    fi
    echo "Using container engine: $CONTAINER_ENGINE"
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--build)
            ACTION="build"
            shift
            ;;
        -t|--test)
            ACTION="test"
            shift
            ;;
        -H|--host)
            USE_HOST=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            ARGS="$*"
            break
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate input
if [ -z "$ACTION" ]; then
    echo "Error: Must specify either --build or --test"
    usage
fi

# Detect container engine if not using host
if [ "$USE_HOST" = false ]; then
    detect_container_engine
fi

# Execute commands
if [ "$USE_HOST" = true ]; then
    case $ACTION in
        "build")
            mix deps.get && mix compile $ARGS
            ;;
        "test")
            mix test $ARGS
            ;;
    esac
else
    case $ACTION in
        "build")
            $CONTAINER_ENGINE build $ARGS
            ;;
        "test")
            $CONTAINER_ENGINE run --rm app mix test $ARGS
            ;;
    esac
fi
