#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

error() {
  printf '[%s] ERROR: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    error "Required env variable is not set: ${name}"
    exit 1
  fi
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    error "Required command is not available: ${name}"
    exit 1
  fi
}

validate_integer() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -le 0 ]; then
    error "${name} must be a positive integer"
    exit 1
  fi
}

normalize_record_name() {
  local name="$1"
  if [[ "$name" != *. ]]; then
    printf '%s.\n' "$name"
  else
    printf '%s\n' "$name"
  fi
}

is_ipv4() {
  local ip="$1"
  local octet
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    [ "$octet" -le 255 ] || return 1
  done
}

configure_yc() {
  local key_file
  key_file="$(mktemp)"
  chmod 0600 "$key_file"
  printf '%s' "$YC_SERVICE_ACCOUNT_KEY_JSON" > "$key_file"

  if ! jq -e . "$key_file" >/dev/null 2>&1; then
    rm -f "$key_file"
    error "YC_SERVICE_ACCOUNT_KEY_JSON is not valid JSON"
    exit 1
  fi

  yc config profile create ddns >/dev/null 2>&1 || true
  yc config profile activate ddns >/dev/null
  yc config set service-account-key "$key_file" >/dev/null
  yc config set cloud-id "$YC_CLOUD_ID" >/dev/null
  yc config set folder-id "$YC_FOLDER_ID" >/dev/null
  rm -f "$key_file"
}

get_public_ip() {
  local url ip
  IFS=',' read -r -a urls <<< "$PUBLIC_IP_URLS"
  for url in "${urls[@]}"; do
    url="$(printf '%s' "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$url" ] || continue

    if ip="$(curl -fsSL --max-time "${PUBLIC_IP_TIMEOUT_SECONDS}" "$url" 2>/dev/null | tr -d '[:space:]')"; then
      if is_ipv4 "$ip"; then
        printf '%s\n' "$ip"
        return 0
      fi
      log "Ignoring non-IPv4 response from ${url}"
    else
      log "Public IP provider failed: ${url}"
    fi
  done

  return 1
}

get_dns_ip() {
  local output dns_ip count
  output="$(
    yc dns zone list-records \
      --id "$YC_DNS_ZONE_ID" \
      --record-name "$DNS_RECORD_NAME" \
      --record-type "$DNS_RECORD_TYPE" \
      --format json
  )"

  count="$(printf '%s' "$output" | jq '.record_sets | length')"
  if [ "$count" -eq 0 ]; then
    error "DNS record does not exist: ${DNS_RECORD_NAME} ${DNS_RECORD_TYPE}"
    return 1
  fi

  dns_ip="$(printf '%s' "$output" | jq -r '.record_sets[0].data[0] // empty')"
  if ! is_ipv4 "$dns_ip"; then
    error "DNS record exists but does not contain a valid IPv4 value"
    return 1
  fi

  printf '%s\n' "$dns_ip"
}

update_dns_ip() {
  local ip="$1"
  yc dns zone replace-records \
    --id "$YC_DNS_ZONE_ID" \
    --record "${DNS_RECORD_NAME} ${DNS_RECORD_TTL} ${DNS_RECORD_TYPE} ${ip}" \
    >/dev/null
}

run_once() {
  local public_ip dns_ip

  if ! public_ip="$(get_public_ip)"; then
    error "Could not determine public IPv4 address"
    return 1
  fi

  log "Public IPv4: ${public_ip}"

  if ! dns_ip="$(get_dns_ip)"; then
    return 1
  fi

  log "Current DNS ${DNS_RECORD_NAME} ${DNS_RECORD_TYPE}: ${dns_ip}"

  if [ "$dns_ip" = "$public_ip" ]; then
    log "DNS record is already up to date"
    touch "$DDNS_STATE_FILE"
    return 0
  fi

  log "Updating DNS record: ${dns_ip} -> ${public_ip}"
  update_dns_ip "$public_ip"
  log "DNS record updated"
  touch "$DDNS_STATE_FILE"
}

main() {
  require_command curl
  require_command jq
  require_command yc

  require_env YC_SERVICE_ACCOUNT_KEY_JSON
  require_env YC_CLOUD_ID
  require_env YC_FOLDER_ID
  require_env YC_DNS_ZONE_ID

  DNS_RECORD_NAME="$(normalize_record_name "${DNS_RECORD_NAME:-home.churneya.ru.}")"
  DNS_RECORD_TYPE="${DNS_RECORD_TYPE:-A}"
  DNS_RECORD_TTL="${DNS_RECORD_TTL:-60}"
  CHECK_INTERVAL_SECONDS="${CHECK_INTERVAL_SECONDS:-900}"
  PUBLIC_IP_URLS="${PUBLIC_IP_URLS:-https://api.ipify.org,https://ifconfig.me/ip,https://icanhazip.com,https://checkip.amazonaws.com}"
  PUBLIC_IP_TIMEOUT_SECONDS="${PUBLIC_IP_TIMEOUT_SECONDS:-10}"
  DDNS_STATE_FILE="${DDNS_STATE_FILE:-/tmp/ddns-yandex-last-success}"

  if [ "$DNS_RECORD_TYPE" != "A" ]; then
    error "Only A records are supported"
    exit 1
  fi

  validate_integer DNS_RECORD_TTL "$DNS_RECORD_TTL"
  validate_integer CHECK_INTERVAL_SECONDS "$CHECK_INTERVAL_SECONDS"
  validate_integer PUBLIC_IP_TIMEOUT_SECONDS "$PUBLIC_IP_TIMEOUT_SECONDS"

  log "Starting Yandex Cloud DDNS updater for ${DNS_RECORD_NAME} ${DNS_RECORD_TYPE}"
  configure_yc
  log "Yandex Cloud CLI configured for folder ${YC_FOLDER_ID}"

  while true; do
    if ! run_once; then
      error "DDNS check failed; retrying after ${CHECK_INTERVAL_SECONDS}s"
    fi
    sleep "$CHECK_INTERVAL_SECONDS"
  done
}

main "$@"
