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
