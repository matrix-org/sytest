#! /usr/bin/env bash

set -e

cd $(dirname $0)
docker build --pull ../ -f Dockerfile -t matrixdotorg/sytest:dinsic
docker build ../ -t matrixdotorg/sytest-synapse:dinsic
