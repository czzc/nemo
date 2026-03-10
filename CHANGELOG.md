#### v1.0.4

- Fix NemoDB reassignment during v1 migration that could cause data loss
- Fix undefined behavior: mutating the table during pairs() iteration
- Extract SnapshotFishingTime() helper to deduplicate fishing time logic
- Fix typo in tooltip comment
