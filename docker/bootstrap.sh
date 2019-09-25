#!/bin/bash
#
# Fetch sytest, and then run the sytest running script.

set -ex

if [ -d "/sytest" ]; then
    # If the user has mounted in a SyTest checkout, use that.
    echo "Using local sytests..."
else
    if [ -n "BUILDKITE_BRANCH" ]; then
        branch_name=$BUILDKITE_BRANCH
    else
        # Otherwise, try and find out what the branch that the Synapse/Dendrite checkout is using. Fall back to develop if it's not a branch.
        branch_name="$(git --git-dir=/src/.git symbolic-ref HEAD 2>/dev/null)" || branch_name="develop"

        if [ "$1" == "dendrite" ] && [ branch_name == "master" ]; then
            # Dendrite uses master as its main branch. If the branch is master, we probably want sytest develop
            branch_name="develop"
        fi
    fi

    # Try and fetch the branch
    echo "Trying to get same-named sytest branch..."
    wget -q https://github.com/matrix-org/sytest/archive/$branch_name.tar.gz -O sytest.tar.gz || {
        # Probably a 404, fall back to develop
        echo "Using develop instead..."
        wget -q https://github.com/matrix-org/sytest/archive/develop.tar.gz -O sytest.tar.gz
    }

    mkdir -p /sytest
    tar -C /sytest --strip-components=1 -xf sytest.tar.gz
fi

export SYTEST_LIB="/sytest/lib"
SYTEST_SCRIPT="/sytest/docker/$1_sytest.sh"

# dos2unix files that need to be UNIX line ending
dos2unix $SYTEST_SCRIPT
dos2unix /sytest/*.pl

# Run the sytest script
$SYTEST_SCRIPT "${@:2}"
