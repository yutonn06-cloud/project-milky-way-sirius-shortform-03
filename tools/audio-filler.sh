#!/usr/bin/env bash
# Audio filler -- generates ElevenLabs audio for Notion entries missing
# 音声URL_A, uploads each MP3 as a GitHub Release asset, and patches the
# Notion page with the public asset URL.
#
# Designed to run from a GitHub Actions workflow. Required env vars:
#   ELEVENLABS_API_KEY    sk_...
#   ELEVENLABS_VOICE_ID   ElevenLabs voice id
#   NOTION_TOKEN          Notion integration token (the same one in local .env)
#   NOTION_DATABASE_ID    32-hex database id of リライトスクリプト
#   GH_TOKEN              token with contents:write on this repo (Actions GITHUB_TOKEN works)
#   GH_REPO               owner/repo (set by Actions: $GITHUB_REPOSITORY)

set -euo pipefail

for v in ELEVENLABS_API_KEY ELEVENLABS_VOICE_ID NOTION_TOKEN NOTION_DATABASE_ID GH_TOKEN GH_REPO; do
  if [ -z "${!v:-}" ]; then
    echo "Missing env var: $v" >&2
    exit 1
  fi
done

NOTION_VERSION="2022-06-28"
RELEASE_TAG="audio-store"

notion_call() {
  local method="$1" url="$2" body="${3:-}"
  if [ -n "$body" ]; then
    printf '%s' "$body" | curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: $NOTION_VERSION" \
      -H "Content-Type: application/json" \
      --data-binary @-
  else
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: $NOTION_VERSION"
  fi
}

ensure_release() {
  if gh release view "$RELEASE_TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
    return 0
  fi
  echo "Creating rolling release '$RELEASE_TAG' on $GH_REPO ..."
  gh release create "$RELEASE_TAG" \
    --repo "$GH_REPO" \
    --title "Audio asset store" \
    --notes "Auto-managed TTS audio assets. Do not edit manually."
}

generate_and_upload() {
  # Generates one ElevenLabs clip, uploads it as a release asset, prints the
  # history-item-id (the asset filename stem) on stdout. All progress goes to
  # stderr so the caller can capture stdout cleanly.
  local text="$1" variant="$2"
  echo "    [$variant] generating audio (${#text} chars)..." >&2

  local body
  body=$(jq -nc --arg t "$text" '{text:$t,model_id:"eleven_v3"}')

  local tmp_audio tmp_headers
  tmp_audio=$(mktemp --suffix=.mp3)
  tmp_headers=$(mktemp)

  local http_code
  http_code=$(curl -sS -o "$tmp_audio" -D "$tmp_headers" -w "%{http_code}" -X POST \
    "https://api.elevenlabs.io/v1/text-to-speech/$ELEVENLABS_VOICE_ID?output_format=mp3_22050_32" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary "$body" || echo "000")

  if [ "$http_code" != "200" ]; then
    echo "      ElevenLabs HTTP $http_code: $(head -c 500 "$tmp_audio")" >&2
    rm -f "$tmp_audio" "$tmp_headers"
    return 1
  fi

  local history_id
  history_id=$(grep -i '^history-item-id:' "$tmp_headers" | tr -d '\r' | awk '{print $2}')
  if [ -z "$history_id" ]; then
    echo "      history-item-id missing from response headers" >&2
    rm -f "$tmp_audio" "$tmp_headers"
    return 1
  fi
  echo "      history-item-id=$history_id" >&2

  local asset="${history_id}.mp3"
  local asset_path="/tmp/$asset"
  mv "$tmp_audio" "$asset_path"
  rm -f "$tmp_headers"

  if ! gh release upload "$RELEASE_TAG" "$asset_path" --repo "$GH_REPO" --clobber >&2; then
    echo "      GH release upload failed" >&2
    rm -f "$asset_path"
    return 1
  fi
  rm -f "$asset_path"

  echo "$history_id"
}

ensure_release

# Build the filter via jq to keep UTF-8 of the Japanese property name clean
# regardless of the host's locale / arg-passing quirks.
audio_prop="音声URL_A"
if [ "${BACKFILL_LOCALHOST:-false}" = "true" ]; then
  echo "Mode: backfill_localhost (re-process entries whose 音声URL_A contains 'localhost:8765')"
  filter=$(jq -nc --arg p "$audio_prop" --arg v "localhost:8765" \
    '{filter:{property:$p,rich_text:{contains:$v}},page_size:50}')
else
  echo "Mode: pending (default)"
  filter=$(jq -nc --arg p "$audio_prop" \
    '{filter:{property:$p,rich_text:{is_empty:true}},page_size:50}')
fi

# Send the body via stdin to bypass any arg-encoding issues.
resp=$(printf '%s' "$filter" | curl -sS -X POST \
  "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Notion-Version: $NOTION_VERSION" \
  -H "Content-Type: application/json" \
  --data-binary @-)

# Bail loudly if Notion returned an error.
if [ "$(echo "$resp" | jq -r '.object // empty')" = "error" ]; then
  echo "Notion query failed:" >&2
  echo "$resp" | jq . >&2
  exit 1
fi

count=$(echo "$resp" | jq '.results | length')
echo "Found $count page(s) needing audio."

if [ "$count" -eq 0 ]; then
  exit 0
fi

success=0
failed=0

mapfile -t pages < <(echo "$resp" | jq -c '.results[]')

for page in "${pages[@]}"; do
  page_id=$(echo "$page" | jq -r '.id')
  title=$(echo "$page" | jq -r '.properties["タイトル"].title | map(.plain_text) | join("")')
  text_a=$(echo "$page" | jq -r '.properties["リライト本文"].rich_text | map(.plain_text) | join("")')
  text_b=$(echo "$page" | jq -r '.properties["リライト本文B"].rich_text | map(.plain_text) | join("")')

  echo "---"
  echo "Page: $title ($page_id)"

  if [ -z "$text_a" ] || [ -z "$text_b" ]; then
    echo "  skip: missing リライト本文 or リライト本文B"
    failed=$((failed+1))
    continue
  fi

  if ! id_a=$(generate_and_upload "$text_a" "A"); then
    failed=$((failed+1))
    continue
  fi
  if ! id_b=$(generate_and_upload "$text_b" "B"); then
    failed=$((failed+1))
    continue
  fi

  url_a="https://github.com/$GH_REPO/releases/download/$RELEASE_TAG/${id_a}.mp3"
  url_b="https://github.com/$GH_REPO/releases/download/$RELEASE_TAG/${id_b}.mp3"

  patch=$(jq -nc \
    --arg a "$url_a" --arg b "$url_b" \
    '{properties:{
      "音声URL_A":{rich_text:[{type:"text",text:{content:$a,link:{url:$a}}}]},
      "音声URL_B":{rich_text:[{type:"text",text:{content:$b,link:{url:$b}}}]}
    }}')

  notion_call PATCH "https://api.notion.com/v1/pages/$page_id" "$patch" >/dev/null
  echo "  OK -- Notion updated."
  success=$((success+1))
done

echo "---"
echo "Done. success=$success failed=$failed total=${#pages[@]}"
[ "$failed" -eq 0 ]
