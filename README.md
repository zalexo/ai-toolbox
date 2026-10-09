# AI Toolbox

Reusable mods and configurations for AI coding tools, maintained by [Alexei Yarilovets](https://github.com/zalexo).

[MIT license](LICENSE)

## Available now

| Tool | Configuration | Description |
| --- | --- | --- |
| Claude Code | [🕐 Clock](claude-code/mods/clock/) | Local time and the used share of the 5-hour and 7-day usage windows in the status line. |
| Codex | [Reserved section](codex/) | No configurations published yet. |

## Install Clock

Requires a Claude Code build with early-access TypeScript module hooks. Validated and tested with **2.1.289**; older builds such as 2.1.143 do not support this mod format.

In a compatible Claude Code session:

```text
/plugin marketplace add zalexo/ai-toolbox
/plugin install clock@ai-toolbox
```

Reload plugins or start a new session after installation. See the [Clock README](claude-code/mods/clock/README.md) for local loading, the display format, and tests.

## Support

Everything here is free to use under MIT. Donations are optional.

Support this project on [GitHub Sponsors](https://github.com/sponsors/zalexo) with a one-time donation or a monthly sponsorship, or on [Buy Me a Coffee](https://buymeacoffee.com/alexeyarilovets). See [donation details](docs/donations.md).

## Contribute

Suggestions, bug reports, and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before adding a configuration.

## License

[MIT](LICENSE): use, modify, and redistribute these files, including for commercial purposes, while keeping the copyright and license notice. Third-party AI tools retain their own licenses and terms. This is an independent community project.
