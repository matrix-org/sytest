#!/bin/sh
#
# buildscript for the sqlite sytest builds

set -ex

cd "`dirname $0`/.."

./jenkins/clone.sh synapse https://github.com/matrix-org/synapse.git
./synapse/jenkins/prepare_synapse.sh
./jenkins/install_and_run.sh
