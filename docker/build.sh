#! /usr/bin/env bash

set -e

cd `dirname $0`
docker build ../ -f Dockerfile -t matrixdotorg/sytest
docker build ../ -f Dockerfile-synapsepy2 -t matrixdotorg/sytest-synapsepy2
docker build ../ -f Dockerfile-synapsepy3 -t matrixdotorg/sytest-synapsepy3
docker build ../ -f Dockerfile-dendrite -t matrixdotorg/sytest-dendrite
