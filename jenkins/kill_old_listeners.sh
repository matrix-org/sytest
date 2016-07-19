#! /bin/bash

# Kill any stray processes that left over from a previous test run
# that are holding onto one of the ports we want to use.
for port in $(seq $PORT_BASE $((PORT_BASE+PORT_COUNT-1))); do
    lsof -i TCP:$port | grep LISTEN | awk '{print $2}' | xargs kill -9
done
