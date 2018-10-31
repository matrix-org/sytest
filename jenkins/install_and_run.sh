#!/bin/bash
#
# Installs the dependencies, and then runs the tests. This is used by both
# the sytest builds and the synapse ones.
#

set -ex

export PERL5LIB=$WORKSPACE/perl5/lib/perl5
export PERL_MB_OPT=--install_base=$WORKSPACE/perl5
export PERL_MM_OPT=INSTALL_BASE=$WORKSPACE/perl5

cd "`dirname $0`/.."

./install-deps.pl

: ${PORT_BASE=20000}
: ${PORT_COUNT=100}
: ${BIND_HOST=localhost}

export PORT_BASE
export PORT_COUNT
export BIND_HOST

./jenkins/kill_old_listeners.sh

# If running dendron then give it somewhere to write log files to
mkdir -p var

./run-tests.pl \
    --port-range ${PORT_BASE}:$((PORT_BASE+PORT_COUNT-1)) \
    --bind-host ${BIND_HOST} \
    -O tap \
    --all "$@" \
    > results.tap
