# SyTest Docker Images

These Dockerfiles create containers for running SyTest in various
configurations. SyTest is not included in these images, but its dependencies
are.

Included currently is:

- matrixdotorg/sytest:stretch and matrixdotorg/sytest:buster, base containers with SyTest dependencies installed
- matrixdotorg/sytest-synapse:py35, a container which will run SyTest against Synapse on Python 3.5 + Stretch
- matrixdotorg/sytest-synapse:py37, a container which will run SyTest against Synapse on Python 3.7 + Buster
- matrixdotorg/sytest-dendrite:go113, a container which will run SyTest against Dendrite on Go 1.13 + Buster

## Using the containers

Once pulled from Docker Hub, a container can be run on a homeserver checkout:

### Synapse

```
docker run --rm -it -v /path/to/synapse\:/src:ro -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-synapse:py35
```

### Dendrite

```
docker run --rm -it -v /path/to/dendrite\:/src:ro -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-dendrite
```

This will run on the same branch in SyTest as the checkout, if possible, but
will fall back to using either Synapse or Dendrite's `develop` branch.

If you want to use an existing checkout of SyTest, mount it to `/sytest` inside
the container by adding `-v /path/to/sytest\:/sytest:ro` to the docker command.

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

Some examples of running Synapse in different configurations:

* Running Synapse in worker mode using
[TCP-replication](https://github.com/matrix-org/synapse/blob/master/docs/tcp_replication.md):

  ```
  docker run --rm -it -e POSTGRES=true -e WORKERS=true -v /path/to/synapse\:/src:ro \
      -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-synapse:py35
  ```

* Running Synapse in worker mode using redis:

  ```
  docker network create testfoobar
  docker run --network testfoobar --name testredis -d redis:5.0
  docker run --network testfoobar --rm -it -v /path/to/synapse\:/src:ro \
       -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-synapse:py35 \
       --redis-host testredis
  # Use `docker start/stop testredis` if you want to explicitly kill redis or start it again after reboot
  ```

Dendrite:

Dendrite does not currently make use of any environment variables.

## Using the local checkout of Sytest

If you would like to run tests with a custom checkout of Sytest, add a volume
to the docker command mounting the checkout to the `/sytest` folder in the
container:

```
docker run --rm -it /path/to/synapse\:/src:ro -v /path/to/where/you/want/logs\:/logs \
    -v /path/to/code/sytest\:/sytest:ro matrixdotorg/sytest-synapse:py35
```

## Building the containers

The containers are built by executing `./build.sh`. You will then have to push
them up to Docker Hub with `./push.sh`.
