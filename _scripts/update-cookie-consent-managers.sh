#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
json_file="$script_dir/council-data.json"
homepages_dir="$script_dir/homepages"
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

detect_cookie_manager() {
	local file="$1"

	# Ordered by specificity so we prefer explicit vendor signatures.
	if has_match "$file" 'cdn\.cookielaw\.org|cookiepro\.com|\bOptanon\b|\bOneTrust\b'; then
		echo "OneTrust / CookiePro"
		return
	fi
	if has_match "$file" 'consent\.cookiebot\.com|consentcdn\.cookiebot\.com|\bCookiebot\b'; then
		echo "Cookiebot"
		return
	fi
	if has_match "$file" 'civiccomputing\.com|CookieControl\.load|cookieControl-[0-9]'; then
		echo "Civic Cookie Control"
		return
	fi
	if has_match "$file" 'cdn-cookieyes\.com|id="cookieyes"|\bcookieyes\b'; then
		echo "CookieYes"
		return
	fi
	if has_match "$file" 'cdn\.cookie-script\.com|cookie-script\.com'; then
		echo "CookieScript"
		return
	fi
	if has_match "$file" 'policy\.app\.cookieinformation\.com'; then
		echo "Cookie Information"
		return
	fi
	if has_match "$file" 'silktideConsentManager|silktideCookieBannerManager|silktide\.com/cookie'; then
		echo "Silktide Consent Manager"
		return
	fi
	if has_match "$file" 'com\.placecube\.cookieconsent\.web'; then
		echo "Placecube CookieConsent"
		return
	fi
	if has_match "$file" 'NADevGDPRCookieConsent'; then
		echo "NADev GDPR Cookie Consent"
		return
	fi
	if has_match "$file" 'eu-cookie-compliance'; then
		echo "Drupal EU Cookie Compliance"
		return
	fi
	if has_match "$file" 'jquery-eu-cookie-law-popup'; then
		echo "jQuery EU Cookie Law Popup"
		return
	fi
	if has_match "$file" 'cookieconsent@3|window\.cookieconsent\.initialise|cookieconsent\.min\.js'; then
		echo "Insites Cookie Consent"
		return
	fi

	echo ""
}

processed=0
matched=0
skipped=0

while IFS= read -r name; do
	[[ -n "$name" ]] || continue

	slug="$(slugify_name "$name")"
	homepage_file="$homepages_dir/$slug.html"

	if [[ ! -f "$homepage_file" ]]; then
		((skipped += 1))
		continue
	fi

	manager="$(detect_cookie_manager "$homepage_file")"
	printf '%s\t%s\n' "$name" "$manager" >> "$tmp_updates"
	((processed += 1))
	if [[ -n "$manager" ]]; then
		((matched += 1))
	fi
done < <(jq -r '.[].name' "$json_file")

if [[ "$processed" -eq 0 ]]; then
	echo "Error: no homepage files processed from $homepages_dir" >&2
	exit 1
fi

jq --rawfile updates "$tmp_updates" '
	def to_map($raw):
		($raw
		 | split("\n")
		 | map(select(length > 0))
		 | map(
			. as $line
			| ($line | index("\t")) as $tab_index
			| select($tab_index != null)
			| {($line[0:$tab_index]): $line[$tab_index + 1:]}
		 )
		 | add // {});

	(to_map($updates)) as $manager_map
	| map(
		if ($manager_map[.name] // null) != null
		then .cookie_consent_manager = $manager_map[.name]
		else .
		end
	)
' "$json_file" > "$tmp_json"

jq empty "$tmp_json"
mv "$tmp_json" "$json_file"

echo "Processed $processed homepage files"
echo "Detected cookie consent manager for $matched councils"
echo "Updated cookie_consent_manager in $json_file"
if [[ "$skipped" -gt 0 ]]; then
	echo "Skipped $skipped councils due to missing homepage file" >&2
fi
