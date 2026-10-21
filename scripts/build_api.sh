#!/usr/bin/env bash
# Build the stable, agent-friendly API projection from the current raw data.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

output=data/output.json
updated=data/updated
destination=api/models.json
tmp=

cleanup() {
    [ -z "$tmp" ] || rm -f -- "$tmp"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf '%s\n' "build_api: $*" >&2
    exit 1
}

[ -f "$output" ] || fail "missing $output"
[ -f "$updated" ] || fail "missing $updated"
[ -f scripts/capabilities.jq ] || fail "missing scripts/capabilities.jq"

stamp=$(tr -d '[:space:]' < "$updated")
if ! printf '%s' "$stamp" | grep -Eq '^[0-9]{8}_[0-9]{6}$' || ! awk -v s="$stamp" 'BEGIN {
    y = substr(s,1,4)+0; m = substr(s,5,2)+0; d = substr(s,7,2)+0
    H = substr(s,10,2)+0; M = substr(s,12,2)+0; S = substr(s,14,2)+0
    split("31 28 31 30 31 30 31 31 30 31 30 31", L, " ")
    if (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) L[2] = 29
    exit !(m >= 1 && m <= 12 && d >= 1 && d <= L[m] && H < 24 && M < 60 && S < 60)
}'; then
    fail "invalid data/updated stamp"
fi
iso=${stamp:0:4}-${stamp:4:2}-${stamp:6:2}T${stamp:9:2}:${stamp:11:2}:${stamp:13:2}Z

jq -e '
  (.data | type == "array")
  and all(.data[];
    (.id | type == "string" and length > 0)
    and (.name | type == "string")
    and (.pricing | type == "object")
    and ((.supported_parameters == null) or (.supported_parameters | type == "array"))
    and ((.architecture == null) or (.architecture | type == "object"))
    and ((.created == null) or (.created | type == "number"))
    and ((.expiration_date == null) or (.expiration_date | type == "string"))
  )
' "$output" >/dev/null || fail "invalid $output"

mkdir -p api
tmp=$(mktemp "api/.models.json.XXXXXX") || fail "could not create temporary output"

jq -L scripts --arg updated "$iso" '
  include "capabilities";
  def parsed_number($value):
    [$value | select(type == "string" or type == "number") | tonumber?]
    | if length == 1 then .[0] else null end;
  def rounded_price($value):
    (((parsed_number($value) * 1000000) * 1000000 | round) / 1000000);
  def slug: gsub("[^A-Za-z0-9._/-]"; "-");
  def safe_slug:
    (length > 0)
    and (startswith("/") | not)
    and (endswith("/") | not)
    and (split("/") | all(.[]; length > 0 and . != "." and . != ".." and (startswith(".") | not)));
  def model_url($id):
    ($id | slug) as $slug
    | if ($slug | safe_slug)
      then "https://openrouterlist.jvrck.com/m/" + ($slug | split("/") | map(@uri) | join("/")) + "/"
      else null
      end;
  def projected_model:
    (parsed_number(.pricing.prompt)) as $prompt
    | (parsed_number(.pricing.completion)) as $completion
    | (if (($prompt != null and $prompt < 0) or ($completion != null and $completion < 0)) then "variable"
       elif $prompt == null or $completion == null then "unavailable"
       elif $prompt == 0 and $completion == 0 then "free"
       else "fixed"
       end) as $pricing_class
    | {
        id: .id,
        name: .name,
        url: model_url(.id),
        prompt_per_1m: (if $pricing_class == "fixed" then rounded_price(.pricing.prompt) elif $pricing_class == "free" then 0 else null end),
        completion_per_1m: (if $pricing_class == "fixed" then rounded_price(.pricing.completion) elif $pricing_class == "free" then 0 else null end),
        pricing: $pricing_class,
        context_length: ((parsed_number(.context_length)) as $context | if $context == null or $context < 0 then null else ($context | floor) end),
        capabilities: capabilities,
        input_modalities: (.architecture.input_modalities // []),
        output_modalities: (.architecture.output_modalities // []),
        created: (if .created == null then null else (.created | strftime("%Y-%m-%dT%H:%M:%SZ")) end),
        expiration_date: (.expiration_date // null)
      };
  (.data | map(projected_model) | sort_by(.id)) as $models
  | {
      schema_version: 1,
      updated: $updated,
      source: "https://openrouter.ai/api/v1/models",
      count: ($models | length),
      models: $models
    }
' "$output" > "$tmp" || fail "could not build $destination"

jq -e . "$tmp" >/dev/null || fail "generated invalid JSON"
mv "$tmp" "$destination" || fail "could not replace $destination"
tmp=
