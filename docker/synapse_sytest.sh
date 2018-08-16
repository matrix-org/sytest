#! /usr/bin/env bash

set -x

# Attempt to find a sytest to use.
# If /test/run-tests.pl exists, it means that a SyTest checkout has been mounted into the Docker image.
if [ -e "./run-tests.pl" ]
then
    # If the user has mounted in a SyTest checkout, use that. We can tell this by files being in the directory.
    echo "Using local sytests..."
else
    # Otherwise, try and find out what the branch that the Synapse checkout is using. Fall back to develop if it's not a branch.
    branch_name="$(git --git-dir=/src/.git symbolic-ref HEAD 2>/dev/null)" || branch_name="develop"

    # Try and fetch the branch
    echo "Trying to get same-named sytest branch..."
    wget -q https://github.com/matrix-org/sytest/archive/$branch_name.tar.gz -O sytest.tar.gz

    if [ $? -eq 0 ]
    then
        # The download succeeded, use that.
        echo "Using $branch_name!"
    else
        # Probably a 404, fall back to develop
        echo "Using develop instead..."
        wget -q https://github.com/matrix-org/sytest/archive/develop.tar.gz -O sytest.tar.gz
    fi

    tar --strip-components=1 -xf sytest.tar.gz

fi

# PostgreSQL setup
if [ -n "$POSTGRES" ]
then

    export PGDATA=/var/lib/postgresql/data
    export PGUSER=postgres
    export POSTGRES_DB_1=pg1
    export POSTGRES_DB_2=pg2

    # Initialise the database files and start the database
    su -c '/usr/lib/postgresql/9.6/bin/initdb -E "UTF-8" --lc-collate="en_US.UTF-8" --lc-ctype="en_US.UTF-8" --username=postgres' postgres
    su -c '/usr/lib/postgresql/9.6/bin/pg_ctl -w -D /var/lib/postgresql/data start' postgres

    # Use the Jenkins script to write out the configuration for a PostgreSQL using Synapse
    jenkins/prep_sytest_for_postgres.sh

    # Make the test databases for the two Synapse servers that will be spun up
    su -c 'psql -c "CREATE DATABASE pg1;"' postgres
    su -c 'psql -c "CREATE DATABASE pg2;"' postgres

fi

# Build the virtualenv, install extra deps that we will need for the tests
$PYTHON -m virtualenv -p $PYTHON /venv/
/venv/bin/pip install -q --no-cache-dir -e /src/
/venv/bin/pip install -q --no-cache-dir lxml psycopg2

# Make sure all Perl deps are installed -- this is done in the docker build so will only install packages added since the last Docker build
./install-deps.pl

# Run the tests
./run-tests.pl -I Synapse --python=/venv/bin/python -O tap --all > results.tap

TEST_STATUS=$?

# Copy out the logs
cp results.tap /logs/results.tap
cp server-0/homeserver.log /logs/homeserver-0.log
cp server-1/homeserver.log /logs/homeserver-1.log

# Write out JUnit for CircleCI
mkdir -p /logs/sytest
perl /tap-to-junit-xml.pl --puretap --input=/logs/results.tap --output=/logs/sytest/results.xml "SyTest"

exit $TEST_STATUS
