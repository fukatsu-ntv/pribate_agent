#!/usr/bin/env bash
# Power Automate HTTP トリガを叩く共通ヘルパー。
# 使い方:
#   ./call_flow.sh <flow-name> '<json-body>'
#   ./call_flow.sh get-unread-mails '{"top": 50}'
#   ./call_flow.sh teams-notify @workflows/<run-id>/teams-payload.json
#
# 環境変数 (.env.powerautomate に書いて source する):
#   PA_UNREAD_MAILS_URL
#   PA_TEAMS_NOTIFY_URL
#   PA_SHARED_SECRET
#
# 出力: フローのレスポンス JSON を stdout に。HTTP ステータスは終了コードに反映。

set -euo pipefail

ENV_FILE="${PA_ENV_FILE:-$(dirname "$0")/../../../.env.powerautomate}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <flow-name> <json-body>" >&2
  echo "  flow-name: get-unread-mails | teams-notify" >&2
  exit 64
fi

FLOW="$1"
BODY="$2"

case "$FLOW" in
  get-unread-mails) URL="${PA_UNREAD_MAILS_URL:-}" ;;
  teams-notify)     URL="${PA_TEAMS_NOTIFY_URL:-}" ;;
  *) echo "unknown flow: $FLOW" >&2; exit 64 ;;
esac

if [[ -z "$URL" ]]; then
  echo "URL for $FLOW is not configured (set in $ENV_FILE)" >&2
  exit 78
fi

if [[ -z "${PA_SHARED_SECRET:-}" ]]; then
  echo "PA_SHARED_SECRET is not set" >&2
  exit 78
fi

# Allow `@path/to/file.json` shorthand for body
DATA_ARG=("-d" "$BODY")
if [[ "$BODY" == @* ]]; then
  DATA_ARG=("--data-binary" "$BODY")
fi

HTTP_STATUS=$(curl -sS -o /tmp/pa_response.$$ -w "%{http_code}" \
  -X POST "$URL" \
  -H "Content-Type: application/json; charset=utf-8" \
  -H "x-claude-secret: $PA_SHARED_SECRET" \
  "${DATA_ARG[@]}")

cat /tmp/pa_response.$$
rm -f /tmp/pa_response.$$

if [[ "$HTTP_STATUS" -ge 400 ]]; then
  echo "" >&2
  echo "HTTP $HTTP_STATUS from $FLOW" >&2
  exit 1
fi
