#!/bin/sh

set -e

cd $(dirname $0)

docker push matrixdotorg/sytest:stretch
docker push matrixdotorg/sytest:buster
docker push matrixdotorg/sytest:bullseye
docker push matrixdotorg/sytest-synapse:py35
docker push matrixdotorg/sytest-synapse:py37
docker push matrixdotorg/sytest-synapse:py38
docker push matrixdotorg/sytest-dendrite:latest
docker push matrixdotorg/sytest-dendrite:go110
docker push matrixdotorg/sytest-dendrite:go113
