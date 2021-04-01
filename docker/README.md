# SyTest Docker Images

These Dockerfiles create containers for running SyTest in various
configurations. SyTest is not included in these images, but its dependencies
are.

Included currently is:

- `matrixdotorg/sytest` Base container with SyTest dependencies installed
    - Tagged by underlying Debian image: `buster` or `testing`
- `matrixdotorg/sytest-synapse`: Runs SyTest against Synapse
    - Tagged by underlying Debian image: `buster` or `testing`
- `matrixdotorg/sytest-dendrite:go113`: Runs SyTest against Dendrite on Go 1.13
    - Currently uses Debian 10 (Buster) as its base image

## Target-specific details

### Synapse

The `sytest-synapse` images expect a checkout of the synapse git repository to
be mounted at `/src`; additionally, server logs will be written to `/logs`, so
it is useful to mount a volume there too.

For example:

```
docker run --rm -it -v /path/to/synapse\:/src:ro -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-synapse:buster
```

The following environment variables can be set with `-e` to control the test run:

 * `POSTGRES`: set non-empty to test against a PostgreSQL database instead of sqlite.
 * `WORKERS`: set non-empty to test a worker-mode deployment rather than a
   monolith. Requires `POSTGRES`.
 * `REDIS`: set non-empty to use redis replication rather than old
   TCP. Requires `WORKERS`.
 * `OFFLINE`: set non-empty to avoid updating the python or perl dependencies.
 * `BLACKLIST`: set non-empty to change the default blacklist file to the
   specified path relative to the Synapse directory
 * `TIMEOUT_FACTOR`: sets a number that test timeouts are multiplied by.

Some examples of running Synapse in different configurations:

* Running Synapse in worker mode using
[TCP-replication](https://github.com/matrix-org/synapse/blob/master/docs/tcp_replication.md):

  ```
  docker run --rm -it -e POSTGRES=1 -e WORKERS=1 -v /path/to/synapse\:/src:ro \
      -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-synapse:buster
  ```

* Running Synapse in worker mode using redis:

  ```
  docker run --rm -it -e POSTGRES=1 -e WORKERS=1 -e REDIS=1 \
       -v /path/to/synapse\:/src:ro \
       -v /path/to/where/you/want/logs\:/logs \
       matrixdotorg/sytest-synapse:buster
  ```

### Dendrite

The `sytest-dendrite` images expect a checkout of the dendrite git repository to
be mounted at `/src`; additionally, server logs will be written to `/logs`, so
it is useful to mount a volume there too.

```
docker run --rm -it -v /path/to/dendrite\:/src:ro -v /path/to/where/you/want/logs\:/logs matrixdotorg/sytest-dendrite
```

## Using the local checkout of Sytest

By default, the images download an appropriate branch of Sytest. (Normally
either a branch with the same name as that of the target homeserver, or
`develop`).

If you would like to run tests with an existing checkout of Sytest, add a
volume to the docker command mounting the checkout to the `/sytest` folder in
the container:

```
docker run --rm -it -v /path/to/synapse\:/src:ro -v /path/to/where/you/want/logs\:/logs \
    -v /path/to/code/sytest\:/sytest:ro matrixdotorg/sytest-synapse:buster
```

## Running a single test file, and other sytest commandline options

You can pass arguments to sytest by adding them at the end of the
docker command. For example:

```
docker run --rm -it ... matrixdotorg/sytest-synapse:buster tests/20profile-events.pl
```

## Building the containers

The containers are built by executing `./build.sh`. You will then have to push
them up to Docker Hub with `./push.sh`.

## Loading sytest plugins at start

To utilize sytest plugins and automatically load them on start set the `PLUGINS` environment variable.
This should be one or more URLs to tar.gz files separated by whitespaces.

The bootstrap script will search for `${SYTEST_TARGET}_sytest.sh` in all plugins. This can be used to
execute custom scripts like the ones in `/scripts/`

```
docker run --rm -it -e PLUGINS="https://host/path/to/hs_plugin.tar.gz https://host2/path/to/output_plugin.tar.gz"
```
