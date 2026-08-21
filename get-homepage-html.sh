#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
json_file="$script_dir/council-data.json"
homepages_dir="$script_dir/homepages"
errors_file="$homepages_dir/errors.txt"

if ! command -v jq >/dev/null 2>&1; then
	echo "Error: jq is required but not installed." >&2
	exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
	echo "Error: perl is required but not installed." >&2
	exit 1
fi

slugify_name() {
	printf '%s' "$1" |
		tr '[:upper:]' '[:lower:]' |
		perl -CS -pe 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//;'
}

mkdir -p "$homepages_dir"
rm -f "$homepages_dir"/*.html
: > "$errors_file"

while IFS=$'\t' read -r name homepage; do
	[[ -n "$name" && -n "$homepage" ]] || continue

	output_file="$homepages_dir/$(slugify_name "$name").html"
	body_file="$(mktemp)"
	curl_stderr_file="$(mktemp)"

	if http_status="$(curl -LsS --max-time 30 -o "$body_file" -w '%{http_code}' "$homepage" 2>"$curl_stderr_file")"; then
		if [[ "$http_status" =~ ^[45] ]]; then
			curl_error="$(<"$curl_stderr_file")"
			{
				printf '=== %s ===\n' "$name"
				printf 'URL: %s\n' "$homepage"
				printf 'Error: HTTP %s returned by server.\n' "$http_status"
				[[ -n "$curl_error" ]] && printf 'Details: %s\n' "$curl_error"
				printf '\n'
			} >> "$errors_file"
		else
			cp "$body_file" "$output_file"
		fi
	else
		curl_error="$(<"$curl_stderr_file")"
		{
			printf '=== %s ===\n' "$name"
			printf 'URL: %s\n' "$homepage"
			printf 'Error: %s\n\n' "${curl_error:-Unknown curl error}"
		} >> "$errors_file"
	fi

	rm -f "$body_file" "$curl_stderr_file"
done < <(jq -r '.[] | [.name, .homepage] | @tsv' "$json_file")

printf 'Wrote results to %s\n' "$homepages_dir"
