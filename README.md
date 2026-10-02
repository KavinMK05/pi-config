# pi-config

My [pi](https://pi.dev) coding-agent configuration, published so I can replicate the exact
setup on another machine (and so an agent can read this file and do the replication).

The priority of this repo is the **exact extension/package setup**: which npm packages load,
which built-ins are disabled, and the five custom extensions that wire everything together.

## What's here

```
agent/
  settings.json          ->  ~/.pi/agent/settings.json
  pi-plan-mode.json      ->  ~/.pi/agent/pi-plan-mode.json
  extensions/            ->  ~/.pi/agent/extensions/
    herdr-agent-state.ts         (installed/managed by herdr)
    orca-agent-status.ts         (managed by Orca)
    orca-prefill.ts              (managed by Orca)
    orca-titlebar-spinner.ts     (managed by Orca)
    web-tools-fallback.ts        (custom — see below)
  npm/
    package.json         ->  ~/.pi/agent/npm/package.json
    package-lock.json    ->  ~/.pi/agent/npm/package-lock.json   (pins exact versions)
config/
  mcp.json               ->  ~/.config/mcp/mcp.json              (shared MCP servers)
skills/
  amazon-flipkart-scraping/  ->  ~/.agents/skills/               (custom, vendored)
  .skill-lock.json           ->  ~/.agents/.skill-lock.json      (sources of third-party skills)
install.ps1                  ->  convenience bootstrap for all of the above
```

## The setup in one picture

**8 npm packages** (declared in `settings.json`, pinned in `package-lock.json`):

| Package | Role | Notes |
|---|---|---|
| `pi-searxng-search` | `web_search` (primary) | `extensions: []` — no auto-load |
| `pi-smart-fetch` | `web_fetch` + `batch_web_fetch` (fallback) | `extensions: []` — no auto-load |
| `donsetch` | `web_fetch` (primary), `web_crawl`, `web_screenshot` | `extensions: []` — no auto-load |
| `@tintinweb/pi-subagents` | `Agent`, `SubagentWorkflow` | auto-load |
| `@juicesharp/rpiv-todo` | `todo` tool | auto-load |
| `pi-mcp-adapter` | MCP gateway | auto-load |
| `@juicesharp/rpiv-ask-user-question` | `ask_user_question` tool | auto-load |
| `@plannotator/pi-extension` | Plannotator plan/code review | auto-load |

**Built-in disabled:** `-builtin:mcp` (the `pi-mcp-adapter` package replaces it).

### Why the three web packages have `extensions: []`

`donsetch`, `pi-searxng-search`, and `pi-smart-fetch` all register the same tool names
(`web_search`, `web_fetch`). Pi's tool registry is a plain `Map`, so whichever extension loads
last silently overwrites the others. `agent/extensions/web-tools-fallback.ts` imports all three
factories and re-registers their tools under disjoint names:

```
web_search               -> searxng      (primary)
web_search_fallback      -> donsetch     (fallback)
web_fetch                -> donsetch     (primary)
web_fetch_fallback       -> smart-fetch  (fallback)
batch_web_fetch_fallback -> smart-fetch
web_crawl, web_screenshot -> donsetch    (unchanged)
```

Because that wrapper is the **only** thing registering these tools, the three packages must keep
`"extensions": []` in `settings.json`. Dropping a filter makes the package double-register under
its original name and shadow the wrapper.

`web-tools-fallback.ts` resolves its imports through `~/.pi/agent/node_modules`, which is a
junction to `~/.pi/agent/npm/node_modules`. The install script creates it.

## Replicate on a new machine

### Option A — run the script

```powershell
git clone https://github.com/KavinMK05/pi-config
cd pi-config
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

### Option B — do it by hand

1. **Extensions** — copy `agent/extensions/*.ts` to `~/.pi/agent/extensions/`.
2. **Settings** — copy `agent/settings.json` to `~/.pi/agent/settings.json`
   (back up any existing file first), and `agent/pi-plan-mode.json` next to it.
3. **Packages** —
   ```bash
   mkdir -p ~/.pi/agent/npm
   cp agent/npm/package.json agent/npm/package-lock.json ~/.pi/agent/npm/
   cd ~/.pi/agent/npm && npm ci
   ```
   Then expose the module dir so the wrapper extension can import them:
   Windows: `cmd /c mklink /J %USERPROFILE%\.pi\agent\node_modules %USERPROFILE%\.pi\agent\npm\node_modules`

   (If npm isn't available, copy the settings first and run `pi update --extensions`.)
4. **Skills** — copy the vendored custom skill, then reinstall the third-party ones:
   ```bash
   mkdir -p ~/.agents/skills
   cp -R skills/amazon-flipkart-scraping ~/.agents/skills/
   npx skills add vercel-labs/skills            # find-skills
   npx skills add mattpocock/skills             # grill-me, teach
   npx skills add leonxlnx/taste-skill          # design-taste-frontend
   npx skills add coreyhaines31/marketingskills # seo-audit
   npx skills add jakubkrehel/skills            # better-ui
   npx skills add emilkowalski/skills           # emil-design-eng
   ```
   `skills/.skill-lock.json` records the exact source repos and folder hashes, and can be copied
   to `~/.agents/.skill-lock.json` to preserve provenance.
5. **MCP** — copy `config/mcp.json` to `~/.config/mcp/mcp.json`. The `notion` server uses OAuth,
   so you'll authenticate on first use.

## Deliberately excluded

| File | Why |
|---|---|
| `auth.json` | OAuth/API credentials (OpenAI, Codex, opencode). Run `/login` or set provider env vars. |
| `models.json` | Contains a personal email in a model name and localhost-only providers. Re-add per machine. |
| `mcp.json.prism-backup` | Local `http://127.0.0.1:11434/mcp/pi` server with a placeholder bearer token. |
| `sessions/` | Conversation history. |
| `mcp-cache.json`, `mcp-onboarding.json` | Regenerated runtime caches. |
| `trust.json` | Machine-specific trusted project paths. |
| `deviceId` (in settings.json) | Unique per machine — stripped from the tracked copy. |
| `bin/` (`fd.exe`, `rg.exe`) | Platform binaries; install separately. |

## Notes

- **Orca / herdr extensions are externally managed.** Their headers say so; updating or
  reinstalling those tools may overwrite the copies here. Re-copy from this repo afterwards.
- **Platform paths.** `settings.json` uses no absolute paths, so it's portable as-is.
- **Auth is per-machine and intentional.** Nothing here will log you in.
