#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
json_file="$script_dir/council-data.json"
heads_dir="$script_dir/heads"
errors_file="$script_dir/errors.txt"

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

if [[ ! -d "$heads_dir" ]]; then
	echo "Error: heads directory not found at $heads_dir" >&2
	exit 1
fi

extract_name() {
	sed -n '1s/^=== \(.*\) ===$/\1/p' "$1"
}

extract_url() {
	sed -n '2s/^URL: \(.*\)$/\1/p' "$1"
}

extract_title() {
	perl -0777 -ne '
		if (/<title\b[^>]*>(.*?)<\/title>/is) {
			$t = $1;
			$t =~ s/\s+/ /g;
			$t =~ s/^\s+|\s+$//g;
			$t =~ s/\t/ /g;
			print $t;
		}
	' "$1"
}

extract_description() {
	perl -0777 -ne '
		my $d;

		if (m{<meta\b(?=[^>]*\bname\s*=\s*["\x27]description["\x27])(?=[^>]*\bcontent\s*=\s*["\x27](.*?)["\x27])[^>]*>}is) {
			$d = $1;
		} elsif (m{<meta\b(?=[^>]*\bproperty\s*=\s*["\x27]og:description["\x27])(?=[^>]*\bcontent\s*=\s*["\x27](.*?)["\x27])[^>]*>}is) {
			$d = $1;
		} elsif (m{<meta\b(?=[^>]*\bname\s*=\s*["\x27]twitter:description["\x27])(?=[^>]*\bcontent\s*=\s*["\x27](.*?)["\x27])[^>]*>}is) {
			$d = $1;
		}

		if (defined $d) {
			$d =~ s/\s+/ /g;
			$d =~ s/^\s+|\s+$//g;
			$d =~ s/\t/ /g;
			print $d;
		}
	' "$1"
}

extract_generator_raw_value() {
	perl -0777 -ne '
		my $g;

		if (m{<meta\b(?=[^>]*\bname\s*=\s*["\x27]generator["\x27])(?=[^>]*\bcontent\s*=\s*["\x27](.*?)["\x27])[^>]*>}is) {
			$g = $1;
		}

		if (defined $g) {
			$g =~ s/\s+/ /g;
			$g =~ s/^\s+|\s+$//g;
			$g =~ s/\t/ /g;
			print $g;
		}
	' "$1"
}

tmp_updates="$(mktemp)"
tmp_descriptions="$(mktemp)"
tmp_generators="$(mktemp)"
tmp_json="$(mktemp)"
trap 'rm -f "$tmp_updates" "$tmp_descriptions" "$tmp_generators" "$tmp_json"' EXIT

: > "$errors_file"

processed=0
missing=0
descriptions_processed=0
descriptions_missing=0
generators_processed=0
generators_missing=0

while IFS= read -r file; do
	name="$(extract_name "$file")"
	url="$(extract_url "$file")"
	title="$(extract_title "$file")"
	description="$(extract_description "$file")"
	generator_raw_value="$(extract_generator_raw_value "$file")"

	if [[ -z "$name" ]]; then
		echo "Warning: could not parse council name from $file" >&2
		((missing += 1))
		continue
	fi

	if [[ -z "$title" ]]; then
		echo "Warning: no <title> found in $file" >&2
		printf 'Error: no <title> found\nURL: %s\nFile: %s\n\n' "${url:-Unknown URL}" "$file" >> "$errors_file"
		((missing += 1))
		continue
	fi

	printf '%s\t%s\n' "$name" "$title" >> "$tmp_updates"
	if [[ -n "$description" ]]; then
		printf '%s\t%s\n' "$name" "$description" >> "$tmp_descriptions"
		((descriptions_processed += 1))
	else
		echo "Warning: no description meta tag found in $file" >&2
		((descriptions_missing += 1))
	fi
	if [[ -n "$generator_raw_value" ]]; then
		printf '%s\t%s\n' "$name" "$generator_raw_value" >> "$tmp_generators"
		((generators_processed += 1))
	else
		echo "Warning: no generator meta tag found in $file" >&2
		((generators_missing += 1))
	fi
	((processed += 1))
done < <(find "$heads_dir" -type f -name '*.txt' | sort)

if [[ "$processed" -eq 0 ]]; then
	echo "Error: no valid title updates found in $heads_dir" >&2
	exit 1
fi

jq --rawfile updates "$tmp_updates" --rawfile descriptions "$tmp_descriptions" --rawfile generators "$tmp_generators" '
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

	(to_map($updates)) as $title_map
	| (to_map($descriptions)) as $description_map
	| (to_map($generators)) as $generator_map
	| map(
		if ($title_map[.name] // null) != null
		then .homepage_title = $title_map[.name]
		else .
		end
		| if ($description_map[.name] // null) != null
		  then .homepage_description = $description_map[.name]
		  else .
		  end
		| if ($generator_map[.name] // null) != null
		  then .generator_raw_value = $generator_map[.name]
		  else .
		  end
	)
' "$json_file" > "$tmp_json"

jq empty "$tmp_json"
mv "$tmp_json" "$json_file"

echo "Updated homepage_title for $processed councils in $json_file"
echo "Updated homepage_description for $descriptions_processed councils in $json_file"
echo "Updated generator_raw_value for $generators_processed councils in $json_file"
if [[ "$missing" -gt 0 ]]; then
	echo "Skipped $missing files due to missing names or <title> values" >&2
	echo "Wrote missing-title errors to $errors_file" >&2
fi
if [[ "$descriptions_missing" -gt 0 ]]; then
	echo "Skipped homepage_description for $descriptions_missing files due to missing meta description" >&2
fi
if [[ "$generators_missing" -gt 0 ]]; then
	echo "Skipped generator_raw_value for $generators_missing files due to missing generator meta tag" >&2
fi
