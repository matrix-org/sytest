#! /usr/bin/env bash

set -ex

cd $(dirname $0)
docker build --pull ../ -f base.Dockerfile --build-arg DEBIAN_VERSION=stretch -t matrixdotorg/sytest:stretch
docker build --pull ../ -f base.Dockerfile --build-arg DEBIAN_VERSION=buster -t matrixdotorg/sytest:buster
docker build --pull ../ -f base.Dockerfile --build-arg DEBIAN_VERSION=bullseye -t matrixdotorg/sytest:bullseye
docker build ../ -f synapse.Dockerfile --build-arg DEBIAN_VERSION=stretch -t matrixdotorg/sytest-synapse:py35
docker build ../ -f synapse.Dockerfile --build-arg DEBIAN_VERSION=buster -t matrixdotorg/sytest-synapse:py37
docker build ../ -f synapse.Dockerfile --build-arg DEBIAN_VERSION=bullseye -t matrixdotorg/sytest-synapse:py38
docker build ../ -f dendrite.Dockerfile --build-arg DEBIAN_VERSION=stretch --build-arg GO_VERSION="1.11.13" -t matrixdotorg/sytest-dendrite:go111 
docker build ../ -f dendrite.Dockerfile --build-arg DEBIAN_VERSION=stretch --build-arg GO_VERSION="1.13.7" -t matrixdotorg/sytest-dendrite:go113 -t matrixdotorg/sytest-dendrite:latest
