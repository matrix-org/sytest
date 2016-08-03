#! /bin/bash

echo "Killing processes using $PORT_COUNT ports starting from $BIND_HOST:$PORT_BASE"

# Kill any stray processes that left over from a previous test run
# that are holding onto one of the ports we want to use.
for port in $(seq $PORT_BASE $((PORT_BASE+PORT_COUNT-1))); do
    lsof -i TCP@${BIND_HOST}:$port | grep LISTEN | awk '{print $2}' | xargs -n 1 --no-run-if-empty kill -9
done
