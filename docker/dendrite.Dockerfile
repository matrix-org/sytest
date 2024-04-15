ARG SYTEST_IMAGE_TAG=bullseye
FROM matrixdotorg/sytest:${SYTEST_IMAGE_TAG}

ARG GO_VERSION=1.22.2
ARG TARGETARCH
ENV GO_DOWNLOAD https://dl.google.com/go/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz

RUN mkdir -p /goroot /gopath
RUN wget -q $GO_DOWNLOAD -O go.tar.gz
RUN tar xf go.tar.gz -C /goroot --strip-components=1
ENV GOROOT=/goroot
ENV GOPATH=/gopath
ENV PATH="/goroot/bin:${PATH}"
# This is used in bootstrap.sh to pull in a dendrite specific Sytest branch
ENV SYTEST_DEFAULT_BRANCH dendrite

# This is where we expect Dendrite to be binded to from the host
RUN mkdir -p /src

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "dendrite" ]
