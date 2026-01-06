#!/bin/bash
NODE=$1
PORT=$(($NODE+10001))
echo Y | MIX_ENV=tiny mix release
VERSION=$(grep -o 'version: "[^"]*"' mix.exs | sed 's/version: "//;s/"//')
PRIV_DIR=./rel/jamixir/lib/jamixir-${VERSION}/priv/
cd _build/tiny/
tar -xzvf jamixir-{$VERSION}.tar.gz
./jamixir run -k ${PRIV_DIR}/keys/$NODE.json --port $PORT --db db/db${NODE} $2