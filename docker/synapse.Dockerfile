ARG SYTEST_IMAGE_TAG=buster

FROM matrixdotorg/sytest:${SYTEST_IMAGE_TAG}

ARG PYTHON_VERSION=python3
ARG SYSTEM_PIP_INSTALL_SUFFIX=""

ENV DEBIAN_FRONTEND noninteractive

# Ensure we die correctly when using pipes in RUN.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get -qq update && apt-get -qq install -y \
        apt-utils ${PYTHON_VERSION} ${PYTHON_VERSION}-dev ${PYTHON_VERSION}-venv \
        python3-pip eatmydata redis-server curl

ENV RUSTUP_HOME=/rust
ENV CARGO_HOME=/cargo
ENV PATH=/cargo/bin:/rust/bin:$PATH
RUN mkdir /rust /cargo

RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable --profile minimal

# Use the latest version of pip. This pulls in fixes not present in the
# pip version provided by Debian Buster. See
# https://github.com/pypa/setuptools/issues/3457#issuecomment-1190125849
# For now, we need to tell Debian we don't care that we're editing the system python
# installation.
# Some context in https://github.com/pypa/pip/issues/11381#issuecomment-1399263627
RUN ${PYTHON_VERSION} -m pip install -q --upgrade pip ${SYSTEM_PIP_INSTALL_SUFFIX}
RUN ${PYTHON_VERSION} -m pip install -q --no-cache-dir poetry==1.3.2 ${SYSTEM_PIP_INSTALL_SUFFIX}

# As part of the Docker build, we attempt to pre-install Synapse's dependencies
# in the hope that it speeds up the real install of Synapse. To make this work,
# we have to reuse the same virtual env both times. There are three ways to do
# this with poetry:
#  1. Ensure that the Synapse source directory lives in the same path both
#     times. Poetry creates and reuses a virtual env based off the package name
#     ("matrix-synapse") and directory path.
#  2. Configure `virtualenvs.in-project` to `true`. This makes poetry create or
#     use a virtual env at `./.venv` in the source directory.
#  3. Run poetry with a virtual env already active. Poetry will use the active
#     virtual env, if there is one.
# We use the second option and make `.venv` a symlink.
ENV POETRY_VIRTUALENVS_IN_PROJECT true

# /src is where we expect the Synapse source directory to be mounted
RUN mkdir /src

# Download a cache of build dependencies to support offline mode.
# These version numbers are arbitrary and were the latest at the time.
RUN ${PYTHON_VERSION} -m pip download --dest /pypi-offline-cache \
        poetry-core==1.1.0 setuptools==65.3.0 wheel==0.37.1 \
        setuptools-rust==1.5.1

# Create the virtual env upfront so we don't need to keep reinstalling
# dependencies.
RUN wget -q https://github.com/matrix-org/synapse/archive/develop.tar.gz \
        -O /synapse.tar.gz && \
        mkdir /synapse && \
        tar -C /synapse --strip-components=1 -xf synapse.tar.gz && \
        ln -s -T /venv /synapse/.venv && \
        cd /synapse && \
        poetry install -q --no-root --extras all && \
        # Finally clean up the poetry cache and the copy of Synapse.
        # This must be done in the same RUN command, otherwise intermediate layers
        # of the Docker image will contain all the unwanted files we think we've
        # deleted.
        rm -rf `poetry config cache-dir` && \
        rm -rf /synapse && \
        rm /synapse.tar.gz

# Pre-install test dependencies installed by `scripts/synapse_sytest.sh`.
RUN /venv/bin/pip install -q --no-cache-dir \
        coverage codecov tap.py coverage_enable_subprocess

# Poetry runs multiple pip operations in parallel. Unfortunately this results
# in race conditions when a dependency is installed while another dependency
# is being up/downgraded in `scripts/synapse_sytest.sh`. Configure poetry to
# serialize `pip` operations by setting `experimental.new-installer` to a falsy
# value.
# See https://github.com/matrix-org/synapse/issues/12419
# TODO: Once poetry 1.2.0 has been released, use the `installer.max-workers`
#       or `installer.parallel` config option instead.
# poetry has a bug where this environment variable is not converted to a
# boolean, so we choose a falsy string value for it. It's fixed in 1.2.0,
# where we'll be wanting to use `installer.max-workers` anyway.
ENV POETRY_EXPERIMENTAL_NEW_INSTALLER ""

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "synapse" ]
