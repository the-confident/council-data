#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
json_file="$script_dir/council-data.json"
tmp_result="$(mktemp)"
tmp_json="$(mktemp)"
tmp_unmatched="$(mktemp)"
trap 'rm -f "$tmp_result" "$tmp_json" "$tmp_unmatched"' EXIT

if ! command -v jq >/dev/null 2>&1; then
	echo "Error: jq is required but not installed." >&2
	exit 1
fi

if [[ ! -f "$json_file" ]]; then
	echo "Error: JSON file not found at $json_file" >&2
	exit 1
fi

# Only fills in .generator when it is currently entirely blank, so previously
# curated values (including ones inferred from evidence other than
# generator_raw_value) are never overwritten. Patterns are derived from the
# generator_raw_value / generator combinations already present in the file.
jq '
	def detect_cms($raw):
		if ($raw | test("^Drupal\\s+(\\d+)"; "i")) then
			($raw | capture("^Drupal\\s+(?<ver>\\d+)"; "i")) as $m
			| {
				cms: "Drupal",
				cms_variant: (if ($raw | test("LocalGov Drupal"; "i")) then "LocalGov Drupal" else "" end),
				cms_version: $m.ver
			}
		elif ($raw | test("^Contensis"; "i")) then
			{
				cms: "Contensis",
				cms_variant: "",
				cms_version: (
					if ($raw | test("Version\\s+[\\d.]+"; "i"))
					then ($raw | capture("Version\\s+(?<ver>[\\d.]+)"; "i").ver)
					else ""
					end
				)
			}
		elif ($raw | test("Cuttlefish CMS"; "i")) then
			{
				cms: "Cuttlefish CMS",
				cms_variant: "ccms",
				cms_version: (
					if ($raw | test("^ccms/[\\d.]+"; "i"))
					then ($raw | capture("^ccms/(?<ver>[\\d.]+)"; "i").ver)
					else ""
					end
				)
			}
		elif ($raw | test("^pTools Software$"; "i")) then
			{cms: "pTools Software", cms_variant: "", cms_version: ""}
		elif ($raw | test("jadu\\.net"; "i")) then
			{cms: "Jadu", cms_variant: "", cms_version: ""}
		elif ($raw | test("^Council Platform\\s+[\\d.]+"; "i")) then
			{cms: "Council Platform", cms_variant: "", cms_version: ($raw | capture("^Council Platform\\s+(?<ver>[\\d.]+)"; "i").ver)}
		elif ($raw | test("^VerseOne CMS"; "i")) then
			{
				cms: "VerseOne CMS",
				cms_variant: "",
				cms_version: (
					if ($raw | test("v\\d[\\d.]*"; "i"))
					then ($raw | capture("v(?<ver>\\d[\\d.]*)"; "i").ver)
					else ""
					end
				)
			}
		elif ($raw | test("^Sitefinity\\s+[\\d.]+"; "i")) then
			{cms: "Sitefinity", cms_variant: "", cms_version: ($raw | capture("^Sitefinity\\s+(?<ver>[\\d.]+)"; "i").ver)}
		elif ($raw | test("^CommonSpot Build\\s+[\\d.]+"; "i")) then
			{cms: "CommonSpot", cms_variant: "", cms_version: ($raw | capture("^CommonSpot Build\\s+(?<ver>[\\d.]+)"; "i").ver)}
		elif ($raw | test("Smart Media Intelligent WebCentre"; "i")) then
			{cms: "Smart Media Intelligent WebCentre", cms_variant: "", cms_version: ""}
		elif ($raw | test("GOSS iCM"; "i")) then
			{cms: "GOSS iCM", cms_variant: "", cms_version: ""}
		elif ($raw | test("SharePoint"; "i")) then
			{cms: "SharePoint", cms_variant: "", cms_version: ""}
		elif ($raw | test("Web Labs Bridge"; "i")) then
			{cms: "Web-labs", cms_variant: "Bridge", cms_version: ""}
		elif ($raw | test("Joomla"; "i")) then
			{cms: "Joomla", cms_variant: "", cms_version: ""}
		elif ($raw | test("^Orchard$"; "i")) then
			{cms: "Orchard CMS", cms_variant: "", cms_version: ""}
		elif ($raw | test("WordPress|WPBakery|\\bDivi\\b|WPML|Site Kit by Google|WP Rocket|\\bRedux\\b"; "i")) then
			{
				cms: "WordPress",
				cms_variant: "",
				cms_version: (
					if ($raw | test("^WordPress\\s+[\\d.]+$"; "i"))
					then ($raw | capture("^WordPress\\s+(?<ver>[\\d.]+)$"; "i").ver)
					else ""
					end
				)
			}
		else
			null
		end;

	map(
		if (.generator_raw_value != "" and (.generator.cms // "") == "")
		then . + {_cms_detected: (detect_cms(.generator_raw_value))}
		else . + {_cms_detected: null}
		end
	) as $rows
	| {
		council_data: ($rows | map(
			if .["_cms_detected"] != null then .generator = .["_cms_detected"] else . end
			| del(.["_cms_detected"])
		)),
		updated: ($rows | map(select(.["_cms_detected"] != null)) | length),
		unmatched: (
			$rows
			| map(select(.["_cms_detected"] == null and .generator_raw_value != "" and (.generator.cms // "") == ""))
			| map(.generator_raw_value)
			| unique
		)
	}
' "$json_file" > "$tmp_result"

jq '.council_data' "$tmp_result" > "$tmp_json"
jq empty "$tmp_json"

updated=$(jq '.updated' "$tmp_result")
jq -r '.unmatched[]' "$tmp_result" > "$tmp_unmatched"
unmatched=$(wc -l < "$tmp_unmatched" | tr -d ' ')

mv "$tmp_json" "$json_file"

echo "Detected CMS for $updated councils in $json_file"
if [[ "$unmatched" -gt 0 ]]; then
	echo "Left $unmatched distinct generator_raw_value pattern(s) unmatched:" >&2
	sed 's/^/  - /' "$tmp_unmatched" >&2
fi
