#!/usr/bin/bash
# =============================================================================
# update_whitelist.sh
# Updates an nginx IP whitelist with resolved IPs for a given domain,
# automatically removing stale entries for that domain.
#
# Usage:
#   update_whitelist.sh -d <domain> [-f <file>] [-b]
#
#   -d, --domain  Domain to resolve (required)
#   -f, --file    Path to whitelist file
#                 (default: /swag/nginx/include/ip_access.conf)
#   -b, --backup  Create a timestamped backup before modifying
#   -h, --help    Show this help message
#
# Example:
#   ./update_whitelist.sh -d myservice.example.com -b
# =============================================================================

set -euo pipefail

DOMAIN=""
WHITELIST_FILE="/swag/nginx/include/ip_access.conf"
BACKUP=false

# Helpers
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN:  $*" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

usage() {
  sed -n '/^# Usage:/,/^# =====/{ /^# =====/d; p }' "$0" | sed 's/^# \?//'
  exit 0
}

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domain)  DOMAIN="$2";         shift 2 ;;
    -f|--file)    WHITELIST_FILE="$2"; shift 2 ;;
    -b|--backup)  BACKUP=true;         shift   ;;
    -h|--help)    usage ;;
    *) err "Unknown option: $1" ;;
  esac
done

[[ -z "$DOMAIN" ]] && err "A domain (-d / --domain) is required."

# Dep checks
for cmd in dig grep mktemp; do
  command -v "$cmd" &>/dev/null || err "'$cmd' is not installed or not in PATH."
done

# Resolve the DNS record to IP(s)
log "Resolving DNS for: $DOMAIN"

mapfile -t RESOLVED_IPS < <(
  dig +short A "$DOMAIN" 2>/dev/null \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
)

if [[ ${#RESOLVED_IPS[@]} -eq 0 ]]; then
  err "Could not resolve any A records for '$DOMAIN'. Aborting."
fi

log "Resolved IPs for '$DOMAIN': ${RESOLVED_IPS[*]}"

# Prepare the whitelist file
if [[ ! -f "$WHITELIST_FILE" ]]; then
  warn "Whitelist file '$WHITELIST_FILE' does not exist. Creating it."
  mkdir -p "$(dirname "$WHITELIST_FILE")"
  touch "$WHITELIST_FILE"
fi

# Check if the whitelist already matches the resolved IPs — exit early if so
mapfile -t CURRENT_IPS < <(
  grep -F "# host: ${DOMAIN}" "$WHITELIST_FILE" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | sort || true
)
mapfile -t SORTED_RESOLVED < <(printf '%s\n' "${RESOLVED_IPS[@]}" | sort)

if [[ "${CURRENT_IPS[*]:-}" == "${SORTED_RESOLVED[*]}" ]]; then
  log "Whitelist for '$DOMAIN' is already up to date. No changes made."
  exit 0
fi

# Optionally back up the existing file
if $BACKUP; then
  BACKUP_FILE="${WHITELIST_FILE}.bak.$(date '+%Y%m%d%H%M%S')"
  cp "$WHITELIST_FILE" "$BACKUP_FILE"
  log "Backup created: $BACKUP_FILE"
fi

# Remove stale entries for this domain
STALE_COUNT=$(grep -cF "# host: ${DOMAIN}" "$WHITELIST_FILE" 2>/dev/null || true)
if [[ $STALE_COUNT -gt 0 ]]; then
  TMPFILE=$(mktemp)
  grep -vF "# host: ${DOMAIN}" "$WHITELIST_FILE" > "$TMPFILE"
  mv "$TMPFILE" "$WHITELIST_FILE"
  log "Removed $STALE_COUNT stale entr$([ "$STALE_COUNT" -eq 1 ] && echo 'y' || echo 'ies') for '$DOMAIN'."
fi

# Write freshly resolved IPs above the deny block, or append if not found
ADDED=0
DENY_LINE=$(grep -n "^#Deny everyone else" "$WHITELIST_FILE" | head -1 | cut -d: -f1 || true)

if [[ -n "$DENY_LINE" ]]; then
  TMPFILE=$(mktemp)
  head -n $(( DENY_LINE - 1 )) "$WHITELIST_FILE" > "$TMPFILE"
  for IP in "${RESOLVED_IPS[@]}"; do
    echo "allow ${IP}; # host: ${DOMAIN}" >> "$TMPFILE"
    log "Added: allow ${IP}; # host: ${DOMAIN}"
    (( ADDED++ )) || true
  done
  tail -n +"${DENY_LINE}" "$WHITELIST_FILE" >> "$TMPFILE"
  mv "$TMPFILE" "$WHITELIST_FILE"
else
  warn "Deny block not found; appending to end of file."
  for IP in "${RESOLVED_IPS[@]}"; do
    echo "allow ${IP}; # host: ${DOMAIN}" >> "$WHITELIST_FILE"
    log "Added: allow ${IP}; # host: ${DOMAIN}"
    (( ADDED++ )) || true
  done
fi

log "$ADDED IP(s) written for '$DOMAIN'."
log "Done."
