#!/bin/bash
NODE=$1
PORT=$(($NODE+40000))
VERSION=$(grep -o 'version: "[^"]*"' mix.exs | sed 's/version: "//;s/"//')

if [ "$NODE" -eq "0" ]; then
  RPC=--rpc
  LOG=--log=debug
fi

PRIV_DIR=./lib/jamixir-${VERSION}/priv/
cd _build/tiny/rel/jamixir
./jamixir run -k ${PRIV_DIR}/keys/$NODE.json ${RPC} ${LOG} ${DUMP} --chainspec=${PRIV_DIR}/polkajam_chainspec.json  --port $PORT --db db/db${NODE} $2
