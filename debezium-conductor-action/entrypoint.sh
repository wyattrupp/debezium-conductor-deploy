#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="$1"
URL_DEV="$2"
URL_STAGE="$3"
URL_PROD="$4"
TOKEN_DEV="$5"
TOKEN_STAGE="$6"
TOKEN_PROD="$7"
CONFIGS_ROOT="$8"

# === Map environment ===
case "$ENVIRONMENT" in
  dev)
    CONDUCTOR_URL="$URL_DEV"
    API_TOKEN="$TOKEN_DEV"
    ;;
  stage)
    CONDUCTOR_URL="$URL_STAGE"
    API_TOKEN="$TOKEN_STAGE"
    ;;
  prod)
    CONDUCTOR_URL="$URL_PROD"
    API_TOKEN="$TOKEN_PROD"
    ;;
  *)
    echo "❌ Invalid environment: $ENVIRONMENT"
    exit 1
    ;;
esac

if [[ -z "$CONDUCTOR_URL" || -z "$API_TOKEN" ]]; then
  echo "❌ Missing URL or API token for $ENVIRONMENT"
  exit 1
fi

echo "🌍 Environment: $ENVIRONMENT"
echo "🔗 Conductor URL: $CONDUCTOR_URL"

SOURCES_PATH="$CONFIGS_ROOT/$ENVIRONMENT/sources/*.json"
PIPELINES_PATH="$CONFIGS_ROOT/$ENVIRONMENT/pipelines/*.json"

# === Initialize logs ===
LOG_FILE="debezium_deploy_log.json"
echo '{"sources":[],"pipelines":[],"rolled_back":[]}' > "$LOG_FILE"

NEW_SOURCES=()
NEW_PIPELINES=()

rollback() {
  echo "⚠️ Rolling back newly created resources..."
  for src in "${NEW_SOURCES[@]}"; do
    echo "🧨 Deleting source: $src"
    curl -s -X DELETE -H "Authorization: Bearer $API_TOKEN" "$CONDUCTOR_URL/sources/$src" >/dev/null || true
    jq --arg s "$src" '.rolled_back += [{"type":"source","name":$s}]' "$LOG_FILE" > tmp.$$.json && mv tmp.$$.json "$LOG_FILE"
  done

  for pipe in "${NEW_PIPELINES[@]}"; do
    echo "🧨 Deleting pipeline: $pipe"
    curl -s -X DELETE -H "Authorization: Bearer $API_TOKEN" "$CONDUCTOR_URL/pipelines/$pipe" >/dev/null || true
    jq --arg p "$pipe" '.rolled_back += [{"type":"pipeline","name":$p}]' "$LOG_FILE" > tmp.$$.json && mv tmp.$$.json "$LOG_FILE"
  done
  echo "Rollback complete."
}

trap 'echo "❌ Error occurred. Initiating rollback..."; rollback; exit 1' ERR

# === Validate configs ===
echo "🧩 Validating configuration files..."
VALID=true
for file in $SOURCES_PATH $PIPELINES_PATH; do
  [[ -f "$file" ]] || continue
  if ! jq empty "$file" >/dev/null 2>&1; then
    echo "❌ Invalid JSON: $file"
    VALID=false
  fi
done
[[ "$VALID" = true ]] || { echo "🚫 Config validation failed."; exit 1; }
echo "✅ Configs valid."

# === Helper function ===
send_request() {
  local method=$1
  local url=$2
  local data_file=$3

  local response
  response=$(curl -s -w "\n%{http_code}" -X "$method" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$data_file" \
    "$url")

  local body=$(echo "$response" | head -n1)
  local code=$(echo "$response" | tail -n1)

  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    echo "❌ Request failed: $url HTTP $code"
    echo "Response: $body"
    return 1
  fi

  if echo "$body" | jq -e '.error' >/dev/null 2>&1; then
    echo "❌ API error: $(echo "$body" | jq -r '.error')"
    return 1
  fi

  return 0
}

# === Register sources ===
echo "📦 Registering sources..."
for file in $SOURCES_PATH; do
  [[ -f "$file" ]] || continue
  SOURCE_NAME=$(jq -r '.name' "$file")
  echo "🔹 Processing source: $SOURCE_NAME"

  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $API_TOKEN" "$CONDUCTOR_URL/sources/$SOURCE_NAME")

  if [[ "$STATUS" = "200" ]]; then
    send_request "PUT" "$CONDUCTOR_URL/sources/$SOURCE_NAME" "$file" || exit 1
    jq --arg s "$SOURCE_NAME" '.sources += [{"name":$s,"action":"updated"}]' "$LOG_FILE" > tmp.$$.json && mv tmp.$$.json "$LOG_FILE"
  else
    send_request "POST" "$CONDUCTOR_URL/sources" "$file" || exit 1
    NEW_SOURCES+=("$SOURCE_NAME")
    jq --arg s "$SOURCE_NAME" '.sources += [{"name":$s,"action":"created"}]' "$LOG_FILE" > tmp.$$.json && mv tmp.$$.json "$LOG_FILE"
  fi
done

# === Register pipelines ===
echo "🔗 Registering pipelines..."
for file in $PIPELINES_PATH; do
  [[ -f "$file" ]] || continue
  PIPE_NAME=$(jq -r '.name' "$file")
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $API_TOKEN" "$CONDUCTOR_URL/pipelines/$PIPE_NAME")

  if [[ "$STATUS" = "200" ]]; then
    send_request "PUT" "$CONDUCTOR_URL/pipelines/$PIPE_NAME" "$file" || exit 1
    jq --arg p "$PIPE_NAME" '.pipelines += [{"name":$p,"action":"updated"}]' "$LOG_FILE" > tmp.$$.json && mv tmp.$$.json "$LOG_FILE"
  else
    send_request "POST" "$CONDUCTOR_URL/pipelines" "$file" || exit 1
    NEW_PIPELINES+=("$PIPE_NAME")
    jq --arg p "$PIPE_NAME" '.pipelines += [{"name":$p,"action":"created"}]' "$LOG_FILE" > tmp.$$.json && mv tmp.$$.json "$LOG_FILE"
  fi
done

# === Trigger deployment ===
echo "🚀 Triggering Watcher deployment..."
DEPLOY_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST -H "Authorization: Bearer $API_TOKEN" "$CONDUCTOR_URL/pipelines/deploy")
BODY=$(echo "$DEPLOY_RESPONSE" | head -n1)
CODE=$(echo "$DEPLOY_RESPONSE" | tail -n1)

if [[ "$CODE" -ge 300 ]] || echo "$BODY" | jq -e '.error' >/dev/null 2>&1; then
  echo "❌ Deployment failed"
  rollback
  exit 1
fi

echo "✅ Deployment triggered successfully!"
echo "📝 Deployment log saved to $LOG_FILE"
