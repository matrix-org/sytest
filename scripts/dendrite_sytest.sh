#!/bin/bash
#
# This script is run by the bootstrap.sh script in the docker image.
#
# It expects to find a built dendrite in /src/bin. It sets up the
# postgres database and runs sytest against dendrite.

set -ex

cd /sytest

mkdir /work

# Make sure all Perl deps are installed -- this is done in the docker build so will only install packages added since the last Docker build
./install-deps.pl

# Start the database
su -c 'eatmydata /usr/lib/postgresql/*/bin/pg_ctl -w -D $PGDATA start' postgres

# Create required databases
su -c 'for i in pg1 pg2 sytest_template; do psql -c "CREATE DATABASE $i;"; done' postgres

export PGUSER=postgres
export POSTGRES_DB_1=pg1
export POSTGRES_DB_2=pg2

# Write out the configuration for a PostgreSQL Dendrite
# Note: Dendrite can run entirely within a single database as all of the tables have
# component prefixes
./scripts/prep_sytest_for_postgres.sh

# Build dendrite
echo >&2 "--- Building dendrite from source"
cd /src
./build.sh
cd -

# Run the tests
echo >&2 "+++ Running tests"

TEST_STATUS=0
mkdir -p /logs
./run-tests.pl -I Dendrite::Monolith -d /src/bin -W /src/sytest-whitelist -O tap --all \
    --work-directory="/work" \
    "$@" > /logs/results.tap || TEST_STATUS=$?

if [ $TEST_STATUS -ne 0 ]; then
    echo >&2 -e "run-tests \e[31mFAILED\e[0m: exit code $TEST_STATUS"
else
    echo >&2 -e "run-tests \e[32mPASSED\e[0m"
fi

# Check for new tests to be added to the test whitelist
/src/show-expected-fail-tests.sh /logs/results.tap /src/sytest-whitelist \
    /src/sytest-blacklist > /work/show_expected_fail_tests_output.txt || TEST_STATUS=$?

echo >&2 "--- Copying assets"

# Copy out the logs
rsync -r --ignore-missing-args --min-size=1B -av /work/server-0 /work/server-1 /logs --include "*/" --include="*.log.*" --include="*.log" --exclude="*"

if [ $TEST_STATUS -ne 0 ]; then
    # Build the annotation
    perl /sytest/scripts/format_tap.pl /logs/results.tap "$BUILDKITE_LABEL" >/logs/annotate.md
    # If show-expected-fail-tests logged something, put it into the annotation
    # Annotations from a failed build show at the top of buildkite, alerting
    # developers quickly as to what needs to change in the black/whitelist.
    cat /work/show_expected_fail_tests_output.txt >> /logs/annotate.md
fi

exit $TEST_STATUS
