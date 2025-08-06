#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Add the crypto module's lib directory to LD_LIBRARY_PATH
# The OpenSSL libraries are in lib/crypto-*/priv/lib/
CRYPTO_LIB_DIR="$SCRIPT_DIR/lib//crypto-5.4.2.3/priv/"
export LD_LIBRARY_PATH="$CRYPTO_LIB_DIR:$LD_LIBRARY_PATH"

echo "Setting LD_LIBRARY_PATH to include: $CRYPTO_LIB_DIR"

# Execute the actual jamixir binary with all passed arguments
exec "$SCRIPT_DIR/jamixir.real" "$@" 