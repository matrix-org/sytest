ARG BASE_IMAGE=debian:bookworm

FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND noninteractive

# Install base dependencies that Python or Go would require
RUN apt-get -qq update && apt-get -qq install -y \
    apt-utils \
    build-essential \
    eatmydata \
    git \
    haproxy \
    jq \
    libffi-dev \
    libjpeg-dev \
    libpq-dev \
    libssl-dev \
    libxslt1-dev \
    libz-dev \
    locales \
    perl \
    postgresql-common \
    rsync \
    sqlite3 \
    wget \
    libicu-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Set the default PostgreSQL version to the minimum supported by Synapse:
# https://element-hq.github.io/synapse/latest/deprecation_policy.html
ARG POSTGRESQL_VERSION=13
RUN /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y \
    && apt -qq install -y postgresql-${POSTGRESQL_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# Set up the locales, as the default Debian image only has C, and PostgreSQL needs the correct locales to make a UTF-8 database
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

# Set the locales in the environment
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install some Perl module(s) from Debian repos that have trouble being installed by the below script
RUN apt-get -qq update && apt-get -qq install -y \
    libdbd-pg-perl \
    && rm -rf /var/lib/apt/lists/*

# Copy in the sytest dependencies and install them
# (we expect the docker build context be the sytest repo root, rather than the `docker` folder)
ADD install-deps.pl ./install-deps.pl
ADD cpanfile ./cpanfile
RUN perl ./install-deps.pl -T
RUN rm cpanfile install-deps.pl

# /logs is where we should expect logs to end up
RUN mkdir /logs

# Add the bootstrap file.
ADD docker/bootstrap.sh /bootstrap.sh

# PostgreSQL setup
ENV PGHOST=/var/run/postgresql
ENV PGDATA=$PGHOST/data
ENV PGUSER=postgres

RUN for ver in `ls /usr/lib/postgresql | head -n 1`; do \
    su postgres -c '/usr/lib/postgresql/'$ver'/bin/initdb -E "UTF-8" --lc-collate="C" --lc-ctype="C" --username=postgres'; \
    done

# configure it not to try to listen on IPv6 (it won't work and will cause warnings)
RUN echo "listen_addresses = '127.0.0.1'" >> "$PGDATA/postgresql.conf"
