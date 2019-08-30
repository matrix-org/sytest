#! /usr/bin/env bash

set -ex

cd /sytest

# Make sure all Perl deps are installed -- this is done in the docker build so will only install packages added since the last Docker build
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
