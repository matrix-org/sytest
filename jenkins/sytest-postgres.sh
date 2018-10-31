#!/bin/sh
#
# buildscript for the postgres sytest builds

set -ex

cd "`dirname $0`/.."

./jenkins/clone.sh synapse https://github.com/matrix-org/synapse.git
./synapse/jenkins/prepare_synapse.sh
./jenkins/prep_sytest_for_postgres.sh
./jenkins/install_and_run.sh --python="$WORKSPACE/.tox/py27/bin/python"
