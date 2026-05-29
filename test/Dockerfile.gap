FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash python3 jq git curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# Install bun (required for opencode)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# Install opencode (best-effort — gap test degrades gracefully if unavailable)
RUN bun install -g opencode-ai 2>/dev/null \
    || echo "[gap-test] opencode not installed — will use Ollama API directly"

RUN git config --global user.email "test@nx-agents-config" && \
    git config --global user.name "nx-agents-test"

WORKDIR /repo
COPY . /repo

CMD ["bash", "/repo/test/gap-test.sh"]
