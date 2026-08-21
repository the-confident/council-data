# Council data

A collection of homepage metadata and technology detections for UK and Irish councils.

The main dataset is [`council-data.json`](council-data.json). Each council record includes:

- council name, country, and homepage URL
- homepage title and description
- detected CMS and version information
- cookie consent manager
- analytics provider, variant, and version

## Evidence

- [`homepages/`](homepages/) contains downloaded homepage HTML.
- `councils.html` and `councils_files/` contain the source council list and downloaded page assets.

Some sites cannot be fetched because of HTTP errors, edge protection, or other network failures. Check `homepages/errors.txt`, `heads/errors.txt`, and [`errors.txt`](errors.txt) when interpreting missing detections.

## Requirements

The shell scripts require:

- Bash
- `curl`
- `jq`
- Perl

## Workflow

Run commands from this directory.

1. Fetch complete homepage HTML:

   ```sh
   ./get-homepage-html.sh
   ```

2. Fetch and extract only the `<head>` tag:

   ```sh
   ./get-head-tag.sh
   ```

3. Update homepage titles, descriptions, and generator metadata:

   ```sh
   ./update-homepage-titles.sh
   ```

4. Update cookie consent manager detections:

   ```sh
   ./update-cookie-consent-managers.sh
   ```

5. Update analytics provider detections:

   ```sh
   ./update-analytics.sh
   ```

The update scripts modify `council-data.json`. Some scripts also write TSV reports describing their findings. Review the generated reports and the evidence files before treating a detection as authoritative. The inference scripts use the available files in `heads/` and `homepages/`, and can replace existing detected values with blank values when no matching marker is found.

## Detection approach

Detections are based on publicly served HTML, metadata, script URLs, and recognisable page markers. An empty value means that the relevant tool was not detected in the available evidence; it does not prove that the council does not use that tool elsewhere.

Analytics detections currently include Google Analytics, Matomo, Microsoft Clarity, Hotjar, Adobe Analytics, and Google Tag Manager-only signals. Cookie consent detections include several common third-party products as well as Drupal and site-specific implementations.

## Data maintenance

When adding or changing council records, keep the JSON valid and preserve the existing field structure. Re-fetch the relevant evidence and record any blocked or failed requests before updating inferred values.
