#!/usr/bin/env bash
# Generate static comparison pages for a deterministic set of current models.
#
# Selection rule:
# - Eligible models have safe /m/ slugs, current text output, non-negative
#   numeric pricing that is not entirely free, and are not routers, variants,
#   or safety classifiers (ids containing ~, :, or "guard").
# - Take the 10 providers with the most eligible models (provider-name tie
#   break), then each provider's newest three (id tie break).
# - The highest 3*prompt+completion price among each newest three is its
#   flagship. Build all 45 cross-provider flagship pairs plus every pair among
#   each provider's newest three (up to 30), ordered by model id.
#
# This deliberately has no build dependencies beyond bash and jq. Pair-slug
# collisions and unsafe pair slugs are warnings: every affected pair is
# skipped without failing the rest of the build.
set -euo pipefail

TEMPLATE_VERSION=2
if [ "${1:-}" = "--template-version" ]; then
    printf '%s\n' "$TEMPLATE_VERSION"
    exit 0
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

output=data/output.json
updated=data/updated
tmp=.compare.tmp.$$

cleanup() {
    rm -rf -- "$tmp"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf '%s\n' "build_compare_pages: $*" >&2
    exit 1
}

[ -f "$output" ] || fail "missing $output"
[ -f "$updated" ] || fail "missing $updated"
[ -f sitemap.xml ] || fail "missing sitemap.xml (run build_model_pages.sh first)"

stamp=$(tr -d '[:space:]' < "$updated")
if ! printf '%s' "$stamp" | grep -Eq '^[0-9]{8}_[0-9]{6}$'; then
    fail "invalid data/updated stamp"
fi
lastmod=${stamp%%_*}
lastmod=${lastmod:0:4}-${lastmod:4:2}-${lastmod:6:2}

mkdir "$tmp" || fail "could not create $tmp"
mkdir "$tmp/compare"

