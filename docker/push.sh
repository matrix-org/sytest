#!/bin/sh

set -ex

cd $(dirname $0)

docker push matrixdotorg/sytest:buster
docker push matrixdotorg/sytest:testing

docker push matrixdotorg/sytest-synapse:buster
docker push matrixdotorg/sytest-synapse:testing
