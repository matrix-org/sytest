#!/bin/sh
#
# check out the relevant branch of synapse, and build it ready for testing

set -ex

cd "`dirname $0`/.."

# update our clone of synapse
if [ ! -d .synapse-base ]; then
  git clone https://github.com/matrix-org/synapse.git .synapse-base --mirror
else
  (cd .synapse-base; git fetch -p)
fi
rm -rf synapse
git clone .synapse-base synapse --shared

: ${GIT_BRANCH:="origin/$(git rev-parse --abbrev-ref HEAD)"}


cd synapse

# check out the relevant branch of synapse
git checkout "${GIT_BRANCH}" || (
    echo >&2 "No ref ${GIT_BRANCH} found, falling back to develop"
    git checkout develop
)

# set up the virtualenv
tox -e py27 --notest -v
