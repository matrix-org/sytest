ARG SYTEST_IMAGE_TAG=buster

FROM matrixdotorg/sytest:${SYTEST_IMAGE_TAG}

ARG PYTHON_VERSION=python3
RUN apt-get -qq update && apt-get -qq install -y \
    ${PYTHON_VERSION} ${PYTHON_VERSION}-dev ${PYTHON_VERSION}-venv \
    ${PYTHON_VERSION}-pip eatmydata redis-server

RUN ${PYTHON_VERSION} -m pip install -q --no-cache-dir poetry==1.1.12

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
RUN poetry config virtualenvs.in-project true

# /src is where we expect the Synapse source directory to be mounted
RUN mkdir /src

# Download a cache of build dependencies to support offline mode.
# `setuptools` and `wheel` are only required for pre-poetry Synapse versions.
# These version numbers are arbitrary and were the latest at the time.
RUN ${PYTHON_VERSION} -m pip download --dest /pypi-offline-cache \
        poetry-core==1.0.8 setuptools==60.10.0 wheel==0.37.1

# TODO: Once poetry lands in the develop branch of Synapse, uncomment these
#       lines and delete the pip version of the virtual env preparation.
# Create the virtual env upfront so we don't need to keep reinstalling
# dependencies.
# RUN wget -q https://github.com/matrix-org/synapse/archive/develop.tar.gz \
#         -O /synapse.tar.gz && \
#     mkdir /synapse && \
#     tar -C /synapse --strip-components=1 -xf synapse.tar.gz && \
#     ln -s -T /venv /synapse/.venv && \
#     cd /synapse && \
#     poetry install -q --no-root --extras all && \
#     # Finally clean up the poetry cache and the copy of Synapse.
#     # This must be done in the same RUN command, otherwise intermediate layers
#     # of the Docker image will contain all the unwanted files we think we've
#     # deleted.
#     rm -rf `poetry config cache-dir` && \
#     rm -rf /synapse && \
#     rm /synapse.tar.gz

# Create the virutal env upfront so we don't need to keep reinstall dependencies
# Manually upgrade pip to ensure it can locate Cryptography's binary wheels
RUN ${PYTHON_VERSION} -m venv /venv && /venv/bin/pip install -U pip
RUN /venv/bin/pip install -q --no-cache-dir matrix-synapse[all]

# Uninstall matrix-synapse package so it doesn't collide with the version we try
# and test
RUN /venv/bin/pip uninstall -q --no-cache-dir -y matrix-synapse

# Pre-install test dependencies installed by `scripts/synapse_sytest.sh`.
RUN /venv/bin/pip install -q --no-cache-dir \
        coverage codecov tap.py coverage_enable_subprocess

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "synapse" ]
