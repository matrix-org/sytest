#!/bin/sh
#
# buildscript for the postgres sytest builds

set -ex

: ${PORT_BASE=8000}
: ${PORT_COUNT=20}

cd "`dirname $0`/.."

./jenkins/prep_synapse.sh
./jenkins/prep_sytest_for_postgres.sh

TOX_BIN="`pwd`/synapse/.tox/py27/bin"
$TOX_BIN/pip install psycopg2
./jenkins/install_and_run.sh --python="$TOX_BIN/python" --port-range ${PORT_BASE}:$((PORT_BASE+PORT_COUNT-1))
