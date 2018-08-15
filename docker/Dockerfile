FROM debian:stretch

ENV DEBIAN_FRONTEND noninteractive

# Install base dependencies that Python or Go would require
RUN apt-get -qq update
RUN apt-get -qq install -y build-essential perl wget postgresql postgresql-client libpq-dev libssl-dev libz-dev libffi-dev sqlite3 libjpeg-dev libxslt1-dev git locales

# Set up the locales, as the default Debian image only has C, and PostgreSQL needs the correct locales to make a UTF-8 database
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

# Set the locales in the environment
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Copy in the sytest dependencies and install them
# The dockerfile context, when run by the buildscript, will actually be the
# repo root, not the docker folder
ADD install-deps.pl ./install-deps.pl
ADD cpanfile ./cpanfile
RUN perl ./install-deps.pl
RUN rm cpanfile install-deps.pl

# /logs is where we should expect logs to end up
RUN mkdir /logs
# /test is where sytest will live
RUN mkdir /test
WORKDIR /test
