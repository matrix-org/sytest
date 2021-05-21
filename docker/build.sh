#! /usr/bin/env bash

set -ex

cd $(dirname $0)

docker build --pull ../ -f base.Dockerfile --build-arg DEBIAN_VERSION=buster -t matrixdotorg/sytest:dinsic
docker build ../ -f synapse.Dockerfile --build-arg DEBIAN_VERSION=buster -t matrixdotorg/sytest-synapse:dinsic
