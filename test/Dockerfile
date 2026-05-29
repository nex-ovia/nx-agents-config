FROM alpine:3.20

# Install all runtime + test dependencies
RUN apk add --no-cache \
    bash \
    python3 \
    jq \
    git \
    coreutils \
    findutils

# git needs a minimal identity for commit operations in tests
RUN git config --global user.email "test@nx-agents-config" && \
    git config --global user.name "nx-agents-test"

WORKDIR /repo
COPY . /repo

CMD ["bash", "/repo/test/suite.sh"]
