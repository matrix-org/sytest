#!/bin/bash

set -e

cd "$(dirname $0)"

for v in stretch buster; do
    docker build --pull ../ -f Dockerfile --build-arg DEBIAN_VERSION=$v -t matrixdotorg/sytest:$v
    docker build ../ -f Dockerfile-synapse --build-arg DEBIAN_VERSION=$v -t matrixdotorg/sytest-synapse:$v
done
docker build ../ -f Dockerfile-dendrite -t matrixdotorg/sytest-dendrite:latest

docker tag matrixdotorg/sytest:buster matrixdotorg/sytest:latest
docker tag matrixdotorg/sytest-synapse:stretch matrixdotorg/sytest-synapse:py35
docker tag matrixdotorg/sytest-synapse:buster matrixdotorg/sytest-synapse:py37
