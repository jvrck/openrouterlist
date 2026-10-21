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
  def null_or_string_array:
    (. == null) or ((type == "array") and all(.[]; type == "string"));
  (.data | type == "array")
  and all(.data[];
    (.id | type == "string" and length > 0)
    and (.name | type == "string")
    and (.pricing | type == "object")
    and ((.supported_parameters == null) or (.supported_parameters | type == "array"))
    and ((.architecture == null) or (.architecture | type == "object"))
    and (.architecture.input_modalities | null_or_string_array)
    and (.architecture.output_modalities | null_or_string_array)
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

jq -e '
  def nullable($kind): (. == null) or (type == $kind);
  def integer_nonnegative: (type == "number") and (. >= 0) and (. == floor);
  def string_array: (type == "array") and all(.[]; type == "string");
  (keys == ["count", "models", "schema_version", "source", "updated"])
  and (.schema_version == 1)
  and (.updated | type == "string")
  and (.source | type == "string")
  and (.models | type == "array")
  and (.count == (.models | length))
  and all(.models[];
    (keys == ["capabilities", "completion_per_1m", "context_length", "created", "expiration_date", "id", "input_modalities", "name", "output_modalities", "pricing", "prompt_per_1m", "url"])
    and (.id | type == "string")
    and (.name | type == "string")
    and (.url | nullable("string"))
    and (.prompt_per_1m | nullable("number"))
    and (.completion_per_1m | nullable("number"))
    and ((.pricing) as $pricing | ["fixed", "free", "variable", "unavailable"] | index($pricing) != null)
    and (.context_length | (. == null) or integer_nonnegative)
    and (.capabilities | (keys == ["reasoning", "response_format", "structured_outputs", "tool_calling", "web_search"]) and all(.[]; type == "boolean"))
    and (.input_modalities | string_array)
    and (.output_modalities | string_array)
    and (.created | nullable("string"))
    and (.expiration_date | nullable("string"))
  )
' "$tmp" >/dev/null || fail "generated output failed shape validation"
mv "$tmp" "$destination" || fail "could not replace $destination"
tmp=
