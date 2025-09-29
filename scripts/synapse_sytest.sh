#!/bin/bash -xe
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

mkdir -p /work

# start the redis server, if desired
if [ -n "$WORKERS" ]; then
    /usr/bin/redis-server /etc/redis/redis.conf
fi

# PostgreSQL setup
if [ -n "$MULTI_POSTGRES" ] || [ -n "$POSTGRES" ]; then
    sed -i -r "s/^max_connections.*$/max_connections = 500/" "$PGDATA/postgresql.conf"

    echo "fsync = off" >> "$PGDATA/postgresql.conf"
    echo "full_page_writes = off" >> "$PGDATA/postgresql.conf"

    # Start the database
    echo "starting postgres..."
    su -c 'eatmydata /usr/lib/postgresql/*/bin/pg_ctl -w start -s' postgres
    echo "postgres started"

    # Allow passing in a custom python module name to use for Postgres.
    # Default to "psycopg2".
    PGMODULE="${PGMODULE:-psycopg2}"

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
    name: $PGMODULE
    data_stores:
        - main
    args:
        dbname: pg1_main
        user: postgres
        password: $PGPASSWORD
        host: localhost
        sslmode: disable
state_db:
    name: $PGMODULE
    data_stores:
        - state
    args:
        dbname: pg1_state
        user: postgres
        password: $PGPASSWORD
        host: localhost
        sslmode: disable
EOF

    cat > "/work/server-1/databases.yaml" << EOF
main:
    name: $PGMODULE
    data_stores:
        - main
    args:
        dbname: pg2_main
        user: postgres
        password: $PGPASSWORD
        host: localhost
        sslmode: disable
state_db:
    name: $PGMODULE
    data_stores:
        - state
    args:
        dbname: pg2_state
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

if [ ! -r "$SYNAPSE_SOURCE" ]; then
    echo "Unable to read synapse source at $SYNAPSE_SOURCE" >&2
    exit 1
fi

if [ ! -d "$SYNAPSE_SOURCE" ]; then
    echo "$SYNAPSE_SOURCE must be a source directory" >&2
    exit 1
fi

# Make a copy of the source directory to avoid writing changes to the source
# volume outside the container.
cp -r "$SYNAPSE_SOURCE" /synapse

if [ -n "$OFFLINE" ]; then
    # if we're in offline mode, just put synapse into the virtualenv, and
    # hope that the deps are up-to-date.
    #
    # pip will want to install any requirements for the build system
    # (https://github.com/pypa/pip/issues/5402), so we have to provide a
    # directory of pre-downloaded build requirements.
    #
    # We need both the `--no-deps` and `--no-index` flags for offline mode:
    # `--no-index` only prevents PyPI usage and does not stop pip from
    # installing dependencies from git.
    # `--no-deps` skips installing dependencies but does not stop pip from
    # pulling Synapse's build dependencies from PyPI.
    echo "Installing Synapse using pip in offline mode..."
    /venv/bin/pip install --no-deps --no-index --find-links /pypi-offline-cache /synapse

    if ! /venv/bin/pip check ; then
        echo "There are unmet dependencies which can't be installed in offline mode" >&2
        exit 1
    fi
else
    if [ -f "/synapse/poetry.lock" ]; then
        # Install Synapse and dependencies using poetry, respecting the lockfile.
        # The virtual env will already be populated with dependencies from the
        # Docker build.
        echo "Installing Synapse using poetry..."
        if [ -d /synapse/.venv ]; then
            # There was a virtual env in the source directory for some reason.
            # We want to use our own, so remove it.
            rm -rf /synapse/.venv
        fi
        ln -s -T /venv /synapse/.venv # reuse the existing virtual env
        pushd /synapse
        poetry install -vv --extras all
        popd
    else
        # Install Synapse and dependencies using pip. As of pip 20.1, this will
        # try to build Synapse in-tree, which means writing changes to the source
        # directory.
        # The virtual env will already be populated with dependencies from the
        # Docker build.
        # Keeping this option around allows us to `pip install` from wheel in synapse's
        # "latest dependencies" job.
        echo "Installing Synapse using pip..."
        /venv/bin/pip install -q --upgrade --upgrade-strategy eager --no-cache-dir /synapse[all]
    fi

    /venv/bin/pip install -q --upgrade --no-cache-dir \
        coverage codecov tap.py coverage_enable_subprocess

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

# We set the `--bind-host` as 127.0.0.1 as docker sometimes can't find
# localhost.
RUN_TESTS=(
    perl -I "$SYTEST_LIB" /sytest/run-tests.pl --python=/venv/bin/python --synapse-directory=/src -B "/src/$BLACKLIST" --coverage -O tap --all
    --work-directory="/work" --bind-host 127.0.0.1
)

if [ -n "$ASYNCIO_REACTOR" ]; then
    RUN_TESTS+=(--asyncio-reactor)
fi

if [ -n "$WORKERS" ]; then
    RUN_TESTS+=(-I Synapse::ViaHaproxy --workers)
    RUN_TESTS+=(--redis-host=localhost)
else
    RUN_TESTS+=(-I Synapse)
fi

mkdir -p /logs

TEST_STATUS=0
"${RUN_TESTS[@]}" "$@" >/logs/results.tap &
pid=$!

# make sure that we kill the test runner on SIGTERM, SIGINT, etc
trap 'kill $pid' TERM INT
wait $pid || TEST_STATUS=$?
trap - TERM INT

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

# Generate annotate.md. This is Buildkite-specific.
if [ -n "$BUILDKITE_LABEL" ] && [ $TEST_STATUS -ne 0 ]; then
    # Build the annotation
    perl /sytest/scripts/format_tap.pl /logs/results.tap "$BUILDKITE_LABEL" >/logs/annotate.md
fi

exit $TEST_STATUS
