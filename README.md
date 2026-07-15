# Local Agent: Ollama + Open WebUI + Open Terminal

A Claude.ai-like local setup: a browser-based chat UI, running against your
local Ollama model, with autonomous shell/code execution in an isolated
sandbox and results (charts, HTML, diagrams) rendered inline in the chat.

## How it fits together

```
  You (browser, http://localhost:3000)
        │
        ▼
   open-webui  ──── HTTP ────▶  Ollama (native on the Mac host, GPU-accelerated)
        │
        │ tool calls (run_command, read_file, write_file, ...)
        ▼
   open-terminal (isolated Docker container, sandbox)
        │
        ▼
   ./workspace  (bind-mounted, visible on your Mac too)
```

open-webui is the interface (chat, artifact rendering, code interpreter,
file browser). open-terminal is the sandbox the model actually acts in —
open-webui calls it as a tool over HTTP; the model never touches your Mac
directly. Ollama stays outside Docker entirely so it gets full GPU/unified-
memory performance.

## Setup

1. **Run Ollama natively** (not in Docker), for GPU performance:
   ```bash
   brew install ollama
   ollama serve
   ```

2. **Pull a tool-calling-capable model with an extended context window.**

   **Important: use Gemma 4, not Gemma 3.** Gemma 3's chat template has no
   tool-calling support in Ollama at all — any request with `tools` fails
   outright with `does not support tools`, regardless of context size or
   Modelfile settings. Gemma 4 has native function-calling built into its
   template. (There were early reports of Ollama's tool-call parsing being
   flaky for Gemma 4 right after its release — worth a quick sanity check
   below, and worth making sure Ollama itself is reasonably current via
   `brew upgrade ollama` if you hit issues.)

   **This project uses `gemma4:26b`** — the MoE (Mixture-of-Experts)
   variant, not the dense `31b`. It only activates ~4B parameters per token
   despite 26B total, so it's both faster and has a smaller memory
   footprint than the dense model (memory tracks total parameters, not
   active ones — 26B total is simply less than 31B total). See "Faster
   local inference" further down for the comparison if you want to try the
   dense `31b` instead for its slightly higher ceiling on hard reasoning
   tasks.

   ```bash
   ollama pull gemma4:26b
   ```

   Quick sanity check that tool calling actually works before wiring it
   into Open WebUI:
   ```bash
   curl http://localhost:11434/api/chat -d '{
     "model": "gemma4:26b",
     "messages": [{"role":"user","content":"What is the weather in Paris?"}],
     "tools": [{"type":"function","function":{"name":"get_weather","description":"Get weather for a location","parameters":{"type":"object","properties":{"location":{"type":"string"}},"required":["location"]}}}]
   }'
   ```
   You want to see a `tool_calls` block in the response, not plain text and
   not an error.

   Then create an extended-context variant — agentic tool-calling
   (multi-step: call a tool, read output, decide next step, repeat) needs
   more headroom than Ollama's 4k default. **This project uses a 64k
   context window** (`num_ctx 65536`) rather than the more common 32k —
   set deliberately larger here for other purposes beyond just tool-calling
   headroom, so don't shrink it back down to 32k on the assumption that's
   overkill:
   ```bash
   ollama run gemma4:26b
   >>> /set parameter num_ctx 65536
   >>> /save gemma4:26b-64k
   >>> /bye
   ```

3. **Set a real Open Terminal API key.** The `.env` file goes in the
   **project root — the same directory as `docker-compose.yml`** — not
   inside `./workspace/` and not your Mac's home directory. Docker Compose
   automatically reads a file literally named `.env` from wherever you run
   `docker compose up`, and uses it to fill in the
   `${OPEN_TERMINAL_API_KEY:-...}` placeholder in `docker-compose.yml`.
   Keep it out of `workspace/` specifically — that folder is bind-mounted
   straight into the sandbox container, so a secret placed there would be
   directly readable by the model.

   Expected layout:
   ```
   local-agent-webui/
   ├── docker-compose.yml
   ├── .env                 ← here
   ├── README.md
   └── workspace/
       └── (your files)
   ```

   ```bash
   cd local-agent-webui   # wherever you saved this project
   cp .env.example .env
   # edit .env and set OPEN_TERMINAL_API_KEY to the output of:
   openssl rand -base64 32
   ```
   `.env` is a dotfile, so `ls` won't show it by default — use `ls -a` to
   confirm it's there before running `docker compose up`.

