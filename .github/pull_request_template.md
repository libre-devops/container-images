## What and why

<!-- What this changes, and the reason for it. Link the issue if there is one. -->

## Checklist

- [ ] `just validate lint docs-check` passes
- [ ] `just test` and `just scan` pass for every image this changes
- [ ] Version changes are in `versions.yml`, with `versions.lock.json`, `images/locks/` and `README.md` regenerated (`just lock docs`)
- [ ] No scan finding is set aside except by a VEX statement with its justification
- [ ] No existing package or tag is renamed, re-tagged or removed
- [ ] UK English, and no en or em dashes
