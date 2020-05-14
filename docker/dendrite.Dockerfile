ARG DEBIAN_VERSION=buster
FROM matrixdotorg/sytest:${DEBIAN_VERSION}

ARG GO_VERSION=1.13.7
ENV GO_DOWNLOAD https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz

RUN mkdir -p /goroot /gopath
RUN wget -q $GO_DOWNLOAD -O go.tar.gz
RUN tar xf go.tar.gz -C /goroot --strip-components=1
ENV GOROOT=/goroot
ENV GOPATH=/gopath
ENV PATH="/goroot/bin:${PATH}"

# This is where we expect Dendrite to be binded to from the host
RUN mkdir -p /src

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "dendrite" ]
