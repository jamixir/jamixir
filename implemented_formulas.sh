#!/bin/bash
grep -o "Formula ([0-9ABCDEFGH]\+[.][0-9]\+)" -R --include \*.{ex,exs} * | awk -F'[()]' '{print $2}' | sort -V |uniq
