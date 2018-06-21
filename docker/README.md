# SyTest Docker

Herein lies a Dockerfile for building a functional SyTest test environment.
SyTest and synapse are cloned from the HEAD of their develop branches. You can
run the tests as follows:

```
cd /path/to/sytest/docker
docker build -t sytest .
docker run --rm -it sytest bash
```

And then at the shell prompt:

```
./run-tests.pl
```

Or other commands as per [the main SyTest
documentation](https://github.com/matrix-org/sytest#running).

Alternatively:

```
docker run --rm sytest <command>
```

Where `<command>` is `./run-tests.pl` or similar.


To use sytest and synapse from the host, so that you can iterate on test
implementation and execute the tests in the container, you can do as follows:

```
docker run --rm -it -v /path/to/sytest:/src/sytest -v /path/to/synapse:/src/synapse sytest bash
```

Then at the prompt, `cd /src/sytest` and then you can run `./run-tests.pl` and
iterate developing a new test or modifying an existing test using your
favourite editor on your host.

#### Windows as a Docker host

If you're using Windows as your Docker host you may need to `apt-get install dos2unix` and run
it on the applicable script (eg: `dos2unix run-tests.pl`). If you're getting "No such file or
directory" when running something, try fixing it with dos2unix first.
