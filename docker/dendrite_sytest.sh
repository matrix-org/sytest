#! /usr/bin/env bash

set -ex

# Attempt to find a sytest to use.
# If /test/run-tests.pl exists, it means that a SyTest checkout has been mounted into the Docker image.
if [ -e "./run-tests.pl" ]
then
    # If the user has mounted in a SyTest checkout, use that. We can tell this by files being in the directory.
    echo "Using local sytests..."
else
    # Otherwise, try and find out what the branch that the Dendrite checkout is using. Fall back to develop if it's not a branch.
    branch_name="$(git --git-dir=/src/.git symbolic-ref HEAD 2>/dev/null)" || branch_name="develop"
    
    # If we're using the master branch of Dendrite, use the develop branch of sytest,
    # as master is Dendrite's development branch
    [ "$branch_name" == "master" ] && branch_name="develop"

    # Try and fetch the branch
    echo "Trying to get same-named sytest branch..."
    wget -q https://github.com/matrix-org/sytest/archive/$branch_name.tar.gz -O sytest.tar.gz || {
        # Probably a 404, fall back to develop
        echo "Using develop instead..."
        wget -q https://github.com/matrix-org/sytest/archive/develop.tar.gz -O sytest.tar.gz
    }

    tar --strip-components=1 -xf sytest.tar.gz

fi

# Make sure all Perl deps are installed -- this is done in the docker build so will only install packages added since the last Docker build
dos2unix ./install-deps.pl
./install-deps.pl

# Start the database
su -c '/usr/lib/postgresql/9.6/bin/pg_ctl -w -D /var/run/postgresql/data start' postgres

# Make the test databases
su -c "psql -c \"CREATE USER dendrite PASSWORD 'itsasecret'\" postgres"
su -c 'for i in account device mediaapi syncapi roomserver serverkey federationsender publicroomsapi appservice naffka sytest_template; do psql -c "CREATE DATABASE $i OWNER dendrite;"; done' postgres

# Write dendrite configuration
mkdir -p "server-0"
cat > "server-0/database.yaml" << EOF
args:
    user: $PGUSER
    database: $PGUSER
    host: $PGHOST
type: pg
EOF

# Run the tests
dos2unix ./run-tests.pl
TEST_STATUS=0
./run-tests.pl -I Dendrite::Monolith -d /src/bin -W /src/testfile -O tap --all "$@" > results.tap || TEST_STATUS=$?

# Check for new tests to be added to testfile
/src/show-expected-fail-tests.sh results.tap /src/testfile || TEST_STATUS=$?

# Copy out the logs
mkdir -p /logs
cp results.tap /logs/results.tap
rsync --ignore-missing-args -av server-0 server-1 /logs --include "*/" --include="*.log.*" --include="*.log" --exclude="*"

# Write out JUnit for CircleCI
mkdir -p /logs/sytest
perl ./tap-to-junit-xml.pl --puretap --input=/logs/results.tap --output=/logs/sytest/results.xml "SyTest"

exit $TEST_STATUS
