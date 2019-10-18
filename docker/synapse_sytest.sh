#!/bin/bash
#
# Run the sytests.

set -ex

cd /sytest

# PostgreSQL setup
if [ -n "$POSTGRES" ]; then
    export PGUSER=postgres
    export POSTGRES_DB_1=pg1
    export POSTGRES_DB_2=pg2

    # Start the database
    su -c 'eatmydata /usr/lib/postgresql/9.6/bin/pg_ctl -w -D /var/lib/postgresql/data start' postgres

    # Write out the configuration for a PostgreSQL using Synapse
    dos2unix docker/prep_sytest_for_postgres.sh
    docker/prep_sytest_for_postgres.sh

    # Make the test databases for the two Synapse servers that will be spun up
    su -c 'psql -c "CREATE DATABASE pg1;"' postgres
    su -c 'psql -c "CREATE DATABASE pg2;"' postgres

fi

if [ -n "$OFFLINE" ]; then
    # if we're in offline mode, just put synapse into the virtualenv, and
    # hope that the deps are up-to-date.
    #
    # (`pip install -e` likes to reinstall setuptools even if it's already installed,
    # so we just run setup.py explicitly.)
    #
    (cd /src && /venv/bin/python setup.py -q develop)
else
    # We've already created the virtualenv, but lets double check we have all
    # deps.
    /venv/bin/pip install -q --upgrade --no-cache-dir -e /src
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
    perl -I "$SYTEST_LIB" ./run-tests.pl --python=/venv/bin/python --synapse-directory=/src -B "/src/$BLACKLIST" --coverage -O tap --all
)

TEST_STATUS=0

if [ -n "$WORKERS" ]; then
    RUN_TESTS+=(-I Synapse::ViaHaproxy --dendron-binary=/pydron.py)
else
    RUN_TESTS+=(-I Synapse)
fi

"${RUN_TESTS[@]}" "$@" >results.tap || TEST_STATUS=$?

if [ $TEST_STATUS -ne 0 ]; then
    echo >&2 -e "run-tests \e[31mFAILED\e[0m: exit code $TEST_STATUS"
else
    echo >&2 -e "run-tests \e[32mPASSED\e[0m"
fi

echo >&2 "--- Copying assets"

# Copy out the logs
mkdir -p /logs
cp results.tap /logs/results.tap
rsync --ignore-missing-args --min-size=1B -av server-0 server-1 /logs --include "*/" --include="*.log.*" --include="*.log" --exclude="*"
cp /.coverage.* /src || true

cd /src
export TOP=/src
/venv/bin/coverage combine

if [ $TEST_STATUS -ne 0 ]; then
    # Build the annotation
    perl ./format_tap.pl /logs/results.tap "$BUILDKITE_LABEL" >/logs/annotate.md
fi

exit $TEST_STATUS
