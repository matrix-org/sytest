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
    mkdir -p /work/jenkins
    for i in install-deps.pl run-tests.pl tap-to-junit-xml.pl jenkins/prep_sytest_for_postgres.sh; do
        dos2unix -n "/sytest/$i" "/work/$i"
    done
    ln -sf /sytest/tests /work
    ln -sf /sytest/keys /work
    SYTEST_LIB="/sytest/lib"
else
    # Otherwise, try and find out what the branch that the Synapse checkout is using. Fall back to dinsic if it's not a branch.
    branch_name="$BUILDKITE_BRANCH" || branch_name="dinsic"

    # Try and fetch the branch
    echo "Trying to get same-named sytest branch (or the dinsic one)..."
    wget -q https://github.com/matrix-org/sytest/archive/$branch_name.tar.gz -O sytest.tar.gz

    mkdir -p /work
    tar -C /work --strip-components=1 -xf sytest.tar.gz
    SYTEST_LIB="/work/lib"
fi

cd /work

# PostgreSQL setup
if [ -n "$POSTGRES" ]
then
    export PGUSER=postgres
    export POSTGRES_DB_1=pg1
    export POSTGRES_DB_2=pg2

    # Start the database
    su -c 'eatmydata /usr/lib/postgresql/9.6/bin/pg_ctl -w -D /var/lib/postgresql/data start' postgres

    # Use the Jenkins script to write out the configuration for a PostgreSQL using Synapse
    jenkins/prep_sytest_for_postgres.sh

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
    /venv/bin/pip install -q --upgrade --no-cache-dir -e /src/
    /venv/bin/pip install -q --upgrade --no-cache-dir \
        lxml psycopg2 coverage codecov tap.py

    # Make sure all Perl deps are installed -- this is done in the docker build
    # so will only install packages added since the last Docker build
    ./install-deps.pl
fi


# Run the tests
>&2 echo "+++ Running tests"

RUN_TESTS=(
    perl -I "$SYTEST_LIB" ./run-tests.pl --python=/venv/bin/python --synapse-directory=/src --coverage -O tap --all
)

TEST_STATUS=0

if [ -n "$WORKERS" ]; then
    RUN_TESTS+=(-I Synapse::ViaHaproxy --dendron-binary=/pydron.py)
else
    RUN_TESTS+=(-I Synapse)
fi

"${RUN_TESTS[@]}" "$@" > results.tap || TEST_STATUS=$?

if [ $TEST_STATUS -ne 0 ]; then
    >&2 echo -e "run-tests \e[31mFAILED\e[0m: exit code $TEST_STATUS"
else
    >&2 echo -e "run-tests \e[32mPASSED\e[0m"
fi

>&2 echo "--- Copying assets"

# Copy out the logs
mkdir -p /logs
cp results.tap /logs/results.tap
rsync --ignore-missing-args -av server-0 server-1 /logs --include "*/" --include="*.log.*" --include="*.log" --exclude="*"

# Write out JUnit for CircleCI
mkdir -p /logs/sytest
perl ./tap-to-junit-xml.pl --puretap --input=/logs/results.tap --output=/logs/sytest/results.xml "SyTest"

if [ -n "$BUILDKITE" ] && [ $TEST_STATUS -ne 0 ]
then
    # Build the annotation
    /venv/bin/python /src/.buildkite/format_tap.py /logs/results.tap "$BUILDKITE_LABEL" >/logs/annotate.md
fi

# Upload coverage to codecov, if running on CircleCI
if [ -n "$CIRCLECI" ]
then
    /venv/bin/coverage combine || true
    /venv/bin/coverage xml || true
    /venv/bin/codecov -X gcov -f coverage.xml
fi

exit $TEST_STATUS
