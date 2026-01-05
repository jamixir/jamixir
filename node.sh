#!/bin/bash
NODE=$1
PORT=$(($NODE+10001))
MIX_ENV=tiny mix jam -k test/keys/$NODE.json --port $PORT --db db/db${NODE} $2
