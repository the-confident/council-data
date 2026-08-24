# Council data

A collection of homepage metadata and technology detections for UK and Irish councils.

Each council record includes:

- council name, country, and homepage URL
- homepage title and description
- detected CMS and version information
- cookie consent manager
- analytics provider, variant, and version

## Detection approach

Detections are based on publicly served HTML, metadata, script URLs, and recognisable page markers. An empty value means that the relevant tool was not detected in the available evidence; it does not prove that the council does not use that tool elsewhere.

Analytics detections currently include Google Analytics, Matomo, Microsoft Clarity, Hotjar, Adobe Analytics, and Google Tag Manager-only signals. Cookie consent detections include several common third-party products as well as Drupal and site-specific implementations.

## Data maintenance

When adding or changing council records, keep the JSON valid and preserve the existing field structure. Re-fetch the relevant evidence and record any blocked or failed requests before updating inferred values.
