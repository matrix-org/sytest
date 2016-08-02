#!/bin/sh
#
# check out the relevant branch of synapse, and build it ready for testing

set -ex

cd "`dirname $0`/.."

./jenkins/clone.sh synapse https://github.com/matrix-org/synapse.git
./synapse/jenkins/prepare_synapse.sh