# Keep the unfiltered candidates long enough to diagnose every collision.
jq -c '
  def num: tonumber? // null;
  def model_slug: gsub("[^A-Za-z0-9._/-]"; "-");
  def safe_model_slug:
    . != "" and (startswith("/") | not) and (endswith("/") | not)
    and (split("/") | all(. != "" and . != "." and . != ".." and (startswith(".") | not)));
  def part: ascii_downcase | gsub("/"; "-") | gsub("[^a-z0-9.-]"; "-");
  [.data[]
    | (.id | model_slug) as $slug
    | select((.id | test("[~:]") | not)
      and ((.id | ascii_downcase) | test("guard") | not)
      and ((.pricing.prompt | num) != null)
      and ((.pricing.completion | num) != null)
      and ((.pricing.prompt | num) >= 0)
      and ((.pricing.completion | num) >= 0)
      and (((.pricing.prompt | num) + (.pricing.completion | num)) > 0)
      and ((.architecture.output_modalities // []) | index("text"))
      and (.expiration_date == null)
      and ($slug | safe_model_slug))
    | {id, provider: (.id | split("/")[0]), created,
       blend: (3 * (.pricing.prompt | num) + (.pricing.completion | num))}
  ] as $eligible
  | ($eligible
      | group_by(.provider)
      | map({provider: .[0].provider, count: length,
             top: (sort_by(-.created, .id) | .[0:3])})
      | sort_by(-.count, .provider)
      | .[0:10]) as $providers
  | ([$providers[] | .top | sort_by(-.blend, .id) | .[0].id]) as $flagships
  | ([range(0; $flagships | length) as $i
      | range($i + 1; $flagships | length) as $j
      | ([$flagships[$i], $flagships[$j]] | sort) as $pair
      | {a: $pair[0], b: $pair[1], kind: "cross"}]
     + [$providers[]
        | (.top | map(.id)) as $top
        | range(0; $top | length) as $i
        | range($i + 1; $top | length) as $j
        | ([$top[$i], $top[$j]] | sort) as $pair
        | {a: $pair[0], b: $pair[1], kind: "same"}])
  | unique_by(.a, .b)
  | map((.a | part) as $apart | (.b | part) as $bpart
        | . + {slug: ($apart + "-vs-" + $bpart),
               collision_key: ([$apart, $bpart] | sort | join("-vs-"))})
  | sort_by(.slug, .a, .b)
' "$output" > "$tmp/candidates.json" || fail "could not select pairs"

jq -r '
  group_by(.collision_key)[]
  | select(length > 1)
  | "WARN: build_compare_pages: skipping colliding pairs "
    + (map(.a + "|" + .b) | join(", ")) + " (slug " + .[0].collision_key + ")"
' "$tmp/candidates.json" >&2

jq -r '.[] | select(.slug == "" or (.slug | test("^[.-]")))
  | "WARN: build_compare_pages: skipping unsafe pair " + .a + "|" + .b + " (slug " + .slug + ")"' \
  "$tmp/candidates.json" >&2

jq '
  (group_by(.collision_key) | map(select(length == 1)) | add // [])
  | map(select(.slug != "" and (.slug | test("^[.-]") | not)))
  | map({slug, a, b, kind})
  | sort_by(.slug)
' "$tmp/candidates.json" > "$tmp/compare/pairs.json" || fail "could not write pair manifest"

# Render one page at a time to keep memory use predictable under jq 1.6.
jq -r '.[] | [.slug, .a, .b] | @tsv' "$tmp/compare/pairs.json" |
while IFS="$(printf '\t')" read -r slug aid bid; do
    page_dir="$tmp/compare/$slug"
    case "$page_dir" in
        "$tmp/compare/"*) ;;
        *) fail "unsafe page path for $aid and $bid" ;;
    esac
    mkdir -p "$page_dir"

    prices=$(jq -r --arg a "$aid" --arg b "$bid" '
      [.data[] | select(.id == $a or .id == $b)]
      | sort_by(.id)
      | [.[0].pricing.prompt, .[0].pricing.completion,
         .[1].pricing.prompt, .[1].pricing.completion] | @tsv
    ' "$output") || fail "could not read prices for $slug"
    IFS="$(printf '\t')" read -r ap ac bp bc <<EOF
$prices
EOF

    costs=$(awk -v ap="$ap" -v ac="$ac" -v bp="$bp" -v bc="$bc" '
      function fmt(v) { return v < 0.01 ? sprintf("%.4f", v) : sprintf("%.2f", v) }
      function fmt_diff(v, digits) { return digits == 4 ? sprintf("%.4f", v) : sprintf("%.2f", v) }
      BEGIN {
        ad = (1000 * ap + 500 * ac) * 100
        bd = (1000 * bp + 500 * bc) * 100
        diff = ad > bd ? ad - bd : bd - ad
        if (diff == 0) {
          day_diff = "none"
          month_diff = "none"
        } else {
          digits = diff < 0.01 ? 4 : 2
          day_diff = fmt_diff(diff, digits)
          month_diff = fmt_diff(diff * 30, digits)
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", fmt(ad), fmt(ad * 30), fmt(bd), fmt(bd * 30), day_diff, month_diff
      }
    ') || fail "could not calculate workload for $slug"
    IFS="$(printf '\t')" read -r aday amonth bday bmonth ddiff mdiff <<EOF
$costs
EOF

    jq -L scripts -r \
      --arg aid "$aid" --arg bid "$bid" --arg slug "$slug" --arg date "$lastmod" \
      --arg aday "$aday" --arg amonth "$amonth" --arg bday "$bday" --arg bmonth "$bmonth" \
      --arg ddiff "$ddiff" --arg mdiff "$mdiff" '
      include "capabilities";
      def h: tostring | @html;
      def model_slug: gsub("[^A-Za-z0-9._/-]"; "-");
      def pathuri: split("/") | map(@uri) | join("/");
      def group_digits:
        tostring
        | if length <= 3 then .
          else .[0:(length - 3)] as $head | .[(length - 3):] as $tail
            | ($head | group_digits) + "," + $tail
          end;
      def fixed($n; $digits):
        (pow(10; $digits)) as $scale
        | (($n * $scale) | round) as $whole
        | ($whole / $scale | tostring) as $base
        | if $digits == 0 then $base
          else ($base | split(".")) as $parts
          | ($parts[0] + "." + (($parts[1] // "") + ("000000"))[0:$digits])
          end;
      def money_m($raw):
        (($raw | tonumber) * 1000000) as $v
        | "$" + (if $v < 0.01 then fixed($v; 4) else fixed($v; 2) end);
      def context($v): if $v == null then "—" else (($v | group_digits) + " tokens") end;
      def modalities($v): if ($v // [] | length) == 0 then "—" else ($v | join(", ")) end;
      def mark($v): if $v then "✓" else "–" end;
      def added($v): ($v | strftime("%Y-%m-%d"));
      def ratio($high; $low):
        if $low == 0 then null else (($high / $low * 10 | round) / 10) end;
      (.data[] | select(.id == $aid)
        | . + {caps: capabilities, model_slug: (.id | model_slug)}) as $a
      | (.data[] | select(.id == $bid)
        | . + {caps: capabilities, model_slug: (.id | model_slug)}) as $b
      | ($a.pricing.prompt | tonumber) as $ap
      | ($a.pricing.completion | tonumber) as $ac
      | ($b.pricing.prompt | tonumber) as $bp
      | ($b.pricing.completion | tonumber) as $bc
      | ($a.name | h) as $an | ($b.name | h) as $bn
      | (($a.name + " vs " + $b.name + ": " + money_m($ap) + " vs " + money_m($bp)
          + " per 1M prompt tokens, " + money_m($ac) + " vs " + money_m($bc)
          + " per 1M completion, " + context($a.context_length) + " vs "
          + context($b.context_length) + " context. Live OpenRouter prices, updated twice daily.") | h) as $description
      | (if $ac == $bc then "Both models have the same completion-token price"
         elif $ac == 0 then $a.name + " has free completion tokens"
         elif $bc == 0 then $b.name + " has free completion tokens"
         elif $ac < $bc then
           if ratio($bc; $ac) == 1 then $a.name + " is " + (fixed((($bc - $ac) / $bc * 100); 1)) + "% cheaper per 1M completion tokens"
           else $a.name + " is " + (ratio($bc; $ac) | tostring) + "× cheaper per 1M completion tokens" end
         else
           if ratio($ac; $bc) == 1 then $b.name + " is " + (fixed((($ac - $bc) / $ac * 100); 1)) + "% cheaper per 1M completion tokens"
           else $b.name + " is " + (ratio($ac; $bc) | tostring) + "× cheaper per 1M completion tokens" end
         end
         + (if $a.context_length == $b.context_length then "; both have the same context window."
            elif ($a.context_length // 0) > ($b.context_length // 0) then "; " + $a.name + " has the larger context window."
            else "; " + $b.name + " has the larger context window." end)) as $verdict
      | ($aid | @uri) as $a_uri | ($bid | @uri) as $b_uri
      | "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        + "<title>" + $an + " vs " + $bn + " pricing: OpenRouterList</title>\n"
        + "<meta name=\"description\" content=\"" + $description + "\">\n"
        + "<link rel=\"canonical\" href=\"https://openrouterlist.jvrck.com/compare/" + ($slug | @uri) + "/\">\n"
        + "<meta property=\"og:title\" content=\"" + $an + " vs " + $bn + " pricing: OpenRouterList\">\n"
        + "<meta property=\"og:description\" content=\"" + $description + "\">\n"
        + "<meta property=\"og:url\" content=\"https://openrouterlist.jvrck.com/compare/" + ($slug | @uri) + "/\">\n"
        + "<meta property=\"og:type\" content=\"website\">\n<meta property=\"og:image\" content=\"https://openrouterlist.jvrck.com/og-image.png\">\n"
        + "<meta name=\"twitter:card\" content=\"summary_large_image\">\n<meta name=\"twitter:title\" content=\"" + $an + " vs " + $bn + " pricing: OpenRouterList\">\n"
        + "<meta name=\"twitter:description\" content=\"" + $description + "\">\n<meta name=\"twitter:image\" content=\"https://openrouterlist.jvrck.com/og-image.png\">\n"
        + "<link rel=\"icon\" href=\"/favicon.ico\" sizes=\"any\">\n<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">\n<link rel=\"apple-touch-icon\" href=\"/apple-touch-icon.png\">\n"
        + "<style>body{max-width:920px;margin:2rem auto;padding:0 1rem;font:16px/1.55 system-ui,sans-serif;color:#172033;background:#fff}a{color:#174ea6}header{border-bottom:1px solid #d8dee8;margin-bottom:1.5rem}h1{line-height:1.2}.verdict{font-size:1.1rem}table{width:100%;border-collapse:collapse;margin:1.5rem 0}th,td{padding:.65rem;text-align:left;border:1px solid #d8dee8;vertical-align:top}th{background:#f4f6f8}.links{display:flex;flex-wrap:wrap;gap:.6rem 1.2rem}.updated{color:#52606d}@media(max-width:600px){body{margin:1rem auto;font-size:15px}th,td{padding:.45rem}.model-id{display:none}}@media(prefers-color-scheme:dark){body{color:#e5e7eb;background:#111827}a{color:#93c5fd}header,th,td{border-color:#374151}th{background:#1f2937}.updated{color:#aab6c8}}</style>\n</head>\n<body>\n"
        + "<header><p><a href=\"/compare/\">← All model comparisons</a></p><h1>" + $an + " vs " + $bn + "</h1><p class=\"verdict\">" + ($verdict | h) + "</p></header>\n<main>\n"
        + "<table><thead><tr><th>Metric</th><th>" + $an + "</th><th>" + $bn + "</th></tr></thead><tbody>"
        + "<tr class=\"model-id\"><th>Model ID</th><td>" + ($a.id | h) + "</td><td>" + ($b.id | h) + "</td></tr>"
        + "<tr><th>Prompt price</th><td>" + money_m($ap) + " / 1M tokens</td><td>" + money_m($bp) + " / 1M tokens</td></tr>"
        + "<tr><th>Completion price</th><td>" + money_m($ac) + " / 1M tokens</td><td>" + money_m($bc) + " / 1M tokens</td></tr>"
        + "<tr><th>Context</th><td>" + (context($a.context_length) | h) + "</td><td>" + (context($b.context_length) | h) + "</td></tr>"
        + "<tr><th>Tool calling</th><td>" + mark($a.caps.tool_calling) + "</td><td>" + mark($b.caps.tool_calling) + "</td></tr>"
        + "<tr><th>Structured outputs</th><td>" + mark($a.caps.structured_outputs) + "</td><td>" + mark($b.caps.structured_outputs) + "</td></tr>"
        + "<tr><th>Reasoning</th><td>" + mark($a.caps.reasoning) + "</td><td>" + mark($b.caps.reasoning) + "</td></tr>"
        + "<tr><th>Response format</th><td>" + mark($a.caps.response_format) + "</td><td>" + mark($b.caps.response_format) + "</td></tr>"
        + "<tr><th>Web search</th><td>" + mark($a.caps.web_search) + "</td><td>" + mark($b.caps.web_search) + "</td></tr>"
        + "<tr><th>Input modalities</th><td>" + (modalities($a.architecture.input_modalities) | h) + "</td><td>" + (modalities($b.architecture.input_modalities) | h) + "</td></tr>"
        + "<tr><th>Output modalities</th><td>" + (modalities($a.architecture.output_modalities) | h) + "</td><td>" + (modalities($b.architecture.output_modalities) | h) + "</td></tr>"
        + "<tr><th>Added</th><td>" + added($a.created) + "</td><td>" + added($b.created) + "</td></tr>"
        + "</tbody></table>\n<section><h2>Sample workload</h2><p>Chat app: 1,000 prompt + 500 completion tokens × 100 requests per day.</p>"
        + "<table><thead><tr><th>Cost</th><th>" + $an + "</th><th>" + $bn + "</th></tr></thead><tbody>"
        + "<tr><th>Per day</th><td>$" + $aday + "</td><td>$" + $bday + "</td></tr><tr><th>Per 30 days</th><td>$" + $amonth + "</td><td>$" + $bmonth + "</td></tr>"
        + "</tbody></table>" + (if $ddiff == "none" then "<p>No difference.</p>" else "<p>Difference: $" + $ddiff + " per day and $" + $mdiff + " per 30 days.</p>" end) + "</section>\n"
        + "<p class=\"links\"><a href=\"/m/" + ($a.model_slug | pathuri) + "/\">" + $an + " details</a><a href=\"/m/" + ($b.model_slug | pathuri) + "/\">" + $bn + " details</a><a href=\"/?cmp=" + $a_uri + "," + $b_uri + "\">Open in the live compare view</a><a href=\"/?calc=1&amp;cm=" + $a_uri + "," + $b_uri + "&amp;cp=1000&amp;cc=500&amp;cr=100\">Try your own workload</a></p>\n"
        + "<p class=\"updated\">Data updated " + ($date | h) + "</p></main>\n</body>\n</html>"
    ' "$output" > "$page_dir/index.html" || fail "could not render $slug"
done

# The index repeats the selection rule so the list is transparent to readers.
jq -L scripts -r --arg date "$lastmod" --slurpfile pairs "$tmp/compare/pairs.json" '
  def h: tostring | @html;
  def links($models; $kind):
    [ $pairs[0][] | select(.kind == $kind) as $p
      | ($models[] | select(.id == $p.a) | .name) as $an
      | ($models[] | select(.id == $p.b) | .name) as $bn
      | "<li><a href=\"/compare/" + ($p.slug | @uri) + "/\">" + ($an | h) + " vs " + ($bn | h) + "</a></li>" ]
    | join("\n");
  .data as $models
  | "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>Model price comparisons: OpenRouterList</title>\n<meta name=\"description\" content=\"Side-by-side OpenRouter model pricing, capabilities, context windows and sample workload costs for popular model pairs.\">\n<link rel=\"canonical\" href=\"https://openrouterlist.jvrck.com/compare/\">\n<meta property=\"og:title\" content=\"Model price comparisons: OpenRouterList\">\n<meta property=\"og:description\" content=\"Side-by-side OpenRouter model prices and workload costs.\">\n<meta property=\"og:url\" content=\"https://openrouterlist.jvrck.com/compare/\">\n<meta property=\"og:type\" content=\"website\">\n<meta property=\"og:image\" content=\"https://openrouterlist.jvrck.com/og-image.png\">\n<meta name=\"twitter:card\" content=\"summary_large_image\">\n<meta name=\"twitter:title\" content=\"Model price comparisons: OpenRouterList\">\n<meta name=\"twitter:description\" content=\"Side-by-side OpenRouter model prices and workload costs.\">\n<meta name=\"twitter:image\" content=\"https://openrouterlist.jvrck.com/og-image.png\">\n<link rel=\"icon\" href=\"/favicon.ico\" sizes=\"any\">\n<link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">\n<link rel=\"apple-touch-icon\" href=\"/apple-touch-icon.png\">\n<style>body{max-width:860px;margin:2rem auto;padding:0 1rem;font:16px/1.55 system-ui,sans-serif;color:#172033;background:#fff}a{color:#174ea6}header{border-bottom:1px solid #d8dee8;margin-bottom:1.5rem}.rule{padding:1rem;background:#f4f6f8;border-radius:.5rem}li{margin:.35rem 0}.updated{color:#52606d}@media(prefers-color-scheme:dark){body{color:#e5e7eb;background:#111827}a{color:#93c5fd}header{border-color:#374151}.rule{background:#1f2937}.updated{color:#aab6c8}}</style>\n</head>\n<body>\n<header><p><a href=\"/\">← Model comparison table</a></p><h1>Model price comparisons</h1><p>Static, side-by-side pricing pages for model A vs model B searches.</p></header>\n<main><section class=\"rule\"><h2>How these pairs are chosen</h2><p>From current, paid text-output models with safe IDs and numeric prices, we select the 10 providers with the most eligible models, take each provider’s newest three, and choose the highest 3:1 blended-price model as its flagship. The list contains every cross-provider flagship pair and every pair within each provider’s newest three.</p></section>\n<section><h2>Cross-provider flagships</h2><ul>\n" + links($models; "cross") + "\n</ul></section>\n<section><h2>Same-provider comparisons</h2><ul>\n" + links($models; "same") + "\n</ul></section>\n<p class=\"updated\">Data updated " + ($date | h) + "</p></main>\n</body>\n</html>"
' "$output" > "$tmp/compare/index.html" || fail "could not render comparison index"

printf '%s\n' "$TEMPLATE_VERSION" > "$tmp/compare/.template-version"

# Remove only comparison entries, then insert the freshly built set before
# </urlset>. The one-URL-per-line sitemap format comes from model-page builds.
grep -v '<loc>https://openrouterlist.jvrck.com/compare/' sitemap.xml > "$tmp/sitemap.base.xml" || fail "could not read sitemap"
jq -r '.[].slug' "$tmp/compare/pairs.json" > "$tmp/slugs.txt"
awk -v date="$lastmod" '
  /<\/urlset>/ {
    print "  <url><loc>https://openrouterlist.jvrck.com/compare/</loc><lastmod>" date "</lastmod><changefreq>daily</changefreq><priority>0.7</priority></url>"
    while ((getline line < pairs) > 0) {
      print "  <url><loc>https://openrouterlist.jvrck.com/compare/" line "/</loc><lastmod>" date "</lastmod><changefreq>daily</changefreq><priority>0.6</priority></url>"
    }
    close(pairs)
  }
  { print }
' pairs="$tmp/slugs.txt" "$tmp/sitemap.base.xml" > "$tmp/sitemap.xml" || fail "could not update sitemap"

# All outputs are complete before either published path is replaced.
rm -rf -- compare
mv "$tmp/compare" compare
mv "$tmp/sitemap.xml" sitemap.xml
