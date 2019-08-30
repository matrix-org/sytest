#!/bin/bash
#
# Fetch sytest, and then run the tests for synapse. The entrypoint for the
# sytest-synapse docker images.

set -ex

# Attempt to find a sytest to use.
# If /sytest exists, it means that a SyTest checkout has been mounted into the Docker image.
if [ -d "/sytest" ]; then
    # If the user has mounted in a SyTest checkout, use that.
    echo "Using local sytests..."

    # create ourselves a working directory and dos2unix some scripts therein
    mkdir -p /work/docker
    for i in install-deps.pl run-tests.pl tap-to-junit-xml.pl docker/prep_sytest_for_postgres.sh; do
        dos2unix -n "/sytest/$i" "/work/$i"
    done
    ln -sf /sytest/tests /work
    ln -sf /sytest/keys /work
    SYTEST_LIB="/sytest/lib"
else
    if [ -n "BUILDKITE_BRANCH" ]; then
        branch_name=$BUILDKITE_BRANCH
    else
        # Otherwise, try and find out what the branch that the Synapse checkout is using. Fall back to develop if it's not a branch.
        branch_name="$(git --git-dir=/src/.git symbolic-ref HEAD 2>/dev/null)" || branch_name="develop"
    fi

    # Try and fetch the branch
    echo "Trying to get same-named sytest branch..."
    wget -q https://github.com/matrix-org/sytest/archive/$branch_name.tar.gz -O sytest.tar.gz || {
        # Probably a 404, fall back to develop
        echo "Using develop instead..."
        wget -q https://github.com/matrix-org/sytest/archive/develop.tar.gz -O sytest.tar.gz
    }

    mkdir -p /work
    tar -C /work --strip-components=1 -xf sytest.tar.gz
    SYTEST_LIB="/work/lib"
fi

cd /work

# PostgreSQL setup
if [ -n "$POSTGRES" ]; then
    export PGUSER=postgres
    export POSTGRES_DB_1=pg1
    export POSTGRES_DB_2=pg2

    # Start the database
    su -c 'eatmydata /usr/lib/postgresql/9.6/bin/pg_ctl -w -D /var/lib/postgresql/data start' postgres

    # Write out the configuration for a PostgreSQL using Synapse
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
    /venv/bin/python /src/.buildkite/format_tap.py /logs/results.tap "$BUILDKITE_LABEL" >/logs/annotate.md
fi

exit $TEST_STATUS
