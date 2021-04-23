#! /usr/bin/env bash

set -ex

cd $(dirname $0)

docker build --pull ../ -f base.Dockerfile --build-arg DEBIAN_VERSION=buster -t matrixdotorg/sytest:buster
docker build --pull ../ -f base.Dockerfile --build-arg DEBIAN_VERSION=testing -t matrixdotorg/sytest:testing

# Note: If changing labels also update docker/push.sh and docker/README.md
docker build ../ -f synapse.Dockerfile --build-arg DEBIAN_VERSION=buster -t matrixdotorg/sytest-synapse:buster
docker build ../ -f synapse.Dockerfile --build-arg DEBIAN_VERSION=testing -t matrixdotorg/sytest-synapse:testing

docker build ../ -f dendrite.Dockerfile --build-arg DEBIAN_VERSION=stretch -t matrixdotorg/sytest-dendrite:go113 -t matrixdotorg/sytest-dendrite:latest
