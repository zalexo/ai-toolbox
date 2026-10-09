# Contributing

Write documentation, comments, and public-facing text in English.

Place Claude Code mods under `claude-code/mods/<name>/` and Codex configurations under `codex/<name>/`. Give each item a README with its purpose, requirements, installation, removal, and an example.

Only contribute files you can distribute under the repository's MIT license. Preserve any applicable third-party notices. Keep credentials, personal conversations, account data, and generated engine declarations out of commits.

For a Claude Code mod, use a stable kebab-case manifest name, keep its marketplace entry consistent, and verify with a compatible Claude Code build:

```sh
claude plugin validate .
claude plugin validate ./claude-code/mods/clock
claude plugin test ./claude-code/mods/clock
```

Replace `clock` with the mod you changed. Record the tested version and results in your pull request. Keep changes focused; update the root catalog when adding a new item.

## Releases

The maintainer develops in a private source repository and publishes each release here as a single commit. Pull requests merged here are carried into the next release. See [docs/releasing.md](docs/releasing.md).
