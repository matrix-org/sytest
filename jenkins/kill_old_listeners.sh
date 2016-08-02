#! /bin/bash

# Kill any stray processes that left over from a previous test run
# that are holding onto one of the ports we want to use.
: ${PORT_COUNT=100}
for port in $(seq $PORT_BASE $((PORT_BASE+PORT_COUNT-1))); do
    lsof -i TCP@${BIND_HOST:-localhost}:$port | grep LISTEN | awk '{print $2}' | xargs -n 1 --no-run-if-empty kill -9
done
