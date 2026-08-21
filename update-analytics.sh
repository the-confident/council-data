#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
json_file="$script_dir/council-data.json"
homepages_dir="$script_dir/homepages"
heads_dir="$script_dir/heads"
tmp_updates="$(mktemp)"
tmp_json="$(mktemp)"

cleanup() {
	rm -f "$tmp_updates" "$tmp_json"
}
trap cleanup EXIT

if ! command -v jq >/dev/null 2>&1; then
	echo "Error: jq is required but not installed." >&2
	exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
	echo "Error: perl is required but not installed." >&2
	exit 1
fi

if [[ ! -f "$json_file" ]]; then
	echo "Error: JSON file not found at $json_file" >&2
	exit 1
fi

slugify_name() {
	printf '%s' "$1" |
		tr '[:upper:]' '[:lower:]' |
		perl -CS -pe 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//;'
}

has_match() {
	local file="$1"
	local pattern="$2"
	grep -Eiq "$pattern" "$file"
}

extract_hotjar_version() {
	local file="$1"
	local version

	version="$(grep -Eio 'hjsv[[:space:]]*:[[:space:]]*[0-9]+' "$file" | head -n 1 | grep -Eo '[0-9]+' || true)"
	if [[ -n "$version" ]]; then
		echo "$version"
		return
	fi

	version="$(grep -Eio 'hotjar[^"'"'"'[:space:]]*sv=([0-9]+)' "$file" | head -n 1 | grep -Eo 'sv=([0-9]+)' | grep -Eo '[0-9]+' || true)"
	echo "$version"
}

detect_analytics() {
	local file="$1"
	local provider=""
	local variant=""
	local version=""
	local has_gtm="false"

	if has_match "$file" 'googletagmanager\.com/gtm\.js|GTM-[A-Z0-9]{4,}'; then
		has_gtm="true"
	fi

	# Prefer explicit analytics systems before tag-manager-only matches.
	if has_match "$file" 'googletagmanager\.com/gtag/js|google-analytics\.com/g/collect|\bgtag\('; then
		if grep -Eq 'G-[A-Z0-9]{6,}' "$file"; then
			provider="Google Analytics"
			variant="GA4"
		elif grep -Eq 'UA-[0-9]+-[0-9]+' "$file"; then
			provider="Google Analytics"
			variant="Universal Analytics"
		fi
	elif has_match "$file" 'UA-[0-9]+-[0-9]+|google-analytics\.com/analytics\.js|ga\(' ; then
		provider="Google Analytics"
		variant="Universal Analytics"
	elif has_match "$file" '\bmatomo\b|\bpiwik\b|_paq'; then
		provider="Matomo"
		variant="Piwik / Matomo"
	elif has_match "$file" 'clarity\.ms|\bclarity\('; then
		provider="Microsoft Clarity"
	elif has_match "$file" '\bhotjar\b|static\.hotjar\.com/c/hotjar-'; then
		provider="Hotjar"
		version="$(extract_hotjar_version "$file")"
	elif has_match "$file" 'adobedtm\.com|omtrdc\.net|demdex\.net|analytics\.adobe\.com'; then
		provider="Adobe Analytics"
	elif [[ "$has_gtm" == "true" ]]; then
		# More aggressive GTM downstream inference using additional in-page signals.
		if has_match "$file" 'google_tag_data|measurementId["'"'"':[:space:]]+G-[A-Z0-9]{6,}|G-[A-Z0-9]{6,}'; then
			provider="Google Analytics"
			variant="GA4"
		elif has_match "$file" 'UA-[0-9]+-[0-9]+|analytics\.js|/collect\?|ga\(\s*['"'"'create['"'"']'; then
			provider="Google Analytics"
			variant="Universal Analytics"
		elif has_match "$file" '_paq|matomo\.js|piwik\.js|matomo\.php'; then
			provider="Matomo"
			variant="Piwik / Matomo"
		elif has_match "$file" 'adobedtm\.com|omtrdc\.net|demdex\.net|analytics\.adobe\.com'; then
			provider="Adobe Analytics"
		elif has_match "$file" 'clarity\.ms|\bclarity\('; then
			provider="Microsoft Clarity"
		elif has_match "$file" '\bhotjar\b|static\.hotjar\.com/c/hotjar-'; then
			provider="Hotjar"
			version="$(extract_hotjar_version "$file")"
		else
			provider="Google"
			variant="GTM"
		fi
	fi

	printf '%s\t%s\t%s\n' "$provider" "$variant" "$version"
}

processed=0
detected=0

while IFS= read -r name; do
	[[ -n "$name" ]] || continue

	slug="$(slugify_name "$name")"
	homepage_file="$homepages_dir/$slug.html"
	head_file="$heads_dir/$slug.txt"
	input_file=""

	if [[ -f "$homepage_file" ]]; then
		input_file="$homepage_file"
	elif [[ -f "$head_file" ]]; then
		input_file="$head_file"
	fi

	provider=""
	variant=""
	version=""

	if [[ -n "$input_file" ]]; then
		IFS=$'\t' read -r provider variant version < <(detect_analytics "$input_file")
	fi

	if [[ -n "$provider" ]]; then
		((detected += 1))
	fi
	printf '%s\t%s\t%s\t%s\n' "$name" "$provider" "$variant" "$version" >> "$tmp_updates"
	((processed += 1))
done < <(jq -r '.[].name' "$json_file")

if [[ "$processed" -eq 0 ]]; then
	echo "Error: no councils found in $json_file" >&2
	exit 1
fi

jq --rawfile updates "$tmp_updates" '
	def to_map($raw):
		($raw
		 | split("\n")
		 | map(select(length > 0))
		 | map(split("\t"))
		 | map(select(length >= 4)
			 | {
				(.[0]): {
					provider: .[1],
					provider_variant: .[2],
					provider_version: .[3]
				}
			 }
		 )
		 | add // {});

	(to_map($updates)) as $analytics_map
	| map(
		if ($analytics_map[.name] // null) != null
		then .analytics = $analytics_map[.name]
		else .
		end
	)
' "$json_file" > "$tmp_json"

jq empty "$tmp_json"
mv "$tmp_json" "$json_file"

echo "Processed $processed councils"
echo "Detected analytics provider for $detected councils"
echo "Updated analytics in $json_file"