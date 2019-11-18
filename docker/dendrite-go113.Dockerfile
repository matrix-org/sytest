FROM matrixdotorg/sytest:buster

# Install Go 1.13
RUN mkdir -p /goroot /gopath
RUN wget -q https://dl.google.com/go/go1.13.4.linux-amd64.tar.gz -O go.tar.gz
RUN tar xf go.tar.gz -C /goroot --strip-components=1
ENV GOROOT=/goroot
ENV GOPATH=/gopath
ENV PATH="/goroot/bin:${PATH}"

# PostgreSQL setup
ENV PGHOST=/var/run/postgresql
ENV PGDATA=$PGHOST/data
ENV PGUSER=postgres

# Turn off all the fsync stuff for postgres
RUN mkdir -p /etc/postgresql/11/main/conf.d/
RUN echo "fsync=off" > /etc/postgresql/11/main/conf.d/fsync.conf
RUN echo "full_page_writes=off" >> /etc/postgresql/11/main/conf.d/fsync.conf

# Initialise the database files
RUN su -c '/usr/lib/postgresql/11/bin/initdb -E "UTF-8" --lc-collate="en_US.UTF-8" --lc-ctype="en_US.UTF-8" --username=postgres' postgres

# This is where we expect Dendrite to be binded to from the host
RUN mkdir -p /src

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "dendrite" ]