4. **Put files to analyze in `./workspace/`** — this becomes the sandbox's
   home directory, mounted into `open-terminal` at `/home/user`.

5. **Start everything:**
   ```bash
   docker compose up -d
   ```

6. **Open `http://localhost:3000`** and create a local account (stored only
   in your own `open-webui-data` volume — nothing leaves your machine).

7. **Connect Open Terminal to Open WebUI:**
   - Go to **Admin Settings → Integrations → Open Terminal**
   - URL: `http://open-terminal:8000` (container-to-container, via the
     `agent-net` Docker network — not `localhost`)
   - API key: the value you put in `.env`
   - Save. You should see a file-browser sidebar appear for it.

8. **Leave Code Interpreter OFF and explicitly attach Open Terminal to the
   model.** Two things are both required — connecting Open Terminal and
   turning off Code Interpreter is *necessary but not sufficient* on its
   own; the model also needs to be explicitly told which terminal to use.

   First, the mutual-exclusivity part: **Code Interpreter and Open Terminal
   cannot both be active for the same model.** Code Interpreter only ever
   runs Python (via Pyodide or Jupyter), with no shell access at all — no
   `awk`, `sed`, `grep`, or anything outside Python. Leave **Code
   Interpreter unchecked** at **Admin Settings → Settings → Models → ⚙️ →
   Default Model Metadata**.

   Then, the actual attachment step (easy to miss): go to
   **Admin Settings → Settings → Models**, click the pencil/edit icon on
   your specific model (`gemma4:26b-64k`), find the **Terminal** section,
   and select the name of the Open Terminal integration you configured in
   step 7. Without this explicit per-model assignment, the model has no
   execution tool at all — connecting the integration instance-wide and
   disabling Code Interpreter don't automatically wire it to a given model.

   Once both are done, the model gets full shell access (`run_command`,
   `read_file`, `write_file`, `grep_search`, `glob_search`) instead of
   Python-only. You don't lose Python capability by leaving Code
   Interpreter off — Open Terminal's image already includes Python 3.12,
   reachable via `run_command` the normal way.

   (Turn on **Builtin Tools** in the Default Model Metadata screen if you
   also want the model to use Open WebUI's own tools — Memory, Notes, etc.
   — alongside Open Terminal; that one isn't exclusive with anything.)

   (Workspace → Models is for optional named *presets* — a wrapper with its
   own system prompt/bound tools sitting on top of a base model, useful if
   you want multiple named personas later. It's normal for it to be empty
   at this point; it does not list your raw Ollama models automatically,
   which is what's happening if you check there and see nothing even
   though the model works fine in chat.)

9. **Start a chat.** Ask it to look at files in the workspace, run analysis,
   generate a chart — it should call Open Terminal's tools autonomously,
   and any generated images/HTML/diagrams render right in the conversation.

## Adding compiler toolchains (C, Java, etc.)

The official Open Terminal image ships Python and general build tools, but
not necessarily a C compiler or a JDK — check what's actually there before
assuming either way:
```bash
docker compose exec open-terminal sh -c 'which gcc make javac java; cat /etc/os-release | head -3'
```

**Quick/ephemeral option:** since `open-terminal` currently has outbound
network access (the tradeoff described in "Restricting network access"),
the model can just `apt-get install -y build-essential default-jdk` itself
mid-session if asked. This works immediately but disappears the next time
the container is recreated — fine for a one-off, not for regular use.

**Persistent option (recommended if you'll use this regularly):** this
project includes `open-terminal/Dockerfile`, which layers `build-essential`
(gcc/g++/make) and `default-jdk` (javac/java) on top of the official image.
`docker-compose.yml` is already set to build it instead of pulling the
image directly. Before building, verify one assumption in the Dockerfile —
it guesses the base image's non-root username as `user` (matching the
`/home/user` path this project mounts `./workspace` into), but confirm it:
```bash
docker inspect --format='{{.Config.User}}' ghcr.io/open-webui/open-terminal:latest
```
If that reports something other than `user` (or nothing, meaning the image
runs as root by default), edit the last line of `open-terminal/Dockerfile`
to match, or remove that `USER` line entirely if it should stay root.

Then build and verify:
```bash
docker compose up -d --build open-terminal
docker compose exec open-terminal sh -c 'gcc --version && javac -version'
```

From there it's a normal ask in chat — e.g. "write a C program that
computes the first 20 Fibonacci numbers, compile it with gcc, and run it"
— and Open Terminal's `run_command` tool handles `gcc`/`javac`/`java` the
same way it handles any other shell command.

**Note on image size and rebuild time:** `build-essential` and especially
`default-jdk` add a few hundred MB and noticeably increase how long
`docker compose build` takes. If you only need one of C or Java, drop the
other package from the Dockerfile to keep the image leaner.

## Web search

This stack includes a self-hosted **SearXNG** metasearch container, so the
model can search the live web without any query going through a single
tracked provider or requiring an API key. `docker-compose.yml` already
wires the connection (`ENABLE_RAG_WEB_SEARCH`, `RAG_WEB_SEARCH_ENGINE`,
`SEARXNG_QUERY_URL`) — two things are still needed before it actually works.

**1. Finish SearXNG's one-time config.** Its `settings.yml` is
auto-generated on first launch and defaults to HTML-only output; Open WebUI
needs JSON:
```bash
docker compose up -d searxng
sleep 5   # let it generate ./searxng/settings.yml
```
Edit `./searxng/settings.yml`, find the `formats:` line under `search:`,
and add `json`:
```yaml
search:
  formats:
    - html
    - json
```
Then restart it:
```bash
docker compose restart searxng
```
Verify it's actually returning JSON before going near Open WebUI. SearXNG
isn't exposed to the host in this compose file — only reachable from
`open-webui` over the internal `agent-net` network — so test it from
inside that container rather than directly from your Mac:
```bash
docker compose exec open-webui curl "http://searxng:8080/search?q=test&format=json"
```
(If you'd rather test directly from your Mac, you can temporarily add a
`ports:` entry like `"8080:8080"` under the `searxng` service in
`docker-compose.yml`, run `docker compose up -d searxng` to apply it, then
`curl "http://localhost:8080/search?q=test&format=json"` — just remember
to remove that mapping afterward if you don't want SearXNG reachable from
your LAN.)

**2. Enable Web Search as a model capability — same two-layer pattern as
Open Terminal.** The instance-wide connection being configured is
necessary but not sufficient, same lesson as before:
- **Admin Settings → Settings → Web Search**: confirm it shows enabled,
  engine `searxng`, and the query URL pointing at
  `http://searxng:8080/search?q=<query>`.
- **Admin Settings → Settings → Models → [pencil icon on your model] →**
  make sure **Web Search** is checked both as a capability and under
  **Default Features** (or toggle it on per-chat via the `+` icon in the
  chat input bar — Web Search has a per-chat toggle, unlike Open Terminal).

Web Search doesn't conflict with Open Terminal or Code Interpreter — it's
a separate tool family, so nothing you set up earlier needs to change.

**3. Context window matters here too.** Web pages often run 4,000–8,000+
tokens; with a small `num_ctx` most of what's fetched gets truncated before
the model ever sees it. The `64k` default from setup step 2 is comfortably
enough; don't go back down to anything under ~16k if you plan to use web
search regularly.

Test with something time-sensitive your model couldn't know from training
(e.g. "what's today's date" or recent news) — if it searches and cites a
source, it's working end to end.

## A note on model capability

Open WebUI's own docs are direct about this: driving Open Terminal well
needs a model that sustains multi-turn tool calling reliably — call a tool,
read the result, decide the next step, repeat, often for many turns in a
row. Frontier cloud models handle this comfortably. Local 27B-class models
can do it, but are more likely to lose the thread on longer chains, retry
the same failing command, or need you to nudge them back on track mid-task.
If you find it flaky:
- Try a coding-oriented model (Qwen2.5-Coder or similar) rather than a
  general-purpose one — tool-calling reliability varies a lot by model.
- Keep tasks scoped (one file, one clear question) rather than open-ended
  multi-file explorations, especially at first.
- Increase `num_ctx` further if conversations get long and the model seems
  to "forget" earlier steps.

## Auto-start at login

Two mechanisms combine to make this reliable, since they cover different
failure modes.

**1. Docker's own restart policy handles the common case.** This project's
`docker-compose.yml` already sets `restart: unless-stopped` on both
services. Combined with **Docker Desktop → Settings → General → "Start
Docker Desktop when you sign in to your computer"**, this means: if the
containers were running when you last shut down or logged out, Docker's
daemon automatically restarts them the moment it comes back up after login
— no extra scripting needed for that case.

**2. This does *not* cover** containers that were removed (you ran
`docker compose down`, not just a stop/reboot), a fresh machine, or a
compose file you've since edited — in those cases nothing exists yet for
the restart policy to apply to. Docker Desktop has no built-in "run this
compose command at launch" feature, so this needs a small `launchd`
LaunchAgent that explicitly runs `docker compose up -d` after login. This
repo includes one, in `scripts/start-agent-stack.sh` and
`launchagent/com.local-agent-webui.autostart.plist`.

**Setup:**

1. Edit `scripts/start-agent-stack.sh` if you saved this project somewhere
   other than `~/local-agent-webui` — update `PROJECT_DIR` at the top.
2. Make the script executable:
   ```bash
   chmod +x scripts/start-agent-stack.sh
   ```
3. Edit `launchagent/com.local-agent-webui.autostart.plist` and replace
   both instances of `YOUR_USERNAME` with your actual macOS username
   (it needs absolute paths — `~` doesn't expand inside a plist).
4. Copy the plist into place and load it:
   ```bash
   cp launchagent/com.local-agent-webui.autostart.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local-agent-webui.autostart.plist
   ```
   (On older macOS versions where `bootstrap` isn't available, use
   `launchctl load ~/Library/LaunchAgents/com.local-agent-webui.autostart.plist`
   instead.)
5. Test it without rebooting:
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.local-agent-webui.autostart
   tail -f ~/Library/Logs/local-agent-webui.log
   ```
   You should see it wait for Docker, then run `docker compose up -d`.

The script polls for the Docker daemon to actually be ready (up to ~3
minutes) before running `docker compose up -d`, since Docker Desktop takes
a while to bring its VM up after login — a bare `RunAtLoad` script without
this wait would usually fail because Docker isn't listening yet. It's also
safe to trigger repeatedly: `docker compose up -d` just leaves already-
running containers alone.

**To remove it later:**
```bash
launchctl bootout gui/$(id -u)/com.local-agent-webui.autostart
rm ~/Library/LaunchAgents/com.local-agent-webui.autostart.plist
```

## Faster local inference (large-unified-memory Macs)

If responses feel slow on a machine with plenty of unified memory to spare
(e.g. an M-series Mac Studio with 64GB+), the bottleneck is usually compute
per token, not memory capacity — so the highest-leverage changes are about
reducing active compute per token, not freeing up RAM.

**1. This project already defaults to the MoE variant.** `gemma4:26b`
(from setup step 2) only activates ~4B parameters per token despite 26B
total — noticeably faster generation than the dense `31b` model, while
keeping tool-calling support (native across the whole Gemma 4 family). If
you want to compare against the dense model for quality on hard reasoning
tasks, you can pull it side by side without disturbing the default:
```bash
ollama pull gemma4:31b
ollama run gemma4:31b
>>> /set parameter num_ctx 65536
>>> /save gemma4:31b-64k
>>> /bye
```
Both tagged variants can coexist; pick per-task in Open WebUI's model
selector.

**2. Turn on KV-cache quantization and flash attention.** Both speed up
long-context decoding with minimal quality loss. How you set this
persistently depends on how Ollama is running:

- **If you start `ollama serve` manually in a terminal**, add the variables
  to your shell profile — no `launchctl` needed, since the process just
  inherits your shell's environment:
  ```bash
  echo 'export OLLAMA_FLASH_ATTENTION=1' >> ~/.zshrc
  echo 'export OLLAMA_KV_CACHE_TYPE=q4_0' >> ~/.zshrc
  source ~/.zshrc
  ```

- **If Ollama runs as a background service** (`brew services start ollama`,
  auto-starting at login), your shell profile won't reach it — it's
  launched by `launchd`, not your shell. Add the variables to the service's
  plist instead:
  ```bash
  ls -la ~/Library/LaunchAgents/ | grep ollama
  ```
  Edit that plist (typically
  `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist`) and add:
  ```xml
  <key>EnvironmentVariables</key>
  <dict>
      <key>OLLAMA_FLASH_ATTENTION</key>
      <string>1</string>
      <key>OLLAMA_KV_CACHE_TYPE</key>
      <string>q4_0</string>
  </dict>
  ```
  then apply it:
  ```bash
  brew services restart ollama
  ```

  Plain `launchctl setenv OLLAMA_FLASH_ATTENTION 1` works too, but only for
  the current login session — it's wiped on reboot/logout, so it's a good
  way to test the settings before committing to one of the persistent
  options above, not a long-term fix on its own.

  Either way, verify the settings actually took effect with
  `curl -s http://localhost:11434/api/ps` or by checking `ollama serve`'s
  startup log, which typically prints the active flash-attention/KV-cache
  config on boot.

**3. On context size — this project deliberately uses 64k, not less.**
Normally a larger `num_ctx` costs real latency on every turn, and the
generic advice is to size it to what you actually need. Here, `64k` was
chosen on purpose for reasons beyond just tool-calling headroom, so it's
not a knob to reflexively turn down for speed the way it might be
elsewhere. If a given task is latency-sensitive and doesn't need that much
headroom, create an additional smaller-context tagged variant
(`gemma4:26b-16k`, following the same `/save` pattern as setup step 2) and
pick it per-task in Open WebUI's model selector, rather than changing the
default.

**Worth testing rather than assuming:** MoE models trade a bit of raw
capability for speed. If `gemma4:26b-64k` feels noticeably worse than
`gemma4:31b-64k` on your actual tasks — especially longer agentic chains —
the dense model may still be the better choice despite being slower. Try
both on a couple of representative tasks before committing to one.

## Alternative: MLX backend instead of Ollama

Ollama runs on llama.cpp/GGUF under the hood; **MLX** is Apple's own
array framework built specifically for unified memory on Apple Silicon,
and generally gets meaningfully better throughput on the same hardware —
community benchmarks on Gemma 4 specifically back this up, though as with
any vendor/community numbers, worth confirming on your own machine rather
than trusting the headline figure.

**This section is opt-in and unverified against this project's specific
tool-calling setup** — test it standalone before touching Open WebUI's
configuration. Given how much back-and-forth it took to get Open
Terminal/Code Interpreter/web search all correctly wired to the Ollama
backend earlier in this README, don't assume MLX's tool-calling support
transfers cleanly without checking first.

**Recommended model: `mlx-community/gemma-4-26b-a4b-it-4bit`, not the
`31b` dense variant.** Both memory footprint and speed favor the MoE
model here — memory footprint tracks *total* parameters, not active ones,
and the 26B-A4B's 26B total is smaller than the 31B dense model's 31B
total (roughly 18GB vs 20GB at 4-bit), on top of the MoE's inherent speed
advantage from only computing through ~4B active parameters per token.
With 128GB of unified memory neither number is tight for you — the real
benefit of the smaller footprint is more headroom left over for KV cache
at long context.

**1. Install and test tool calling before anything else.** Use Homebrew,
not pip — `mlx-lm` has an official formula, so this avoids needing
`pip install --break-system-packages` (which overrides Python's own
safety check against modifying the system Python install) and keeps
installation consistent with how Ollama itself is already installed:
```bash
brew install mlx-lm
mlx_lm.server --model mlx-community/gemma-4-26b-a4b-it-4bit --port 8081
```
In another terminal, the same kind of check used earlier for Ollama —
confirm you get a `tool_calls` block back, not just plain text or an error:
```bash
curl http://localhost:8081/v1/chat/completions -d '{
  "model": "mlx-community/gemma-4-26b-a4b-it-4bit",
  "messages": [{"role":"user","content":"What is the weather in Paris?"}],
  "tools": [{"type":"function","function":{"name":"get_weather","description":"Get weather for a location","parameters":{"type":"object","properties":{"location":{"type":"string"}},"required":["location"]}}}]
}'
```
Double-check the exact model repo name on Hugging Face
(`mlx-community/gemma-4-26b-a4b-it-4bit`) before relying on it — naming
conventions across quantized community uploads aren't perfectly uniform.
(If you'd rather use pip for some reason — e.g. needing a newer release
than Homebrew's formula currently has — `pip install mlx-lm
--break-system-packages` still works as a fallback.)

**2. If tool calling checks out, add it to Open WebUI as a new connection**
— don't replace the working Ollama connection outright; add MLX alongside
it so you can compare and fall back easily:
- **Admin Settings → Connections → Add Connection**, type **OpenAI**
  (not Ollama — `mlx_lm.server` speaks OpenAI format, not Ollama's API)
- Base URL: `http://host.docker.internal:8081/v1`
- API key: anything non-empty, `mlx_lm.server` doesn't check it
- The `gemma-4-26b-a4b-it-4bit` model should then show up in the chat
  model picker alongside your Ollama models

**3. Re-verify Open Terminal, Web Search, and Code Interpreter capability
settings against this new model** — per-model capability/attachment
settings (the Terminal section, Web Search toggle) are per *model entry*,
not global, so switching backend doesn't automatically carry them over to
the newly added MLX model. Repeat setup steps 7–9 for it.

**4. Set Max Tokens explicitly — `mlx_lm.server` defaults to only 512
tokens per response, and Open WebUI's OpenAI-connection type doesn't
override that automatically.** This is a confirmed, real gotcha, not a
theoretical one: `mlx_lm.server`'s own docs state `max_tokens` defaults to
512 unless the client sets it, and testing directly against the server
(bypassing Open WebUI) with `max_tokens: 4096` produced a complete,
well-structured ~2,000-token response with `finish_reason: "stop"` —
proving the model itself is fully capable, and that anything shorter
through Open WebUI is being cut off by the unset default, not by a real
quality gap between Ollama and MLX. Fix: **Admin Settings → Settings →
Models → [pencil icon on the MLX model] → Advanced Parameters → Max
Tokens**, set to `8192`.

**Confirmed end to end:** with Max Tokens set to `8192`, MLX output
matches Ollama's descriptiveness/verbosity while still running faster —
there is no real quality tradeoff between the two backends for this model;
the entire gap was this one unset parameter. `8192` is a comfortable
number given the 64k context budget from setup step 2; go higher only if
you find the model still getting cut off on especially long tasks.

**Persisting `mlx_lm.server` across reboots.** This project includes a
ready-made LaunchAgent for this, in `scripts/start-mlx-server.sh` and
`launchagent/com.local-agent-webui.mlx-server.plist` — same pattern as the
Docker autostart setup, with one difference: since `mlx_lm.server` has no
external dependency to wait on (unlike the Docker script, which waits for
the Docker daemon), this one sets `KeepAlive` true in the plist so
`launchd` restarts the server automatically if it ever exits or crashes,
rather than only running once at login.

**Setup:**

1. Edit `scripts/start-mlx-server.sh` if your model/port choice differs
   from the defaults (`mlx-community/gemma-4-26b-a4b-it-4bit` on port
   `8081`), and confirm `MLX_LM_BIN` matches your Homebrew install
   location — `/opt/homebrew/bin/mlx_lm.server` on Apple Silicon,
   `/usr/local/bin/mlx_lm.server` on Intel (check with
   `which mlx_lm.server`).
2. Make it executable:
   ```bash
   chmod +x scripts/start-mlx-server.sh
   ```
3. Edit `launchagent/com.local-agent-webui.mlx-server.plist` and replace
   both instances of `YOUR_USERNAME` with your actual macOS username.
4. Copy the plist into place and load it:
   ```bash
   cp launchagent/com.local-agent-webui.mlx-server.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local-agent-webui.mlx-server.plist
   ```
   (On older macOS versions without `bootstrap`, use `launchctl load
   ~/Library/LaunchAgents/com.local-agent-webui.mlx-server.plist` instead.)
5. Test without rebooting:
   ```bash
   launchctl kickstart -k gui/$(id -u)/com.local-agent-webui.mlx-server
   tail -f ~/Library/Logs/local-agent-mlx-server.log
   curl http://localhost:8081/v1/models
   ```

**To remove it later:**
```bash
launchctl bootout gui/$(id -u)/com.local-agent-webui.mlx-server
rm ~/Library/LaunchAgents/com.local-agent-webui.mlx-server.plist
```

If you'd rather not persist it at login at all — e.g. you only spin up MLX
occasionally to compare against Ollama — skip this and just run
`mlx_lm.server` manually in a terminal when you want it.

## Restricting network access

By default, `open-terminal` sits on the same Docker network as `open-webui`
(`agent-net`), which means it can also reach the open internet — Docker
doesn't distinguish "reachable by my sibling container" from "reachable by
anything" without extra firewall rules. This matters if `./workspace` will
ever contain files from someone you don't fully trust (a file could contain
a prompt-injection attempt aimed at getting the model to exfiltrate data).

To lock this down further:
- Add an egress-restricting sidecar (e.g. a `squid` or `mitmproxy` container
  configured to only allow the `open-webui` hostname/IP) and route
  `open-terminal`'s traffic through it.
- Or use `iptables` rules baked into a custom `open-terminal` image build to
  restrict outbound connections to just the `agent-net` subnet.

This is genuinely extra setup — reasonable to skip for a single-user setup
on your own trusted files, worth doing if you'll feed it things from others.

## Persistence across restarts and rebuilds

The two containers behave differently here, and it matters for what you can
rely on staying put:

- **`open-webui`'s settings persist.** Admin settings, the Code Interpreter
  capability toggle, connections, users, and chat history all live in the
  `open-webui-data` named volume (`/app/backend/data`). This survives
  `docker compose down` / `up`, restarts, rebuilds (`--build`), and reboots.
  It's only wiped by explicitly removing volumes:
  ```bash
  docker compose down -v   # -v removes volumes — avoid unless you mean it
  ```
  Confirm it exists any time with `docker volume ls | grep open-webui-data`.

- **`open-terminal`'s state does *not* persist**, by design (see Safety
  notes below on treating it as disposable). Only `./workspace` — bind-
  mounted from your Mac — survives container recreation. Anything else
  (packages installed mid-session, temp files elsewhere in the container,
  shell state) is gone the next time the container is recreated
  (`docker compose down && up`, or a rebuild).

**Renaming or relocating the project directory after the fact is a real
trap, now fixed.** `docker-compose.yml` pins `name: local-agent-webui` at
the top level. Without this, Compose derives its project name from
whatever folder you happen to run it from — so renaming the project
directory later doesn't migrate anything, it silently starts managing a
*second*, disconnected set of containers and volumes tied to the new name,
while the original containers (still tagged to the old folder name) keep
running untouched under `restart: unless-stopped`. Concretely, this means:
if you ever renamed this project's folder, your original containers didn't
go anywhere — they're still running, still bind-mounting `./workspace` and
`./searxng` at their *original* path, and Docker will keep silently
re-creating that original path (even after deleting it) every time those
containers restart at login, since Docker auto-creates a missing bind-mount
source directory rather than failing. If you're hitting this, the fix is a
one-time migration: tear down the old project by its original name
(`docker compose -p <old-project-name> down`, without `-v`, to keep the
volume), copy its named volume's data into the new pinned volume name via
a throwaway container, then bring the stack up fresh from the correct
directory. This preserves your Open WebUI configuration rather than losing
it. With the project name now pinned, this specific trap can't recur even
if you rename the folder again later.

## Safety notes

- Treat `open-terminal`'s filesystem as disposable. Its home directory is
  your `./workspace` folder, so anything it does there persists — rebuild
  the container (`docker compose down && docker compose up -d`) between
  unrelated tasks if you don't want state (temp files, installed packages)
  carrying over.
- Don't mount the Docker socket into `open-terminal` unless you fully trust
  everything that will ever run there — it's effectively root on your Mac's
  Docker daemon (host-level access, not just this container).
- `mem_limit` / `cpus` on `open-terminal` cap runaway resource use.
- `WEBUI_AUTH=True` requires a login for the web UI — keep this on even on
  a single-user machine, since `open-webui` is reachable from anything on
  your LAN unless you also restrict port 3000.

## Troubleshooting

- **Model only ever writes Python, refuses/can't run shell tools like
  `awk`/`sed`, or reports its execution tool as unavailable**: two things
  are needed, not just one. (1) Code Interpreter and Open Terminal are
  mutually exclusive — turn Code Interpreter OFF at **Admin Settings →
  Settings → Models → ⚙️ → Default Model Metadata**. (2) Separately, the
  model needs Open Terminal explicitly attached: **Admin Settings →
  Settings → Models → [pencil icon on your model] → Terminal section →
  select your Open Terminal integration by name**. Connecting the
  integration instance-wide and disabling Code Interpreter alone are not
  enough — without this per-model attachment the model has no execution
  tool at all (which surfaces as an error like `execute_code` not found).
  If you change either setting mid-conversation, start a new chat —
  a chat's available tools can stay stale from when it began.
- **"Ollama connection failed" in open-webui**: confirm `ollama serve` is
  running on the Mac and reachable — test with
  `curl http://localhost:11434/api/tags` from the host. If open-webui still
  can't reach it, double check `extra_hosts` took effect:
  `docker compose exec open-webui curl http://host.docker.internal:11434/api/tags`.
- **Workspace → Models is empty**: this is expected, not a bug. That page
  only lists custom presets you've created there — it does not
  automatically show raw base models pulled from a connection (like your
  Ollama models). Those only appear in the chat model picker. Capabilities
  like Code Interpreter are set via **Admin Settings → Settings → Models →
  ⚙️ → Default Model Metadata** instead (see step 8 above), which applies
  to base models directly.
- **Tool calls silently do nothing**: almost always the context-window
  issue from step 2 — confirm you're using the `-64k` tagged model
  (`gemma4:26b-64k`), not the base `gemma4:26b`, in the chat model picker.
- **Open Terminal shows as disconnected**: check
  `docker compose logs open-terminal` for the API key it generated/expects,
  and confirm it matches your `.env`.
