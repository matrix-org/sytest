# SyTest Docker Images

These Dockerfiles create containers for running SyTest in various
configurations. SyTest is not included in these images, but its dependencies
are.

Included currently is:

- matrixdotorg/sytest:stretch and matrixdotorg/sytest:buster, base containers with SyTest dependencies installed
- matrixdotorg/sytest-synapse:py35, a container which will run SyTest against Synapse on Python 3.5 + Stretch
- matrixdotorg/sytest-synapse:py37, a container which will run SyTest against Synapse on Python 3.7 + Buster
- matrixdotorg/sytest-dendrite:go111, a container which will run SyTest against Dendrite on Go 1.11 + Stretch
- matrixdotorg/sytest-dendrite:go113, a container which will run SyTest against Dendrite on Go 1.13 + Buster

## Using the containers

Once pulled from Docker Hub, a container can be run on a homeserver checkout:

### Synapse

```
docker run --rm -it -v /path/to/synapse\:/src -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-synapse:py35
```

### Dendrite

```
docker run --rm -it -v /path/to/dendrite\:/src -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-dendrite
```

This will run on the same branch in SyTest as the checkout, if possible, but
will fall back to using either Synapse or Dendrite's `develop` branch.

If you want to use an existing checkout of SyTest, mount it to `/sytest` inside
the container by adding `-v /path/to/sytest\:/sytest` to the docker command.

You can pass arguments to sytest by adding them at the end of the docker
command. For example, you can use

```
docker run --rm -it ... matrixdotorg/sytest-synapse:py35 tests/20profile-events.pl
```

to run only a single test.

### Environment variables

The following environment variables can be set with `-e` to control the test run:

Synapse:

 * `POSTGRES`: set non-empty to test against a PostgreSQL database instead of sqlite.
 * `WORKERS`: set non-empty to test a worker-mode deployment rather than a
   monolith.
 * `OFFLINE`: set non-empty to avoid updating the python or perl dependencies.
 * `BLACKLIST`: set non-empty to change the default blacklist file to the
   specified path relative to the Synapse directory

Dendrite:

Dendrite does not currently make use of any environment variables.

## Building the containers

The containers are built by executing `build.sh`. You will then have to push
them up to Docker Hub:

```
docker push matrixdotorg/sytest:stretch
docker push matrixdotorg/sytest:buster
docker push matrixdotorg/sytest-synapse:py35
docker push matrixdotorg/sytest-synapse:py37
docker push matrixdotorg/sytest-dendrite:go110
docker push matrixdotorg/sytest-dendrite:go113
```
