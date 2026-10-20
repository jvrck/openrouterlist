#!/usr/bin/env bash
# Generate the static, per-model SEO pages.  This deliberately has no build
# dependencies beyond bash and jq: it also runs in the data-update workflow.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

output=data/output.json
history=data/history/prices.json
updated=data/updated
tmp=.m.tmp.$$

cleanup() {
    rm -rf -- "$tmp"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf '%s\n' "build_model_pages: $*" >&2
    exit 1
}

[ -f "$output" ] || fail "missing $output"
[ -f "$history" ] || fail "missing $history"
[ -f "$updated" ] || fail "missing $updated"

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
lastmod=${stamp%%_*}
lastmod=${lastmod:0:4}-${lastmod:4:2}-${lastmod:6:2}

# Project only fields used on pages.  In particular, benchmark data is never
# inspected or passed to the page renderer.
jq -e '
  (.data | type == "array" and length > 0)
  and all(.data[];
    (.id | type == "string" and length > 0)
    and (.name | type == "string")
    and ((.description == null) or (.description | type == "string"))
    and (.pricing | type == "object")
    and (.pricing.prompt | type == "string")
    and (.pricing.completion | type == "string")
    and ((.architecture == null) or (.architecture | type == "object"))
    and ((.expiration_date == null) or (.expiration_date | type == "string"))
    and ((.hugging_face_id == null) or (.hugging_face_id | type == "string"))
  )
' "$output" >/dev/null || fail "invalid $output"

