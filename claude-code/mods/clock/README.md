# 🕐 Clock

A Claude Code mod that shows local time and the percentage of the 5-hour and 7-day usage limits already used:

```text
14:31  23%  41%
```

The display order is **time → 5-hour used percentage → 7-day used percentage**. Values are rounded to the nearest integer. Before any rate-limit reading arrives, only the time is shown. Once either window has a reading, an omitted window displays as `0%`.

The mod refreshes at the next minute boundary, then every minute, when rate limits change, and after a turn completes. It also closes the legacy pane named `clock` on session start. It writes to Claude Code's shared status line, so another mod writing there may replace its display.

## Compatibility

Requires the early-access **TypeScript module hooks API**, including `$.session.usage()`, `$.ui.status()`, and `$.clock`. Manifest validation and all four supplied tests passed with **Claude Code 2.1.289**. This API may change between releases.

Claude Code 2.1.143 does not accept the `modules` hook format. If validation says `hooks: Invalid input: expected record, received undefined`, check the actual binary version with `claude --version`; the desktop engine may be newer than the command on your shell's PATH.

## Install from GitHub

In a compatible Claude Code session:

```text
/plugin marketplace add zalexo/ai-toolbox
/plugin install clock@ai-toolbox
```

Reload plugins or start a new session. The public distribution uses the name `clock`; the original local mod was named `🕐`, version 0.3.0. The hook implementation is unchanged. Disable your existing copy before loading this distribution to avoid duplicate timers.

## Load a local copy

From the repository root, with a compatible `claude` executable:

```sh
claude --plugin-dir ./claude-code/mods/clock
```

The flag loads the mod for that session. To stop loading it, omit the flag in the next session.

## Validate and test

```sh
claude plugin validate ./claude-code/mods/clock
claude plugin test ./claude-code/mods/clock
```

The tests cover time formatting, percentage formatting, selecting rate-limit windows, and status updates through mocked clock and session events in Claude Code's mod test runtime.

The engine generates `.claude-plugin/types/` when it loads an owned mod folder. Those declarations are ignored by Git. The included `tsconfig.json` expects them for editor type checking.

## Remove

For a marketplace installation:

```text
/plugin uninstall clock@ai-toolbox
```

Start a new session after uninstalling.

## License

[MIT](../../../LICENSE).
