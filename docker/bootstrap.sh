#!/bin/bash
#
# Fetch sytest, and then run the sytest running script.

set -ex

export SYTEST_TARGET="$1"
shift

if [ -d "/sytest" ]; then
    # If the user has mounted in a SyTest checkout, use that.
    echo "Using local sytests"
else
    echo "--- Trying to get same-named sytest branch..."

    if [ -n "BUILDKITE_BRANCH" ]; then
        branch_name=$BUILDKITE_BRANCH
    else
        # Otherwise, try and find out what the branch that the Synapse/Dendrite checkout is using. Fall back to develop if it's not a branch.
        branch_name="$(git --git-dir=/src/.git symbolic-ref HEAD 2>/dev/null)" || branch_name="develop"
    fi

    if [ "$SYTEST_TARGET" == "dendrite" ] && [ "$branch_name" == "master" ]; then
        # Dendrite uses master as its main branch. If the branch is master, we probably want sytest develop
        branch_name="develop"
    fi

    # Try and fetch the branch
    wget -q https://github.com/matrix-org/sytest/archive/$branch_name.tar.gz -O sytest.tar.gz || {
        # Probably a 404, fall back to develop
        echo "Using develop instead..."
        wget -q https://github.com/matrix-org/sytest/archive/develop.tar.gz -O sytest.tar.gz
    }

    mkdir -p /sytest
    tar -C /sytest --strip-components=1 -xf sytest.tar.gz
fi

echo "--- Preparing sytest for ${SYTEST_TARGET}"

export SYTEST_LIB="/sytest/lib"

if [ -x "/sytest/scripts/${SYTEST_TARGET}_sytest.sh" ]; then
    exec "/sytest/scripts/${SYTEST_TARGET}_sytest.sh" "$@"

elif [ -x "/sytest/docker/${SYTEST_TARGET}_sytest.sh" ]; then
    # old branches of sytest used to put the sytest running script in the "/docker" directory
    exec "/sytest/docker/${SYTEST_TARGET}_sytest.sh" "$@"

else
    echo "sytest runner script for ${SYTEST_TARGET} not found" >&2
    exit 1
fi
