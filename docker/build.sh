#! /usr/bin/env bash

set -ex

cd $(dirname $0)

docker build --pull ../ -f base.Dockerfile --build-arg BASE_IMAGE=ubuntu:bionic -t matrixdotorg/sytest:bionic
docker build --pull ../ -f base.Dockerfile --build-arg BASE_IMAGE=debian:buster -t matrixdotorg/sytest:buster
docker build --pull ../ -f base.Dockerfile --build-arg BASE_IMAGE=debian:testing -t matrixdotorg/sytest:testing

# Note: If changing labels also update docker/push.sh and docker/README.md
docker build ../ -f synapse.Dockerfile --build-arg SYTEST_IMAGE_TAG=bionic -t matrixdotorg/sytest-synapse:bionic
docker build ../ -f synapse.Dockerfile --build-arg SYTEST_IMAGE_TAG=buster -t matrixdotorg/sytest-synapse:buster
docker build ../ -f synapse.Dockerfile --build-arg SYTEST_IMAGE_TAG=testing -t matrixdotorg/sytest-synapse:testing

docker build ../ -f dendrite.Dockerfile --build-arg SYTEST_IMAGE_TAG=buster -t matrixdotorg/sytest-dendrite:go113 -t matrixdotorg/sytest-dendrite:latest
