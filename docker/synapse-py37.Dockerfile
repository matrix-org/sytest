FROM matrixdotorg/sytest:buster

RUN apt-get -qq update && apt-get -qq install -y \
    python3 python3-dev python3-virtualenv eatmydata

ENV PYTHON=python3
ENV PGDATA=/var/lib/postgresql/data

RUN su -c '/usr/lib/postgresql/11/bin/initdb -E "UTF-8" --lc-collate="en_US.UTF-8" --lc-ctype="en_US.UTF-8" --username=postgres' postgres

# Turn off all the fsync stuff for postgres
RUN mkdir -p /etc/postgresql/11/main/conf.d/
RUN echo "fsync=off" > /etc/postgresql/11/main/conf.d/fsync.conf
RUN echo "full_page_writes=off" >> /etc/postgresql/11/main/conf.d/fsync.conf

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
