ARG DEBIAN_VERSION=buster

FROM matrixdotorg/sytest:${DEBIAN_VERSION}

RUN apt-get -qq update && apt-get -qq install -y \
    python3 python3-dev python3-virtualenv eatmydata \
    redis-server

ENV PYTHON=python3

# /src is where we expect Synapse to be
RUN mkdir /src

# Create the virutal env upfront so we don't need to keep reinstall dependencies
RUN $PYTHON -m virtualenv -p $PYTHON /venv/
RUN /venv/bin/pip install -q --no-cache-dir matrix-synapse[all]
RUN /venv/bin/pip install -q --no-cache-dir lxml psycopg2 coverage codecov

# Uninstall matrix-synapse package so it doesn't collide with the version we try
# and test
RUN /venv/bin/pip uninstall -q --no-cache-dir -y matrix-synapse

ADD docker/pydron.py /pydron.py

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "synapse" ]
