#!/bin/sh
#
# Configure sytest to use postgres databases, per the env vars.  This is used
# by both the sytest builds and the synapse ones.
#

set -e

cd "/work"

export SQLITE_DB_1=sqlite1
export SQLITE_DB_2=sqlite2

mkdir -p "server-0"
mkdir -p "server-1"

# Write out the configuration for a PostgreSQL Dendrite
# Note: Dendrite can run entirely within a single database as all of the tables have
# component prefixes
cat > "server-0/database.yaml" << EOF
name: sqlite3
args:
    database: $SQLITE_DB_1
EOF

cat > "server-1/database.yaml" << EOF
name: sqlite3
args:
    database: $SQLITE_DB_2
EOF
