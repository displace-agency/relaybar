# Quota

**Know how much Claude and Codex you have left, and when each weekly limit resets.**

A free, open-source Mac menu bar app. Formerly RelayBar and ClaudeBar.

[**Download Quota 1.1.0 for Mac**](https://github.com/displace-agency/relaybar/releases/latest/download/Quota.dmg) · [Report an issue](https://github.com/displace-agency/relaybar/issues)

<p align="center">
  <img src="docs/screenshots/quota-limits-light.png" width="420" alt="Quota showing the weekly Claude limit remaining and when it resets" />
</p>

## Get started

1. [Download Quota.dmg](https://github.com/displace-agency/relaybar/releases/latest/download/Quota.dmg) (all versions on [Releases](https://github.com/displace-agency/relaybar/releases)).
2. Open it and drag **Quota** into **Applications**.
3. Open Quota. Click its menu bar item to see your limits.

Requires **macOS 13 or later**, on Apple Silicon or Intel, and an existing **Claude Code and/or Codex login** on this Mac. Each provider works independently, and every Claude account signed in on this Mac gets its own card. Quota uses your existing subscription login; it does not require another account.

**First launch:** this community build is not Apple-notarized. If macOS blocks it, first try opening it, then use **System Settings → Privacy & Security → Open Anyway** if you trust the download. See [Apple's instructions](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally.

**Upgrading from RelayBar or ClaudeBar?** Quit the old app first, replace it with Quota, and keep one copy in Applications. The bundle identity stays the same so existing settings can carry over.

## What you can see

- **Limits:** both weekly quotas, reset countdowns, exact local reset dates, and shorter session windows when the provider reports them.
- **Menu bar:** weekly reset countdowns for Claude (`C`, or `C1`, `C2`, … with several accounts) and Codex (`O`). A `~` means the reading is stale.
- **Overview:** today's local token activity and model breakdown for the selected provider.
- **Sessions:** local conversations grouped by project, sorted by recent activity or size.
- **History:** calendar-based 7-day and 30-day totals, daily activity, and weekly charts.
- **Launch at login:** an optional native setting.

<p align="center">
  <img src="docs/screenshots/quota-menubar-label.png" width="180" alt="Quota menu bar label with a weekly reset countdown" />
</p>

Quota always uses its light look, in light and dark macOS, and the popover is only as tall as its content. The screenshots come from one opt-in live capture and show real readings: the light Limits view, the menu bar label, the Claude Overview (only with real local Claude activity), and the Codex Overview (only with real local Codex activity). Overviews use local aggregate token totals only. Your percentages, reset dates, and available windows will differ.

## What the numbers mean

**Subscription quota and token history are different measurements.** The providers supply the quota percentages and reset timestamps. Quota does not estimate a subscription's allowance from token counts or assume a fixed number of tokens for a “20x” plan.

Codex's quota is for **Codex usage on your ChatGPT plan**. It is not a combined meter for every ChatGPT model, OpenAI API billing, or all activity on other devices.

Local token history comes from files on this Mac:

- Claude Code: `~/.claude/projects/` plus the `projects/` folder of every other Claude profile found (see below)
- Codex: `~/.codex/sessions/` and `~/.codex/archived_sessions/`, or `CODEX_HOME` when set

The headline token total is new input plus output. Cache reads and cache writes are displayed separately. Codex reasoning output is not counted twice, and repeated cumulative records across resumed/archived sessions are deduplicated.

Claude's optional dollar figures are approximate API equivalents using the original app's model-family rate table, **not subscription charges or a billing reconciliation**. Codex dollar estimates are hidden.

## Multiple Claude accounts

Sign the second account in through its own Claude Code config folder:

```bash
CLAUDE_CONFIG_DIR=~/.claude-2 claude
# then run /login
```

Quota looks for the default profile (`~/.claude`), any folder in your home directory named `.claude*` that holds a `.claude.json` or `.credentials.json` (for example `.claude-2` or `.claude-work`), and the `CLAUDE_CONFIG_DIR` folder if the app process has one. Each account gets a card labeled with its email address, and local history combines all of their transcripts. New profiles appear on the next refresh, without relaunching. With two or more Claude accounts the menu bar shows `C1`, `C2`, … in that order (default profile first, then by folder name). A single account looks exactly as before.

## Privacy and reliability

- Conversation text stays on your Mac. No telemetry or analytics.
- Subscription checks make read-only HTTPS requests to Anthropic and OpenAI usage endpoints.
- Existing credentials are read into memory from Claude's Keychain entry (or its credential-file fallback) and Codex's existing `auth.json`.
- Quota never saves credentials, changes accounts, refreshes login tokens, or makes paid model requests.
- Quota checks run at most once per minute and back off after rate-limit responses, separately for each account.
- Unknown reset dates stay unknown. Failed checks show an error alongside any last-known reading and its timestamp.
- Quota checks run independently from local history scanning. A large history can take longer on first launch; unchanged files are cached in memory afterward.

Usage endpoints follow [claude-swap](https://github.com/realiti4/claude-swap) and the [Codex backend client](https://github.com/openai/codex/tree/main/codex-rs/backend-client). Provider changes can require app updates. Quota is an independent project and is not affiliated with Anthropic or OpenAI.

## Troubleshooting

**One provider is unavailable:** open that provider's CLI and verify you are signed in with a subscription. Wait a minute, then refresh Quota. API-key-only logins do not provide subscription quota.

**Credentials expired or access denied:** reconnect in Claude Code or Codex. For a second Claude account, open Claude with that profile folder (`CLAUDE_CONFIG_DIR=<folder> claude`). Quota deliberately does not change your login. A custom CLI configuration must also be visible to the app process.

**No session window:** some accounts only return a weekly window. Quota shows the data the provider supplies.

**History takes time to load:** the initial scan reads existing local transcripts. Quota cards can load while that work finishes.

## Build from source

Requires Xcode Command Line Tools.

```bash
git clone https://github.com/displace-agency/relaybar.git
cd relaybar
swift test
./scripts/build-app.sh 1.1.0
```

Output: `build/Quota.app`, universal for Apple Silicon and Intel. The build does not install or launch it. Previous build output is preserved before replacement.

Builds use ad-hoc signing by default. Set `CODESIGN_IDENTITY` to an installed signing identity for a stable local signature. Apple notarization is not configured.

The internal Swift module remains `ClaudeBar` and the bundle identifier remains `agency.displace.ClaudeBar` for continuity.

Optional developer checks:

```bash
RELAYBAR_LIVE_USAGE_TEST=1 swift test --filter SubscriptionUsageTests
RELAYBAR_PREVIEW_DIR=/tmp/relaybar-preview swift test --filter PreviewTests
```

Live checks print sanitized quota summaries only. Fixture tests require no login or network. See [test coverage](docs/QA.md).

## Credits and license

Built by [Displace Agency](https://github.com/displace-agency).

Codex transcript schema handling is adapted from Flavio Adamo's MIT-licensed SpendBar; its license is retained in the source. Claude quota research follows realiti4's claude-swap. No account-switching dependency is installed.

[MIT License](LICENSE)
