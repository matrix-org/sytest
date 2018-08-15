# SyTest Docker Images

These Dockerfiles create containers for running SyTest in various configurations. SyTest is not included in these images, but its dependencies are.

Included currently is:

- matrixdotorg/sytest, a base container with SyTest dependencies installed
- matrixdotorg/sytest-synapsepy2, a container which will run SyTest against Synapse on Python 2.7
- matrixdotorg/sytest-synapsepy3, a container which will run SyTest against Synapse on Python 3.5

## Using the Synapse containers

Once pulled from Docker Hub, the container can be run on a Synapse checkout:

```
$ docker run --rm -it -v /path/to/synapse\:/src -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-synapsepy2
```

This will run on the same branch in SyTest as the Synapse checkout, if possible, but will fall back to using develop.

If you want to use an existing checkout of SyTest, mount it to `/test` inside the container by adding `-v /path/to/sytest\:/test` to the docker command.

If you want to test against a PostgreSQL database, pass `-e POSTGRES=1` to the docker command.

## Building the containers

The containers are built by executing `build.sh`. You will then have to push them up to Docker Hub:

```
$ docker push matrixdotorg/sytest
$ docker push matrixdotorg/sytest-synapsepy2
$ docker push matrixdotorg/sytest-synapsepy3
```
