#!/bin/bash
# Download and build dendrite from a given branch, else the "master" branch.

if [ $# -ne 2 ]; then
    echo "Usage: $0 \"branchname\" \"output_dir\""
    exit 1
fi

BRANCH=$1
OUTPUT_DIR=$2
mkdir -p "$OUTPUT_DIR"
(wget -O - https://github.com/matrix-org/dendrite/archive/$BRANCH.tar.gz || wget -O - https://github.com/matrix-org/dendrite/archive/master.tar.gz) | tar -xz --strip-components=1 -C "$OUTPUT_DIR"
cd $OUTPUT_DIR
./build.sh
