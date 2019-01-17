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

    # Try and fetch the branch
    echo "Trying to get same-named sytest branch..."
    wget -q https://github.com/matrix-org/sytest/archive/$branch_name.tar.gz -O sytest.tar.gz || {
        # Probably a 404, fall back to develop
        echo "Using develop instead..."
        wget -q https://github.com/matrix-org/sytest/archive/develop.tar.gz -O sytest.tar.gz
    }

    tar --strip-components=1 -xf sytest.tar.gz

fi

# PostgreSQL setup
if [ -n "$POSTGRES" ]
then

    export PGHOST=/var/run/postgresql
    export PGDATA=$PGHOST/data
    export PGUSER=dendrite

    # Initialise the database files and start the database
    su -c '/usr/lib/postgresql/9.6/bin/initdb -E "UTF-8" --lc-collate="en_US.UTF-8" --lc-ctype="en_US.UTF-8" --username=postgres' postgres
    su -c '/usr/lib/postgresql/9.6/bin/pg_ctl -w -D /var/lib/postgresql/data start' postgres

    # Write dendrite configuration
    mkdir -p "server-0"
    cat > "server-0/database.yaml" << EOF
    args:
      database: $PGUSER
      host: $PGHOST
    type: pg
EOF

    # Make the test databases
    create_user="CREATE USER dendrite PASSWORD 'itsasecret'"
    su -c 'psql -c "$create_user"' postgres
    su -c 'for i in account device mediaapi syncapi roomserver serverkey federationsender publicroomsapi appservice naffka; do psql -c "CREATE DATABASE $i OWNER dendrite;"; done' postgres

fi

# Make sure all Perl deps are installed -- this is done in the docker build so will only install packages added since the last Docker build
dos2unix ./install-deps.pl
./install-deps.pl

# Run the tests
dos2unix ./run-tests.pl
TEST_STATUS=0
./run-tests.pl -I Dendrite::Monolith -W ../dendrite/testfile -O tap --all "$@" > results.tap || TEST_STATUS=$?

# Copy out the logs
mkdir -p /logs
cp results.tap /logs/results.tap
rsync --ignore-missing-args -av server-0 server-1 /logs --include "*/" --include="*.log.*" --include="*.log" --exclude="*"

# Write out JUnit for CircleCI
mkdir -p /logs/sytest
perl /tap-to-junit-xml.pl --puretap --input=/logs/results.tap --output=/logs/sytest/results.xml "SyTest"

exit $TEST_STATUS
