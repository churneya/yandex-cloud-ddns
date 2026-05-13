FROM debian:12-slim

ARG YC_CLI_INSTALLER_URL="https://storage.yandexcloud.net/yandexcloud-yc/install.sh"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        jq \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "${YC_CLI_INSTALLER_URL}" -o /tmp/yc-install.sh \
    && bash /tmp/yc-install.sh -i /opt/yandex-cloud -n \
    && ln -s /opt/yandex-cloud/bin/yc /usr/local/bin/yc \
    && rm -f /tmp/yc-install.sh

RUN useradd --create-home --shell /usr/sbin/nologin ddns

COPY ddns-yandex.sh /usr/local/bin/ddns-yandex.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod 0755 /usr/local/bin/ddns-yandex.sh /usr/local/bin/healthcheck.sh

USER ddns
WORKDIR /home/ddns

ENV DNS_RECORD_NAME="home.churneya.ru." \
    DNS_RECORD_TYPE="A" \
    DNS_RECORD_TTL="60" \
    CHECK_INTERVAL_SECONDS="900" \
    PUBLIC_IP_URLS="https://api.ipify.org,https://ifconfig.me/ip,https://icanhazip.com,https://checkip.amazonaws.com" \
    DDNS_STATE_FILE="/tmp/ddns-yandex-last-success"

HEALTHCHECK --interval=60s --timeout=10s --start-period=90s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/ddns-yandex.sh"]