jq -e '
  (.models | type == "object")
  and all(.models[]?;
    ((.points? // []) | type == "array")
    and all((.points? // [])[];
      (type == "array") and length == 3
      and (.[0] | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
      and ((.[1] == null) or (.[1] | type == "number"))
      and ((.[2] == null) or (.[2] | type == "number"))
    )
  )
' "$history" >/dev/null || fail "invalid $history"

slug_for() {
    printf '%s' "$1" | sed 's#[^A-Za-z0-9._/-]#-#g'
}

safe_slug() {
    local candidate segment
    candidate=$1
    case "$candidate" in
        ""|/*|*/ ) return 1 ;;
    esac
    while :; do
        segment=${candidate%%/*}
        case "$segment" in
            ""|.|..|.*) return 1 ;;
        esac
        [ "$segment" = "$candidate" ] && return 0
        candidate=${candidate#*/}
    done
}

# Case-insensitive collisions would overwrite a page on case-insensitive file
# systems.  Check before creating any replacement output.
collisions=$(jq -r '.data[].id' "$output" | while IFS= read -r id; do
    slug=$(slug_for "$id")
    if safe_slug "$slug"; then
        printf '%s\n' "$slug" | tr '[:upper:]' '[:lower:]'
    fi
done | LC_ALL=C sort | uniq -d)
[ -z "$collisions" ] || fail "case-insensitive model-page slug collision: $collisions"

mkdir "$tmp" || fail "could not create $tmp"
mkdir "$tmp/m"

jq -r '.data[].id' "$output" | while IFS= read -r id; do
    slug=$(slug_for "$id")
    if ! safe_slug "$slug"; then
        printf '%s\n' "WARN: build_model_pages: skipping unsafe id $id" >&2
        continue
    fi
    page_dir="$tmp/m/$slug"
    case "$page_dir" in
        "$tmp/m/"*) ;;
        *) fail "unsafe page path for $id" ;;
    esac
    mkdir -p "$page_dir"
    points=$(jq -c --arg id "$id" '.models[$id].points // []' "$history") || fail "could not read price points"

    jq -r --arg id "$id" --arg slug "$slug" --argjson points "$points" '
      def h: tostring | @html;
      def pathuri: split("/") | map(@uri) | join("/");
      def is_variable($v): ($v | tonumber) < 0;
      def rounded_significant($n):
        if $n == 0 then 0
        else ((($n | fabs | log) / (10 | log)) | floor) as $power
          | (pow(10; 3 - $power)) as $scale
          | (($n * $scale | round) / $scale)
        end;
      def price_per_m($n):
        if $n < 0 then "n/a (variable pricing)"
        elif ($n | fabs) < 0.000000001 then "Free"
        else "$" + (rounded_significant($n) | tostring) end;
      def price($v): ($v | tonumber * 1000000) | price_per_m(.);
      def price_row($v):
        price($v) as $text |
        if $text == "Free" or ($text | startswith("n/a")) then $text else $text + " / 1M tokens" end;
      def field($v): if $v == null or $v == "" then "—" else $v | h end;
      def group_digits:
        if length <= 3 then .
        else .[0:(length - 3)] as $head | .[(length - 3):] as $tail | ($head | group_digits) + "," + $tail
        end;
      def context_text($v): if $v == null then "—" else (($v | tostring | group_digits) + " tokens") end;
      def xpos($day; $first; $last): if $last == $first then 50 else 50 + (510 * ($day - $first) / ($last - $first)) end;
      def ypos($value; $max): 160 - (140 * $value / $max);
      def segment_paths($series; $max; $colour):
        reduce $series[] as $point ({segments: [], current: []};
          if $point.v == null then
            if (.current | length) > 0 then .segments += [.current] | .current = [] else . end
          else .current += [$point] end
        )
        | if (.current | length) > 0 then .segments += [.current] else . end
        | .segments[] as $segment
        | "<path class=\"series\" stroke=\"" + $colour + "\" d=\""
          + ($segment[0] | "M " + (.x | tostring) + " " + (ypos(.v; $max) | tostring))
          + (reduce $segment[1:][] as $next ("";
              . + " H " + ($next.x | tostring)
                + " V " + (ypos($next.v; $max) | tostring)
            ))
          + " H " + ($segment[-1].hold | tostring)
          + "\"/>";
      .data[] | select(.id == $id) |
      {
        id, name, description: (.description // ""), context_length,
        input_modalities: (.architecture.input_modalities // []),
        output_modalities: (.architecture.output_modalities // []),
        tokenizer: (.architecture.tokenizer // null),
        instruct_type: (.architecture.instruct_type // null),
        knowledge_cutoff, hugging_face_id, expiration_date,
        prompt: .pricing.prompt, completion: .pricing.completion
      } as $m |
      ($points | map({date: .[0], day: ((.[0] + "T00:00:00Z") | fromdateiso8601), prompt: (if .[1] == null or .[1] < 0 then null else .[1] end), completion: (if .[2] == null or .[2] < 0 then null else .[2] end)})) as $points |
      (($m.prompt | is_variable(.)) or ($m.completion | is_variable(.))) as $router |
      ($m.name | h) as $name |
      ($m.id | h) as $id_html |
      ($m.id | pathuri) as $id_path |
      ($slug | pathuri) as $slug_path |
      (($m.input_modalities | if type == "array" then join(", ") else tostring end) | field(.)) as $input |
      (($m.output_modalities | if type == "array" then join(", ") else tostring end) | field(.)) as $output |
      (if $router then "variable pricing" else (price($m.prompt) + " prompt, " + price($m.completion) + " completion") end) as $price_summary |
      ($m.name + " (" + $m.id + "): " + $price_summary + ", " + (($m.context_length // "—") | tostring) + " context. Live OpenRouter pricing." | h) as $description |
      (if ($points | length) >= 2 then
        ([ $points[] | (.prompt, .completion) | select(type == "number" and . >= 0) ] | max // 0) as $rawmax |
        (if $rawmax < 0.000000001 then 1 else $rawmax end) as $max |
        ($points[0].day) as $first_day |
        ($points[-1].day) as $last_day |
        ([range(0; $points|length) as $i | {i: $i, v: $points[$i].prompt, x: xpos($points[$i].day; $first_day; $last_day), hold: (if $i == ($points|length)-1 then 600 else xpos($points[$i + 1].day; $first_day; $last_day) end)}]) as $prompt_series |
        ([range(0; $points|length) as $i | {i: $i, v: $points[$i].completion, x: xpos($points[$i].day; $first_day; $last_day), hold: (if $i == ($points|length)-1 then 600 else xpos($points[$i + 1].day; $first_day; $last_day) end)}]) as $completion_series |
        "<section class=\"history\"><h2>Price history</h2><svg viewBox=\"0 0 640 200\" role=\"img\" aria-label=\"Prompt and completion price history\"><line class=\"grid\" x1=\"50\" y1=\"20\" x2=\"600\" y2=\"20\"/><line class=\"axis\" x1=\"50\" y1=\"160\" x2=\"600\" y2=\"160\"/><text x=\"44\" y=\"24\" text-anchor=\"end\">" + (price_per_m($rawmax) | h) + "</text><text x=\"44\" y=\"164\" text-anchor=\"end\">$0</text><text x=\"50\" y=\"198\">$ per 1M tokens</text><text x=\"50\" y=\"184\">" + ($points[0].date | h) + "</text><text x=\"560\" y=\"184\" text-anchor=\"end\">" + ($points[-1].date | h) + "</text><g class=\"legend\"><line class=\"prompt\" x1=\"50\" y1=\"12\" x2=\"72\" y2=\"12\"/><text x=\"78\" y=\"16\">Prompt</text><line class=\"completion\" x1=\"145\" y1=\"12\" x2=\"167\" y2=\"12\"/><text x=\"173\" y=\"16\">Completion</text></g>"
        + ([segment_paths($prompt_series; $max; "#2563eb")] | join(""))
        + ([segment_paths($completion_series; $max; "#d946ef")] | join(""))
        + "</svg></section>"
       else "<section class=\"history\"><h2>Price history</h2><p>No price changes recorded</p></section>" end | gsub("<line class=\"grid\""; "<line class=\"grid\" stroke=\"#d8dee8\"")) as $chart |
      "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>" + $name + " pricing: OpenRouterList</title>\n<meta name=\"description\" content=\"" + $description + "\">\n<link rel=\"canonical\" href=\"https://openrouterlist.jvrck.com/m/" + $slug_path + "/\">\n<meta property=\"og:title\" content=\"" + $name + " pricing: OpenRouterList\">\n<meta property=\"og:description\" content=\"" + $description + "\">\n<meta property=\"og:url\" content=\"https://openrouterlist.jvrck.com/m/" + $slug_path + "/\">\n<meta property=\"og:type\" content=\"website\">\n<meta property=\"og:image\" content=\"https://openrouterlist.jvrck.com/og-image.png\">\n<meta name=\"twitter:card\" content=\"summary_large_image\">\n<meta name=\"twitter:title\" content=\"" + $name + " pricing: OpenRouterList\">\n<meta name=\"twitter:description\" content=\"" + $description + "\">\n<meta name=\"twitter:image\" content=\"https://openrouterlist.jvrck.com/og-image.png\">\n<link rel=\"icon\" href=\"/favicon.ico\" sizes=\"any\">\n<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">\n<link rel=\"apple-touch-icon\" href=\"/apple-touch-icon.png\">\n<style>body{max-width:760px;margin:2rem auto;padding:0 1rem;font:16px/1.55 system-ui,sans-serif;color:#172033;background:#fff}a{color:#174ea6}header{border-bottom:1px solid #d8dee8;margin-bottom:1.5rem}.id{color:#52606d;overflow-wrap:anywhere}.badge{display:inline-block;padding:.15rem .5rem;border-radius:1rem;background:#fff3cd;color:#664d03;font-weight:600}dl{display:grid;grid-template-columns:max-content 1fr;gap:.45rem 1rem}dt{font-weight:600}dd{margin:0}.description{white-space:pre-wrap}.history{margin-top:2rem}svg{width:100%;height:auto;overflow:visible}.axis{stroke:#8795a8}.series,.legend line{fill:none;stroke-width:2}.prompt{stroke:#2563eb}.completion{stroke:#d946ef}svg text{font-size:12px;fill:#52606d}@media (prefers-color-scheme:dark){body{color:#e5e7eb;background:#111827}a{color:#93c5fd}header{border-color:#374151}.id,svg text{color:#aab6c8;fill:#aab6c8}.badge{background:#4b3b08;color:#fde68a}.axis{stroke:#64748b}}</style>\n</head>\n<body>\n<header><p><a href=\"/?search=" + ($m.id | @uri) + "\">← All models</a></p><h1>" + $name + "</h1><p class=\"id\">" + $id_html + "</p>"
      + (if $m.expiration_date == null or $m.expiration_date == "" then "" else "<p><span class=\"badge\">Retires on " + ($m.expiration_date | h) + "</span></p>" end)
      + "</header>\n<main><dl><dt>Prompt price</dt><dd>" + price_row($m.prompt) + "</dd><dt>Completion price</dt><dd>" + price_row($m.completion) + "</dd><dt>Context</dt><dd>" + (context_text($m.context_length) | h) + "</dd><dt>Input modalities</dt><dd>" + $input + "</dd><dt>Output modalities</dt><dd>" + $output + "</dd><dt>Tokenizer</dt><dd>" + ($m.tokenizer | field(.)) + "</dd><dt>Instruct type</dt><dd>" + ($m.instruct_type | field(.)) + "</dd><dt>Knowledge cutoff</dt><dd>" + ($m.knowledge_cutoff | field(.)) + "</dd>"
      + (if $m.hugging_face_id == null or $m.hugging_face_id == "" then "<dt>Hugging Face</dt><dd>—</dd>" else "<dt>Hugging Face</dt><dd><a href=\"https://huggingface.co/" + ($m.hugging_face_id | pathuri) + "\">" + ($m.hugging_face_id | h) + "</a></dd>" end)
      + "</dl>"
      + (if ($points | length) > 0 then "<p>Last price change: " + ($points[-1].date | h) + "</p>" else "" end)
      + "<p class=\"description\">" + ($m.description | h) + "</p>" + $chart + "<p><a href=\"https://openrouter.ai/models/" + $id_path + "\">View on OpenRouter</a></p></main>\n</body>\n</html>"
    ' "$output" > "$page_dir/index.html" || fail "could not render $id"
done

jq -r --arg date "$lastmod" '
  def slug: gsub("[^A-Za-z0-9._/-]"; "-");
  def pathuri: split("/") | map(@uri) | join("/");
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n  <url><loc>https://openrouterlist.jvrck.com/</loc><lastmod>\($date)</lastmod><changefreq>daily</changefreq><priority>1.0</priority></url>",
  (.data | map(.id | {slug: slug}) | map(select(.slug | split("/") | all(.[]; length > 0 and . != "." and . != ".." and (startswith(".") | not)))) | sort_by(.slug)[] | "  <url><loc>https://openrouterlist.jvrck.com/m/\(.slug | pathuri)/</loc><lastmod>\($date)</lastmod><changefreq>daily</changefreq><priority>0.6</priority></url>"),
  "</urlset>"
' "$output" > "$tmp/sitemap.xml" || fail "could not render sitemap"

# Both outputs now exist in the temporary tree, so failures above leave the
# currently-published pages untouched.  A generated tree intentionally has no
# index at /m/.
rm -rf -- m
mv "$tmp/m" m
mv "$tmp/sitemap.xml" sitemap.xml
