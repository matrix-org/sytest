#!/bin/sh
#
# buildscript for the postgres sytest builds

set -ex

: ${PORT_BASE=8000}

cd "`dirname $0`/.."

if [[ -z "$POSTGRES_DB_1" ]]; then
    echo >&2 "Variable POSTGRES_DB_1 not set"
    exit 1
fi

if [[ -z "$POSTGRES_DB_2" ]]; then
    echo >&2 "Variable POSTGRES_DB_2 not set"
    exit 1
fi

mkdir -p "localhost-$(($PORT_BASE + 1))"
mkdir -p "localhost-$(($PORT_BASE + 2))"

cat > localhost-$(($PORT_BASE + 1))/database.yaml << EOF
name: psycopg2
args:
    database: $POSTGRES_DB_1
    user: $POSTGRES_USER_1
    password: $POSTGRES_PASS_1
    host: $POSTGRES_HOST_1
EOF

cat > localhost-$(($PORT_BASE + 2))/database.yaml << EOF
name: psycopg2
args:
    database: $POSTGRES_DB_2
EOF

./jenkins/prep_synapse.sh

TOX_BIN="`pwd`/synapse/.tox/py27/bin"
./jenkins/install_and_run.sh --python="$TOX_BIN/python" --port-base ${PORT_BASE}
