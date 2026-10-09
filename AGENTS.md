# Repository instructions

Read README.md for the project scope and CONTRIBUTING.md for contribution rules.

Keep changes focused. Preserve mod behavior unless the requested change requires otherwise. Never import private AI settings, credentials, account data, or session history into this public repository.

Generated `.claude-plugin/types/` declarations stay local and ignored. Validate manifests and run the affected mod's tests with a Claude Code build supporting TypeScript module hooks. Do not convert module hooks to shell hooks to satisfy an older validator.

Write all repository documentation, comments, and public-facing text in English. Keep README.md accurate, including actual donation availability. Do not advertise a payment link until the owner has a working donation profile.

To publish a release, follow [docs/releasing.md](docs/releasing.md) and use `scripts/publish.sh`. Publish only when the maintainer asks, run `--dry-run` first, and never push to the public remote by other means.
