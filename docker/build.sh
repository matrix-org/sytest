#! /usr/bin/env bash

set -e

cd $(dirname $0)
docker build --pull ../ -f base-stretch.Dockerfile -t matrixdotorg/sytest:stretch
docker build --pull ../ -f base-buster.Dockerfile -t matrixdotorg/sytest:buster
docker build ../ -f synapse-py35.Dockerfile -t matrixdotorg/sytest-synapse:py35
docker build ../ -f synapse-py37.Dockerfile -t matrixdotorg/sytest-synapse:py37
docker build ../ -f dendrite-go110.Dockerfile -t matrixdotorg/sytest-dendrite:go110 -t matrixdotorg/sytest-dendrite:latest
docker build ../ -f dendrite-go113.Dockerfile -t matrixdotorg/sytest-dendrite:go113
