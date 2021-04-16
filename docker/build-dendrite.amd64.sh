#! /usr/bin/env bash

set -ex

cd $(dirname $0)

docker build --pull ../ -f base.Dockerfile --build-arg BASE_IMAGE=debian:buster -t matrixdotorg/sytest:buster

docker build ../ -f dendrite.Dockerfile --build-arg SYTEST_IMAGE_TAG=buster -t matrixdotorg/sytest-dendrite:go113 -t matrixdotorg/sytest-dendrite:latest
