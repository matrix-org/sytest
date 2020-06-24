#! /usr/bin/env bash

set -ex

cd $(dirname $0)
docker build --pull ../ -f base.Dockerfile -t matrixdotorg/sytest:dinsic
docker build ../ -f synapse.Dockerfile -t matrixdotorg/sytest-synapse:dinsic
