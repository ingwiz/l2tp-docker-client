FROM debian:bookworm-slim

# strongswan        — starter + charon IKE daemon + stroke plugin (ipsec.conf interface)
# libcharon-extra-plugins — additional cipher / DH algorithms (camellia, AES-GCM, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
        strongswan \
        libcharon-extra-plugins \
        iproute2 \
        iptables \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
