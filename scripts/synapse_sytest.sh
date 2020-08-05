#!/bin/bash
#
# This script is run by the bootstrap.sh script in the docker image.
#
# It expects to find the synapse source in /src, and a virtualenv in /venv.
# It installs synapse into the virtualenv, configures sytest according to the
# env vars, and runs sytest.
#

# Run the sytests.

set -e

cd "$(dirname $0)/.."

mkdir /work

# PostgreSQL setup
if [ -n "$MULTI_POSTGRES" ] || [ -n "$POSTGRES" ]; then
    sed -i -r "s/^max_connections.*$/max_connections = 500/" "$PGDATA/postgresql.conf"

    echo "fsync = off" >> "$PGDATA/postgresql.conf"
    echo "full_page_writes = off" >> "$PGDATA/postgresql.conf"

    # Start the database
    echo "starting postgres..."
    su -c 'eatmydata /usr/lib/postgresql/*/bin/pg_ctl -w start -s' postgres
    echo "postgres started"
fi

# Now create the databases
if [ -n "$MULTI_POSTGRES" ]; then
    # In this mode we want to run synapse against multiple split out databases.

    # Make the test databases for the two Synapse servers that will be spun up
    su -c psql postgres <<EOF
CREATE DATABASE pg1_main;
CREATE DATABASE pg1_state;
CREATE DATABASE pg2_main;
CREATE DATABASE pg2_state;
EOF

    mkdir -p "/work/server-0"
    mkdir -p "/work/server-1"

    # We leave user, password, host blank to use the defaults (unix socket and
    # local auth)
    cat > "/work/server-0/databases.yaml" << EOF
main:
    name: psycopg2
    data_stores:
        - main
    args:
        database: pg1_main
        user: postgres
        password: $PGPASSWORD
        host: localhost
        sslmode: disable
state_db:
    name: psycopg2
    data_stores:
        - state
    args:
        database: pg1_state
        user: postgres
        password: $PGPASSWORD
        host: localhost
        sslmode: disable
EOF

    cat > "/work/server-1/databases.yaml" << EOF
main:
    name: psycopg2
    data_stores:
        - main
    args:
        database: pg2_main
        user: postgres
        password: $PGPASSWORD
        host: localhost
        sslmode: disable
state_db:
    name: psycopg2
    data_stores:
        - state
    args:
        database: pg2_state
        user: postgres
        password: $PGPASSWORD
        host: localhost
        sslmode: disable
EOF

elif [ -n "$POSTGRES" ]; then
    # Env vars used by prep_sytest_for_postgres script.
    export PGUSER=postgres
    export POSTGRES_DB_1=pg1
    export POSTGRES_DB_2=pg2

    # Write out the configuration for a PostgreSQL using Synapse
    ./scripts/prep_sytest_for_postgres.sh

    # Make the test databases for the two Synapse servers that will be spun up
    su -c 'psql -c "CREATE DATABASE pg1;"' postgres
    su -c 'psql -c "CREATE DATABASE pg2;"' postgres

fi

# default value for SYNAPSE_SOURCE
: ${SYNAPSE_SOURCE:=/src}

# if we're running against a source directory, turn it into a tarball.  pip
# will then unpack it to a temporary location, and build it.  (As of pip 20.1,
# it will otherwise try to build it in-tree, which means writing changes to the
# source volume outside the container.)
#
if [ -d "$SYNAPSE_SOURCE" ]; then
    echo "Creating tarball from synapse source"
    tar -C "$SYNAPSE_SOURCE" -czf /tmp/synapse.tar.gz \
        synapse scripts setup.py README.rst synctl MANIFEST.in
    SYNAPSE_SOURCE="/tmp/synapse.tar.gz"
elif [ ! -r "$SYNAPSE_SOURCE" ]; then
    echo "Unable to read synapse source at $SYNAPSE_SOURCE" >&2
    exit 1
fi

if [ -n "$OFFLINE" ]; then
    # if we're in offline mode, just put synapse into the virtualenv, and
    # hope that the deps are up-to-date.
    #
    # --no-use-pep517 works around what appears to be a pip issue
    # (https://github.com/pypa/pip/issues/5402 possibly) where pip wants
    # to reinstall any requirements for the build system, even if they are
    # already installed.
    /venv/bin/pip install --no-index --no-use-pep517 "$SYNAPSE_SOURCE"
else
    # We've already created the virtualenv, but lets double check we have all
    # deps.
    /venv/bin/pip install -q --upgrade --no-cache-dir "$SYNAPSE_SOURCE"[redis]
    /venv/bin/pip install -q --upgrade --no-cache-dir \
        lxml psycopg2 coverage codecov tap.py coverage_enable_subprocess

    # Make sure all Perl deps are installed -- this is done in the docker build
    # so will only install packages added since the last Docker build
    ./install-deps.pl
fi

if [ -z "$BLACKLIST" ]; then
    BLACKLIST=sytest-blacklist
fi

# Run the tests
echo >&2 "+++ Running tests"

export COVERAGE_PROCESS_START="/src/.coveragerc"

RUN_TESTS=(
    perl -I "$SYTEST_LIB" /sytest/run-tests.pl --python=/venv/bin/python --synapse-directory=/src -B "/src/$BLACKLIST" --coverage -O tap --all
    --work-directory="/work"
)

if [ -n "$WORKERS" ]; then
    RUN_TESTS+=(-I Synapse::ViaHaproxy --dendron-binary=/pydron.py)
else
    RUN_TESTS+=(-I Synapse)
fi

mkdir -p /logs

TEST_STATUS=0
"${RUN_TESTS[@]}" "$@" >/logs/results.tap || TEST_STATUS=$?

if [ $TEST_STATUS -ne 0 ]; then
    echo >&2 -e "run-tests \e[31mFAILED\e[0m: exit code $TEST_STATUS"
else
    echo >&2 -e "run-tests \e[32mPASSED\e[0m"
fi

echo >&2 "--- Copying assets"

# Copy out the logs
rsync --ignore-missing-args --min-size=1B -av /work/server-0 /work/server-1 /logs --include "*/" --include="*.log.*" --include="*.log" --exclude="*"
#cp /.coverage.* /src || true

#cd /src
#export TOP=/src
#/venv/bin/coverage combine

if [ $TEST_STATUS -ne 0 ]; then
    # Build the annotation
    perl /sytest/scripts/format_tap.pl /logs/results.tap "$BUILDKITE_LABEL" >/logs/annotate.md
fi

exit $TEST_STATUS
