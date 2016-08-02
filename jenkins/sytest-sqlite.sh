#!/bin/sh
#
# buildscript for the sqlite sytest builds

set -ex

cd "`dirname $0`/.."

./jenkins/prep_synapse.sh

./jenkins/install_and_run.sh
