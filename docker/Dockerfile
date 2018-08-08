FROM debian:stretch

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -qq update
RUN apt-get -qq install -y build-essential perl wget postgresql postgresql-client libpq-dev libssl-dev libz-dev libffi-dev sqlite3 libjpeg-dev libxslt1-dev git locales

RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# The dockerfile context, when ran by the buildscript, will actually be the
# repo root, not the docker folder
ADD install-deps.pl ./install-deps.pl
ADD cpanfile ./cpanfile
RUN perl ./install-deps.pl

# /logs is where we should expect logs to end up
RUN mkdir /logs
# /test is where sytest will live
RUN mkdir /test
WORKDIR /test
