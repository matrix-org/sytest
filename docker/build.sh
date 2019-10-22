#! /usr/bin/env bash

set -e

cd $(dirname $0)
docker build --pull ../ -f Dockerfile -t matrixdotorg/sytest:latest
docker build ../ -f Dockerfile-synapsepy35 -t matrixdotorg/sytest-synapse:py35
docker build ../ -f Dockerfile-dendrite -t matrixdotorg/sytest-dendrite:latest
