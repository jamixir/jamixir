#!/bin/bash
find -E lib test -regex '.*exs?$' | entr -c mix test $1 
