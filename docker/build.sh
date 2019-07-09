#! /usr/bin/env bash

set -e

cd `dirname $0`
docker build ../ -f Dockerfile -t matrixdotorg/sytest
docker build ../ -f Dockerfile-synapsepy2 -t matrixdotorg/sytest-synapse:dinsic
