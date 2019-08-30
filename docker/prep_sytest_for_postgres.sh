#!/bin/sh
#
# Configure sytest to use postgres databases, per the env vars.  This is used
# by both the sytest builds and the synapse ones.
#

set -e

cd "`dirname $0`/.."

if [ -z "$POSTGRES_DB_1" ]; then
    echo >&2 "Variable POSTGRES_DB_1 not set"
    exit 1
fi

if [ -z "$POSTGRES_DB_2" ]; then
    echo >&2 "Variable POSTGRES_DB_2 not set"
    exit 1
fi

mkdir -p "server-0"
mkdir -p "server-1"

: PGUSER=${PGUSER:=$USER}

# We leave user, password, host blank to use the defaults (unix socket and
# local auth)
cat > "server-0/database.yaml" << EOF
name: psycopg2
args:
    database: $POSTGRES_DB_1
    user: $PGUSER
    password: $PGPASSWORD
    host: localhost
    sslmode: disable
EOF

cat > "server-1/database.yaml" << EOF
name: psycopg2
args:
    database: $POSTGRES_DB_2
    user: $PGUSER
    password: $PGPASSWORD
    host: localhost
    sslmode: disable
EOF
