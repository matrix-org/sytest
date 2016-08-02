#!/bin/sh
#
# buildscript for the sqlite sytest builds

set -ex

: ${PORT_BASE=8000}
: ${PORT_COUNT=100}

cd "`dirname $0`/.."

./jenkins/prep_synapse.sh

TOX_BIN="`pwd`/synapse/.tox/py27/bin"
./jenkins/install_and_run.sh --python="$TOX_BIN/python" --port-range ${PORT_BASE}:$((PORT_BASE+PORT_COUNT-1))
