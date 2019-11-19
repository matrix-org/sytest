#! /usr/bin/env bash

set -e

cd $(dirname $0)
docker build --pull ../ -f base.Dockerfile --build-arg DEBIAN_VERSION=stretch -t matrixdotorg/sytest:stretch
docker build --pull ../ -f base.Dockerfile --build-arg DEBIAN_VERSION=buster -t matrixdotorg/sytest:buster
docker build ../ -f synapse.Dockerfile --build-arg DEBIAN_VERSION=stretch -t matrixdotorg/sytest-synapse:py35
docker build ../ -f synapse.Dockerfile --build-arg DEBIAN_VERSION=buster -t matrixdotorg/sytest-synapse:py37
docker build ../ -f dendrite.Dockerfile --build-arg DEBIAN_VERSION=stretch --build-arg GO_VERSION="1.11.13" -t matrixdotorg/sytest-dendrite:go111 -t matrixdotorg/sytest-dendrite:latest
docker build ../ -f dendrite.Dockerfile --build-arg DEBIAN_VERSION=stretch --build-arg GO_VERSION="1.13.4" -t matrixdotorg/sytest-dendrite:go113
