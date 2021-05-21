#!/bin/sh

set -ex

cd $(dirname $0)

docker push matrixdotorg/sytest:dinsic
docker push matrixdotorg/sytest-synapse:dinsic