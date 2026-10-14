# claude-code-provider (`ccp`)

Point Claude Code at another Anthropic-compatible provider with every model slot set, then test it with one tiny request.
A single Node file with no dependencies. Last checked: **2026-10-14**, Claude Code 2.1.296.

```sh
ccp use deepseek        # writes the env block to ~/.claude/settings.json (backup first)
ccp check               # one tiny /v1/messages request: OK, auth wrong, model_not_found, or extra /v1
ccp reset               # puts back what was there before
```

## How do I point Claude Code at another provider without model_not_found errors?

Set **all** of these, not only the base URL and `ANTHROPIC_MODEL`:

| Variable | Value |
| --- | --- |
| `ANTHROPIC_BASE_URL` | the provider's Anthropic-compatible URL, **without `/v1`** |
| `ANTHROPIC_AUTH_TOKEN` | your key (sent as `Authorization: Bearer`), with `ANTHROPIC_API_KEY=""` so no second key header goes out |
| `ANTHROPIC_MODEL` | a model ID the provider accepts |
| `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_FABLE_MODEL` | model IDs the provider accepts |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` (and the deprecated `ANTHROPIC_SMALL_FAST_MODEL`) | a model ID for background work |
| `CLAUDE_CODE_SUBAGENT_MODEL` | a model ID for subagents |

Claude Code's built-in aliases request Anthropic IDs such as `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-haiku-5-5` and `claude-fable-5-1`. Most Anthropic-compatible providers don't serve those IDs, so any request that goes through an unset slot fails with `model_not_found` even though your main model works.

`ccp use <preset>` writes that whole block for you, and `ccp check` tells you which part is wrong.

### The four mistakes behind most failures

1. **Setting only `ANTHROPIC_MODEL`.** The main chat works, but the slots behind it still ask for Anthropic IDs. In our test run with only `ANTHROPIC_MODEL` set, `/model sonnet`, `opus`, `haiku` and `fable` still requested `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-haiku-5-5` and `claude-fable-5-1`, and auto mode's permission classifier requested `claude-sonnet-5`. Those are the errors that show up "randomly" mid-session.
2. **`/v1` on the base URL.** Claude Code appends `/v1/messages` itself, so `ANTHROPIC_BASE_URL=https://host/v1` makes it call `https://host/v1/v1/messages`, which is a 404.
3. **The wrong key variable, or two of them.** `ANTHROPIC_AUTH_TOKEN` is sent as `Authorization: Bearer`; `ANTHROPIC_API_KEY` is sent as `x-api-key`. If both are set, both headers go out, so an old Anthropic key in your shell profile rides along to the other provider. Set the one your provider documents and blank the other (`ANTHROPIC_API_KEY=""` sends no header).
4. **A value from somewhere else wins.** The `env` block in `~/.claude/settings.json` (and a project's `.claude/settings.json` / `.claude/settings.local.json`) overrides your shell exports. An old export or settings entry quietly keeps the previous provider. `ccp show` prints the effective values and where each one comes from.

Also good to know: a `[1m]` suffix on a model ID (`kimi-k3[1m]`) tells Claude Code the model has a 1M-token context. Claude Code drops the suffix before sending, so the provider sees `kimi-k3`. Without it, Claude Code assumes 200K for model IDs it doesn't know.

## Install

Needs Node 18 or newer (`ccp check` also needs `curl`). Claude Code's native installer doesn't install Node, so check `node -v` first.

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/henrikdukefoss/claude-code-provider/main/ccp -o ~/.local/bin/ccp
chmod +x ~/.local/bin/ccp     # make sure ~/.local/bin is on your PATH
```

Or just download `ccp` and run it with `node ccp ...`. It's one file; read it before you run it.

## Usage

```sh
# A preset. The key comes from the preset's env var, $CCP_API_KEY, or a hidden prompt.
export DEEPSEEK_API_KEY=...        # or leave it unset and type it at the prompt
ccp use deepseek
ccp check

# Any Anthropic-compatible provider.
ccp use --base-url https://YOUR_PROVIDER/anthropic --model MODEL_ID --small-model SMALL_MODEL_ID

# Change models on top of a preset.
ccp use openrouter --model deepseek/deepseek-v4-flash   # every slot
ccp use kimi --haiku kimi-k2.7-code                      # one slot

# Back to Anthropic.
ccp reset                 # restores the provider values from before ccp's first change
ccp reset --defaults      # removes them all (same as `ccp use anthropic`)
```

| Command | What it does |
| --- | --- |
| `ccp use <preset>` | Writes base URL, key, every model slot and the vendor's recommended extras to the `env` block of `~/.claude/settings.json`. Other settings are left alone. The first change saves `settings.json.ccp-backup`. |
| `ccp use ... --profile [PATH]` | Writes a shell file to source instead (default `~/.config/claude-code-provider/env.sh`). If the key came from an env var, the file references `${THAT_VAR}` instead of storing the key. |
| `ccp use ... --settings PATH` | Another settings file, e.g. `.claude/settings.local.json` for one project. |
| `ccp check` | Reads the same settings Claude Code reads, warns about unset slots, and sends one `POST /v1/messages` (16 max tokens) with the main model. |
| `ccp check --all` | One request per distinct model across all slots, including the Anthropic IDs that unset slots fall back to. |
| `ccp reset` | Restores the values from the backup (or removes them with `--defaults`). Add `--profile` to remove the shell file. |
| `ccp show` | The effective provider settings and where each came from. Keys are shown as "set (N chars)". |
| `ccp presets` | The presets with their source links. |

Options for `use`: `--model`, `--small-model`, `--main/--opus/--sonnet/--haiku/--fable/--subagent`, `--auth bearer|x-api-key`, `--key-env NAME`, `--no-key`, `--workspace ID`, `--dry-run`.

### What `ccp check` reports

```text
$ ccp check
Claude Code will call: https://api.deepseek.com/anthropic/v1/messages   (ANTHROPIC_BASE_URL from ~/.claude/settings.json)
     auth: Authorization: Bearer (ANTHROPIC_AUTH_TOKEN from ~/.claude/settings.json)
     ANTHROPIC_MODEL                 deepseek-flash[1m]
     ...
OK   model deepseek-flash (Claude Code drops the [1m] suffix): request accepted (HTTP 200).
```

| Result | Meaning |
| --- | --- |
| `OK` | The provider accepted the key and the model. |
| `auth rejected` | HTTP 401/403. Says which header the key went in, and suggests the other one. |
| `model_not_found` | The provider doesn't serve that ID. Use the ID from its docs or `GET /v1/models`. |
| `extra /v1` | The base URL ends in `/v1`. ccp retries without it and tells you whether that works. |
| `no /v1/messages at this base URL` | 404 that isn't about the model: not the provider's Anthropic-compatible URL. |
| `rate-limited` | HTTP 429: the key works, the account is out of quota or throttled. |
| `could not connect` | DNS, network or a local proxy that isn't running. |

The exit code is 0 when everything passed and 1 otherwise, so `ccp check` works in scripts.

## Presets

Base URLs and model IDs are copied from each vendor's own Claude Code or Anthropic-API page, linked below. Slots a vendor's page leaves out get the vendor's main model (or its small model for the Haiku slot). Listed alphabetically after Anthropic; no ranking is implied.

| Preset | Provider | `ANTHROPIC_BASE_URL` | Main / Haiku-slot model | Key env var | Source |
| --- | --- | --- | --- | --- | --- |
| `anthropic` | Anthropic (default) | unset | Claude Code's defaults | your login or `ANTHROPIC_API_KEY` | [model config](https://code.claude.com/docs/en/model-config) |
| `deepseek` | DeepSeek | `https://api.deepseek.com/anthropic` | `deepseek-flash[1m]` / `deepseek-flash` | `DEEPSEEK_API_KEY` | [Integrate with Claude Code](https://api-docs.deepseek.com/guides/coding_agents) |
| `kimi` | Moonshot AI (Kimi) | `https://api.moonshot.ai/anthropic` | `kimi-k3[1m]` / `kimi-k3` | `MOONSHOT_API_KEY` | [Use Kimi in Claude Code](https://platform.kimi.ai/docs/guide/claude-code-kimi) |
| `litellm` | LiteLLM proxy (self-hosted) | `http://localhost:4000` | your `model_name` (`--model` required) | `LITELLM_API_KEY` | [Claude Code with LiteLLM](https://docs.litellm.ai/docs/tutorials/claude_responses_api) |
| `minimax` | MiniMax | `https://api.minimax.io/anthropic` | `MiniMax-M3.1-Flash-Preview[1m]` (all slots) | `MINIMAX_API_KEY` | [Claude Code](https://platform.minimax.io/docs/m-plan/claude-code) |
| `openrouter` | OpenRouter | `https://openrouter.ai/api` | `~anthropic/claude-opus-latest[1m]` / `~anthropic/claude-haiku-latest` | `OPENROUTER_API_KEY` | [Claude Code integration](https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration) |
| `qwen` | Alibaba Model Studio (Qwen), pay-as-you-go, Singapore | `https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/apps/anthropic` | `qwen3.7-max` / `qwen3.6-flash` | `DASHSCOPE_API_KEY` | [Claude Code](https://www.alibabacloud.com/help/en/model-studio/claude-code) |
| `qwen-coding` | Alibaba Model Studio (Qwen), Coding Plan | `https://coding-intl.dashscope.aliyuncs.com/apps/anthropic` | `qwen3.7-plus` (all slots) | `DASHSCOPE_API_KEY` | [Claude Code](https://www.alibabacloud.com/help/en/model-studio/claude-code) |
| `standardcompute` | Standard Compute | `https://api.stdcmpt.com` | `standardcompute` (all slots) | `STANDARDCOMPUTE_API_KEY` | [Messages API](https://docs.standardcompute.com/api/messages), [Claude Code](https://docs.standardcompute.com/agents/claude-code) |
| `zai` | Z.ai (GLM Coding Plan) | `https://api.z.ai/api/anthropic` | `glm-5.3-flash[1m]` (all slots) | `ZAI_API_KEY` | [How to switch models](https://docs.z.ai/devpack/latest-model), [Claude Code](https://docs.z.ai/scenario-example/develop-tools/claude) |

Every preset uses `ANTHROPIC_AUTH_TOKEN` (Bearer), as each vendor's Claude Code page does, and blanks `ANTHROPIC_API_KEY`. Notes:

- **DeepSeek, Kimi, MiniMax, Z.ai** also get the extras their pages recommend: `CLAUDE_CODE_EFFORT_LEVEL=max` (DeepSeek, Kimi), `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (Kimi 1000000, MiniMax 524288, Z.ai 1000000) and `API_TIMEOUT_MS=3000000` (Z.ai). `ccp reset` removes them too.
- **Kimi**: Kimi's example puts `kimi-k2.7-code` in the Haiku slot. Kimi's page also says that model rejects requests with thinking turned off, and in our test Claude Code's background request (the WebFetch summary) sent no `thinking` field. So the preset uses `kimi-k3` there. `--haiku kimi-k2.7-code` follows Kimi's example exactly.
- **Z.ai** maps Claude IDs to GLM on its side when you set no models. The preset pins `glm-5.3-flash[1m]` as Z.ai's "How to switch models" page shows; Z.ai notes that pinning means you won't follow their default model updates automatically.
- **Alibaba**: the pay-as-you-go URL needs your Workspace ID (`--workspace ID`). For Beijing or Virginia pass `--base-url` with `cn-beijing` or `us-east-1`. Keys only work in the region where you created them, and Coding Plan keys only work with `qwen-coding`.
- **OpenRouter** asks for `ANTHROPIC_API_KEY=""` explicitly, which ccp always writes for Bearer providers. Any OpenRouter slug works with `--model`.
- **LiteLLM** model IDs are the `model_name` entries in your proxy's `config.yaml`. The key is your master key or a virtual key.
- **Standard Compute** accepts `standardcompute` (the gateway picks a model per request) or a catalog ID such as `anthropic/claude-sonnet-5.5` via `--model`.

Anthropic's docs say routing Claude Code to non-Claude models isn't supported by Anthropic. Many providers do it anyway; expect differences in tool use and thinking.

Missing a provider? Open a PR adding it to `PRESETS` in `ccp` with a link to the vendor's page that shows the base URL and model IDs.

## Keys

- ccp never prints a key. It reads it from an env var or a hidden prompt (nothing is echoed), and `ccp show` only says "set (N chars)".
- In settings mode the key is written to the `env` block of `~/.claude/settings.json`, as most of the vendor guides above show, and the file is set to mode 600. Don't commit that file to a dotfiles repo. `--profile` keeps the key out of files when it comes from an env var. `--no-key` writes everything except the key.
- `ccp check` passes headers to curl on stdin, so the key doesn't appear in the process list, and sends it only to the base URL you configured.

## How this was checked

The real Claude Code CLI (2.1.296) ran in a throwaway `HOME` with only `PATH` and `HOME` in its environment, so every setting came from the `settings.json` that ccp wrote. It talked to a local mock `/v1/messages` server ([`test/mock-server.mjs`](test/mock-server.mjs)) that logs the model ID and which auth header arrived. [`test/e2e.sh`](test/e2e.sh) reproduces it; [`test/results-2026-10-14.txt`](test/results-2026-10-14.txt) is the full output of the last run.

| Setup | What Claude Code requested |
| --- | --- |
| Base URL and key only, no model variables | main chat `claude-opus-5-5`; `--model sonnet` `claude-sonnet-5-5`; `haiku` `claude-haiku-5-5`; `fable` and `best` `claude-fable-5-1` |
| Only `ANTHROPIC_MODEL` set | main chat and WebFetch summary use it; the `opus`/`sonnet`/`haiku`/`fable` aliases still request the Claude IDs above; auto mode's permission classifier requests `claude-sonnet-5` |
| ccp with a different ID in every slot | main chat → `ANTHROPIC_MODEL`; `--model opus/sonnet/haiku/fable` → the matching `ANTHROPIC_DEFAULT_*_MODEL`; `opusplan` outside plan mode → Sonnet slot; subagent → `CLAUDE_CODE_SUBAGENT_MODEL`; WebFetch summary (background) → Haiku slot; auto-mode classifier → Sonnet slot |
| `ANTHROPIC_SMALL_FAST_MODEL` only | WebFetch summary uses it (deprecated, still read) |
| Model ID with `[1m]` | sent without the suffix |
| `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_API_KEY=""` | `Authorization: Bearer` only |
| `ANTHROPIC_API_KEY` only / both set | `x-api-key` only / both headers |
| Every preset, base URL pointed at the mock, mock accepting only the preset's model IDs | main chat, WebFetch summary, subagent, auto-mode classifier and all four aliases used the preset's IDs, with Bearer auth. No `model_not_found` |
| `--profile` file, sourced | same requests as settings mode |

`ccp check` was run against the mock for each failure mode (wrong key, unknown model, base URL with `/v1`, wrong path, unreachable port, no key, no model slots), and against the live endpoints of DeepSeek, Moonshot, Z.ai, MiniMax, OpenRouter, Alibaba (Coding Plan) and Standard Compute with an invalid key: each reported `auth rejected`. `https://api.stdcmpt.com/v1` was reported as an extra `/v1`.

Not checked: requests with real keys to each provider. The preset model IDs come from the vendors' pages, which change often. If one is out of date, `ccp check` shows `model_not_found`, and a PR with the new ID and a source link fixes it for everyone.

Related: [agent-provider-configs](https://github.com/henrikdukefoss/agent-provider-configs) has copy-paste configs for 20 coding agents and the same Claude Code findings. [CC Switch](https://github.com/farion1231/cc-switch) is a desktop app that switches Claude Code providers; ccp is a single file for the terminal and adds the `check` diagnosis.

## Related guides

Written by Standard Compute, which maintains ccp:

- [Claude Code without the 5-hour and weekly limits](https://standardcompute.com/claude-code-without-weekly-limits): every option, how to set it up, and the catch with each. Also in: [Español](https://standardcompute.com/claude-code-limite-de-uso) · [Português](https://standardcompute.com/claude-code-plano-mensal-fixo) · [Deutsch](https://standardcompute.com/claude-code-flatrate) · [Français](https://standardcompute.com/claude-code-cout-fixe)
- [Claude Code with other models](https://standardcompute.com/claude-code-other-models): DeepSeek, GLM, Kimi, GPT and Gemini behind Claude Code, and what changes.
- [Fixing "model does not exist" (404)](https://standardcompute.com/fix/model-not-found): the same `model_not_found` that `ccp check` reports, across providers.
- [Claude Code pricing](https://standardcompute.com/claude-code-pricing): plans and real API cost per day.
- [Cheapest way to run Claude Code](https://standardcompute.com/cheapest-way-to-run-claude-code): six options by price.

## About

Maintained by [Standard Compute](https://standardcompute.com), which is one of the presets above. The tool is provider-neutral: every preset is sourced from its vendor's docs, and `--base-url` works with any Anthropic-compatible API.

MIT License. Provider and product names belong to their owners.
