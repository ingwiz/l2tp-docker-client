FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        dante-server \
        iproute2 \
        procps \
        passwd \
    && rm -rf /var/lib/apt/lists/*

# danted.conf is generated at container startup by entrypoint.sh
# so that socksmethod can be chosen based on PROXY_USER_* env vars.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
