# octer-shell

**English** · [中文](README.zh.md)

Shell scripts that point [Hermes Agent](https://github.com/nousresearch/hermes-agent) at an [Octer.ai](https://octer.ai) custom LLM — you supply an API key (and optionally a model name), everything else is fixed.

There are two scripts plus a cleanup helper:

| Script | Platform | What it does |
|--------|----------|--------------|
| `set-hermes-model.sh` | Linux / macOS | Switch Hermes Agent to the Octer OpenAI-compatible endpoint |
| `set-hermes-model.ps1` | Windows / PowerShell | Same behavior as the `.sh`, written for PowerShell |
| `set-openclaw-model.sh` | Linux / macOS | Switch OpenClaw to the Octer custom model (OpenAI-compatible) |
| `set-openclaw-model.ps1` | Windows / PowerShell | Same behavior as the OpenClaw `.sh`, written for PowerShell |
| `test-all-models.sh` | Linux / macOS | Test every built-in model's Chat and Hermes tool-streaming paths |
| `clear-hermes-model.sh` | Linux / macOS | Remove all Octer-related config and restore the default |
| `clear-openclaw-model.sh` | Linux / macOS | Remove the Octer model config from OpenClaw and restore the default |
| `clear-openclaw-model.ps1` | Windows / PowerShell | Same behavior as the OpenClaw clear `.sh`, written for PowerShell |

## set-hermes-model.sh

Switch Hermes Agent's LLM to Octer's OpenAI-compatible API. The required argument is your API key. The model is chosen from an **interactive menu** ("dropdown") when you don't pass one, or via an optional second argument.

### Usage

```bash
./set-hermes-model.sh <API_KEY> [MODEL]
```

Example:

```bash
./set-hermes-model.sh evo_xxxxxxxxxxxxxxxx            # shows the interactive model menu (default gpt-5.5)
./set-hermes-model.sh evo_xxxxxxxxxxxxxxxx claude-opus-4-8    # explicit model, skips the menu
```

When no model argument is given, the script prints a numbered menu of the supported models and lets you pick one (press Enter for the default). In a non-interactive environment (pipe/CI) it falls back to the default `gpt-5.5`.

### Supported models

The menu (first item is the default) offers:

- `gpt-5.5` (default)
- `gpt-5.6-sol`
- `gpt-5.6-terra`
- `gpt-5.6-luna`
- `claude-opus-4-8`
- `gemini-3.1-pro-preview`
- `gemini-3-flash-preview`
- `gemini-3.5-flash`
- `deepseek-v4-flash`
- `deepseek-v4-pro`
- `glm-5.2`

You can still pass any other model name explicitly as the 2nd argument; it's used as-is with a warning if it's not in the list.

**All of these models are registered on the provider**, so the client's model selector (dropdown) lists every one of them — the menu / argument only decides which is the *active/default* model. In your app you can switch between them at any time without re-running the script.

### Test every model

```bash
./test-all-models.sh <API_KEY>
```

By default the script sequentially tests a basic Chat request and Hermes' critical `SSE + function tools` path for every built-in model. It prints a final matrix, HTTP statuses, concise errors, and upstream request IDs without displaying the API key.

Use environment variables to narrow or expand the matrix:

```bash
# Test only two models
OCTER_MODELS='gpt-5.5,glm-5.2' ./test-all-models.sh <API_KEY>

# Test Chat, Tools, SSE, SSE+Tools, reasoning+Tools, and Responses
OCTER_EXTENDED=1 ./test-all-models.sh <API_KEY>
```

Any failed case gives the script a non-zero exit status, making it suitable for CI. Set `OCTER_KEEP_RESULTS=1` to retain each payload, response header, and response body for gateway diagnosis.

### Fixed configuration

| Item | Value |
|------|-------|
| Endpoint | `https://oclaw.octer.ai/v1` |
| Protocol | OpenAI-compatible Chat Completions API (`chat_completions`) |
| Model | picked from the menu, or the optional 2nd argument (default `gpt-5.5`) |
| Provider slug | `custom:octer` |

The **API key** is required; the **model** comes from the interactive menu or the optional 2nd argument (default `gpt-5.5`); everything else is hard-coded.

### What the script does

It edits `config.yaml` directly (resolved via `hermes config path`) and writes both a named custom provider and the active model selection — Hermes only reads credentials from a **named** `custom_providers` entry, so setting `model.*` alone yields `No LLM provider configured`:

When invoked through `curl | bash`, the script automatically downloads the adjacent `hermes_config.py` helper from this repository into a temporary file and removes it when the install exits. A normal repository checkout continues to use its local helper.

1. **Canonical custom provider** — detects legacy Octer entries by provider identity (including suffixed aliases such as `Octer-2`), any `*.octer.ai` endpoint, or the Octer key environment variable; removes all of them from both supported provider schemas; then writes exactly one `custom_providers` item. Re-running the installer is idempotent. All supported models are registered and `discover_models: false` keeps the picker stable.
2. **One Chat Completions route** — sets `provider=custom:octer` and `api_mode=chat_completions` for every model. Octer's `/responses` route does not support all catalog models (for example GLM-5.2), while `/chat/completions` does.
3. **GPT-5.x compatibility** — writes model-scoped `agent.reasoning_overrides: false` entries for GPT-5.x. Chat Completions accepts GPT tools when reasoning is disabled, but rejects tools combined with an enabled `reasoning_effort`. Other model families retain their server-side reasoning defaults.
4. **Secret storage** — stores the key once as `OCTER_LLM_API_KEY` in Hermes' `.env` and references it with `key_env`; the key is no longer duplicated in `config.yaml`.
5. **Apply and verify** — validates/enables an installed Octer platform plugin, performs `gateway stop` + `gateway start` to clear detached processes, and treats a failed or timed-out `hermes -z` self-test as a script failure.

A timestamped backup of `config.yaml` is written before any change.

### Prerequisites

- `hermes` CLI installed and available on `PATH`.
- An OClaw API key — copy or reset it on the [OClaw page in the Octer console](https://octer.ai/workspace/o/?next=/o).
- Python 3 with `pyyaml`. The script auto-selects a suitable interpreter, preferring Hermes' own venv.

## set-hermes-model.ps1 (Windows / PowerShell)

Use this on Windows. Behavior is identical to `set-hermes-model.sh`: it writes one `custom:octer` provider, selects Chat Completions, stores the key in `.env`, fully reloads the Gateway, and runs the same bounded self-test.

### Usage

```powershell
.\set-hermes-model.ps1 <API_KEY> [MODEL]
```

Example:

```powershell
.\set-hermes-model.ps1 evo_xxxxxxxxxxxxxxxx            # shows the interactive model menu (default gpt-5.5)
.\set-hermes-model.ps1 evo_xxxxxxxxxxxxxxxx claude-opus-4-8    # explicit model, skips the menu
```

If the system blocks scripts (`running scripts is disabled on this system`), run:

```powershell
powershell -ExecutionPolicy Bypass -File .\set-hermes-model.ps1 <API_KEY> [MODEL]
```

### Differences from the .sh version (implementation only — the written result is identical)

- **Python discovery** — prefers Hermes' bundled venv (`hermes-agent\venv\Scripts\python.exe`), then tries `py -3` / `python` / `python3`; if none has `pyyaml`, falls back to `pip install --user pyyaml`.
- **60s self-test timeout** — implemented with a background PowerShell job (Windows has no `timeout <command>` semantics).
- **Encoding** — writes the temporary helper as UTF-8 without BOM to avoid garbled non-ASCII comments/output.

### Prerequisites (Windows)

- `hermes` CLI installed and on `PATH` (callable as `hermes`).
- Python 3 (`py -3` or `python`); the script finds/installs `pyyaml` automatically.
- An Octer.ai API key.

## set-openclaw-model.sh / set-openclaw-model.ps1

Switch OpenClaw to the Octer custom model — the same idea as the Hermes scripts, applied to OpenClaw's own config (`~/.openclaw/openclaw.json`) via `openclaw config set`. Fixed params: base URL `https://oclaw.octer.ai/v1`, OpenAI-compatible adapter (`openai-completions`), provider slug `octer`. The model is chosen from the same interactive menu (default `gpt-5.5`, see [Supported models](#supported-models)) when you don't pass one, or via an optional 2nd argument.

### Usage

```bash
# Linux / macOS
./set-openclaw-model.sh <API_KEY> [MODEL]
```

```powershell
# Windows / PowerShell
.\set-openclaw-model.ps1 <API_KEY> [MODEL]
```

Example (Linux / macOS):

```bash
./set-openclaw-model.sh evo_xxxxxxxxxxxxxxxx            # shows the interactive model menu (default gpt-5.5)
./set-openclaw-model.sh evo_xxxxxxxxxxxxxxxx claude-opus-4-8    # explicit model, skips the menu
```

### What the script does

1. **Register the provider** — `openclaw config set models.providers.octer '<json>' --strict-json --merge`, where `<json>`'s `models` array holds **all** supported models (`[{"id":"gpt-5.5","name":"gpt-5.5"}, …]`) so the client's model dropdown lists every one of them. If you passed a custom model not in the list, it's added too.
2. **Select the default model** — `openclaw models set octer/<MODEL>` (only sets the active/default; the dropdown still shows all registered models).
3. **Apply & self-test** — `openclaw gateway restart`, print `openclaw models status`, then run a non-fatal self-test (`openclaw agent --agent main -m "你好"`, capped at 60s) — mirroring the Hermes script's `hermes -z` check.

### Prerequisites

- `openclaw` CLI installed and on `PATH`.
- An OClaw API key — copy or reset it on the [OClaw page in the Octer console](https://octer.ai/workspace/o/?next=/o).

## clear-hermes-model.sh

Remove the Octer custom-model configuration and restore Hermes to its default. Hermes has no `config unset/remove`, so the script edits `config.yaml` directly (with a backup).

### Usage

```bash
./clear-hermes-model.sh

# Or run it directly through a pipe
curl -fsSL https://raw.githubusercontent.com/octer-ai/octer-shell/refs/heads/master/clear-hermes-model.sh | bash
```

When run through `curl | bash`, the script downloads the adjacent `hermes_config.py` to a temporary file and removes it on exit. Downloads have bounded connection and total timeouts; if GitHub Raw is unavailable, the script automatically falls back to jsDelivr instead of hanging indefinitely. The installer uses the same strategy.

It strips every Octer-related entry while leaving other providers (e.g. `qwen`) intact:

1. Drops the `model` override keys when its provider or URL points at Octer.
2. Removes Octer entries from both the list-shaped `custom_providers` schema and the keyed `providers` schema.
3. Deletes `OCTER_LLM_API_KEY` from `.env`.
4. Fully reloads the Gateway with `stop` + `start`.

To re-enable the Octer model afterwards, just run `./set-hermes-model.sh <API_KEY>` again.

## clear-openclaw-model.sh / clear-openclaw-model.ps1

The OpenClaw counterpart of `clear-hermes-model.sh`: remove the Octer provider and restore OpenClaw to its default, via `openclaw config unset`.

### Usage

```bash
# Linux / macOS
./clear-openclaw-model.sh
```

```powershell
# Windows / PowerShell
.\clear-openclaw-model.ps1
```

### What it does

1. `openclaw config unset models.providers.octer` — remove the provider written by `set-openclaw-model.sh` (other providers untouched).
2. `openclaw gateway restart`, then print `openclaw models status`.

If your default model still points at `octer`, pick another with `openclaw models set <model>` (or `openclaw onboard`). To re-enable the Octer model, run `./set-openclaw-model.sh <API_KEY>` again.

## Troubleshooting

If `hermes -z` hangs, hit the endpoint directly with `curl` to check whether the endpoint itself is the problem:

```bash
curl -sS https://oclaw.octer.ai/v1/chat/completions \
  -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  -d '{"model":"gemini-3-flash-preview","messages":[{"role":"user","content":"hi"}]}'
```
