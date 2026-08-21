#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
json_file="$script_dir/council-data.json"
heads_dir="$script_dir/heads"
errors_file="$heads_dir/errors.txt"

if ! command -v jq >/dev/null 2>&1; then
	echo "Error: jq is required but not installed." >&2
	exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
	echo "Error: perl is required but not installed." >&2
	exit 1
fi

extract_head() {
	perl -0ne 'if (m{<head\b[^>]*>.*?</head>}is) { print $& }'
}

is_blocked_response() {
	local http_status="$1"
	local headers_file="$2"
	local body_file="$3"

	[[ "$http_status" == "403" ]] || return 1
	grep -qi '^cf-mitigated:\s*challenge' "$headers_file" ||
		grep -qi '^server:\s*cloudflare' "$headers_file" ||
		grep -qi '^x-azure-ref:' "$headers_file" ||
		grep -qi 'The request is blocked\.' "$body_file" ||
		grep -qi '<title>Service unavailable</title>' "$body_file"
}

slugify_name() {
	printf '%s' "$1" |
		tr '[:upper:]' '[:lower:]' |
		perl -CS -pe 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//;'
}

mkdir -p "$heads_dir"
rm -f "$heads_dir"/*.txt
: > "$errors_file"

while IFS=$'\t' read -r name homepage; do
	file_name="$(slugify_name "$name").txt"
	output_file="$heads_dir/$file_name"
	body_file="$(mktemp)"
	headers_file="$(mktemp)"
	curl_stderr_file="$(mktemp)"

	{
		printf '=== %s ===\n' "$name"
		printf 'URL: %s\n\n' "$homepage"

		if http_status="$(curl -LsS --max-time 30 -D "$headers_file" -o "$body_file" -w '%{http_code}' "$homepage" 2>"$curl_stderr_file")"; then
			html="$(<"$body_file")"
			if [[ "$http_status" =~ ^[45] ]]; then
				printf 'Failed to fetch homepage.\n'
				if is_blocked_response "$http_status" "$headers_file" "$body_file"; then
					error_message="Blocked by edge protection (HTTP $http_status)."
				else
					error_message="HTTP $http_status returned by server."
				fi
				{
					printf '=== %s ===\n' "$name"
					printf 'URL: %s\n' "$homepage"
					printf 'Error: %s\n\n' "$error_message"
				} >> "$errors_file"
			elif head_tag="$(printf '%s' "$html" | extract_head)" && [[ -n "$head_tag" ]]; then
				printf '%s\n' "$head_tag"
			else
				printf 'No <head> tag found.\n'
			fi
		else
			printf 'Failed to fetch homepage.\n'
			curl_error="$(<"$curl_stderr_file")"
			{
				printf '=== %s ===\n' "$name"
				printf 'URL: %s\n' "$homepage"
				printf 'Error: %s\n\n' "${curl_error:-Unknown curl error}"
			} >> "$errors_file"
		fi

		printf '\n\n'
	} >> "$output_file"
	rm -f "$body_file" "$headers_file"
	rm -f "$curl_stderr_file"
done < <(jq -r '.[] | [.name, .homepage] | @tsv' "$json_file")

printf 'Wrote results to %s\n' "$heads_dir"
