FROM ubuntu:14.04

ENV PERL5LIB=$HOME/lib/perl5
ENV PERL_MB_OPT=--install_base=$HOME
ENV PERL_MM_OPT=INSTALL_BASE=$HOME
ENV DEBIAN_FRONTEND=noninteractive

ADD MyConfig.pm /root/.cpan/CPAN/MyConfig.pm

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y \
        build-essential \
        python2.7-dev \
        libffi-dev \
        python-pip \
        python-setuptools \
        sqlite3 \
        libssl-dev \
        python-virtualenv \
        libjpeg-dev \
        libxslt1-dev \
        git \
        postgresql \
        libpq-dev \
    && cd /root \
    && git clone https://github.com/matrix-org/sytest \
    && git clone https://github.com/matrix-org/synapse \
    && pip install --upgrade setuptools \
    && mkdir -p /root/.cpan/CPAN \
    && cd /root/sytest \
    && ./install-deps.pl \
    && cd ../synapse \
    && git checkout develop \
    && python synapse/python_dependencies.py | xargs -n1 pip install \
    && pip install lxml \
    && python setup.py develop --user \
    && python setup.py test

WORKDIR /root/sytest
