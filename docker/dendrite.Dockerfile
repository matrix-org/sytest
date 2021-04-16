ARG SYTEST_IMAGE_TAG=buster
FROM matrixdotorg/sytest:${SYTEST_IMAGE_TAG}

ARG GO_VERSION=1.13.7
ARG ARCH=amd64
ENV GO_DOWNLOAD https://dl.google.com/go/go${GO_VERSION}.linux-${ARCH}.tar.gz

RUN mkdir -p /goroot /gopath
RUN mkdir /go-build
RUN wget -q $GO_DOWNLOAD -O go.tar.gz
RUN tar xf go.tar.gz -C /goroot --strip-components=1
ENV GOROOT=/goroot
ENV GOPATH=/gopath
ENV PATH="/goroot/bin:${PATH}"
ENV GOCACHE=/go-build

# This is where we expect Dendrite to be binded to from the host
RUN mkdir -p /src

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "dendrite" ]
