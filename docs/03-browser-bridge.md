# 03 — Browser automation after migration

This is the part that silently breaks, and the part no other migration guide covers.

## Why it breaks

Claude Desktop's browser automation has two moving parts:

1. a **Chrome extension** (the official *Claude for Chrome*, extension id
   `fcoeoabgfenejglbffodgkkbkcdhcgfn`), and
2. a **pairing** between that extension and the Desktop app, recorded in the app config
   (`preferences.chromeExtension`).

Both are **account-scoped**. After switching accounts:

- the pairing is gone (the new account's config has an empty `chromeExtension` object), and
- re-pairing fails anyway, because **the official extension requires a paid plan**. Logging in with
  an account that has no plan shows: *"Claude in Chrome requires a paid plan."*

So on a gateway / free account, the official route is a dead end. You need a different bridge.

## The alternative: mcp-chrome-bridge

[`mcp-chrome-bridge`](https://www.npmjs.com/package/mcp-chrome-bridge) is a Chrome extension plus a
local MCP server. The extension drives **your own Chrome** (with all your existing logins), talks to
a local native-messaging host, and exposes a set of `chrome_*` tools over MCP. **No Anthropic
account is involved.**

```bash
npm install -g mcp-chrome-bridge
mcp-chrome-bridge register --detect     # registers the native-messaging host for Chrome
mcp-chrome-bridge doctor                # should print all-OK
```

Then load the extension in Chrome (`chrome://extensions` → Developer mode → Load unpacked) from the
extension folder shipped with the package/repo, and click **Connect** in its popup. `doctor` should
report the port (`127.0.0.1:12306`) as listening.

Finally register the MCP server with Claude:

```bash
claude mcp add chrome-mcp -- mcp-chrome-stdio
# or add to ~/.claude.json:
#   "chrome-mcp": { "type": "stdio", "command": "mcp-chrome-stdio" }
```

Verify: `claude mcp list` should show `chrome-mcp ... ✔ Connected`.

> ⚠️ Do not name the MCP server `claude-in-chrome`. Claude Code treats that name as **reserved** and
> silently refuses to load it.

## Five problems you will hit, and their fixes

These are all real; each one makes the bridge look "broken" in a different way.

### 1. It only serves one session at a time

The bridge's HTTP server calls `getMcpServer().connect(transport)` on a **singleton** `Server`, and
an MCP `Server` can only be connected once. The second client — or any client after an unclean
disconnect — gets:

```
Streamable HTTP error: 500 {"message":"Already connected to a transport.
Call close() before connecting to a new transport, or use a separate Protocol instance per connection."}
```

**Fix:** patch `node_modules/mcp-chrome-bridge/dist/mcp/mcp-server.js` so `getMcpServer()` returns a
**new** `Server` on every call instead of caching one. (`scripts/patch-chrome-bridge.md` describes
the patch; it is three lines.) A `npm update` will overwrite it — re-apply after upgrades.

### 2. One tool hangs forever

`chrome_read_page` (which returns an accessibility tree via a page-injected helper) never returns on
some setups. Because it is also the source of the `ref` values that `chrome_click_element` and
`chrome_computer` accept, its failure removes the whole ref-based workflow.

**Fix:** remove it from the tool list and short-circuit calls to it, then use **CSS selectors**
instead of refs. `chrome_click_element` and `chrome_fill_or_select` both accept a `selector`, so the
workflow still works — you just locate elements with a selector (e.g. by running a small script with
`chrome_javascript`) instead of a ref.

Two gotchas when you do this:

- `chrome_javascript` requires an **explicit `return`** — an expression alone returns `undefined`.
  Its result is wrapped: `{"success":true,"tabId":…,"result":"…"}`.
- `chrome_computer` with `action:"left_click"` and a **`selector`** frequently fails with
  *"Element not found"*. It reliably accepts `ref`/`coordinates`. For selector-based clicking, use
  `chrome_click_element`.

### 3. Every operation steals focus

By default the bridge activates the tab and brings the window forward, so the user cannot keep using
their browser while automation runs.

**Fix:** pass `background: true`. It is supported by `chrome_navigate`, `chrome_computer`,
`chrome_screenshot`, `chrome_get_web_content` and `chrome_console`. Also **never call
`chrome_switch_tab`** — activating a tab is its whole job.

Verified: with `background: true`, navigation and clicks complete on a background tab **without the
active tab changing**.

### 4. Clicks are trivially detectable as bots

A bare click (`chrome_click_element`, or `chrome_computer` with `left_click`) dispatches only
`mousedown, mouseup, click`. A real user always moves the mouse first, so the absence of
`mousemove` / `mouseover` is a bot fingerprint — and sites with anti-bot defences will notice.

**Fix:** **hover before clicking.** `chrome_computer` with `action:"hover"` dispatches
`mouseover, pointerenter/pointermove, mousemove`. The resulting sequence

```
mouseover, pointermove, mousemove, mousedown, mouseup, click
```

looks like a person. Hover before filling forms too.

### 5. It opens a new browser window every time

`chrome_navigate` takes `newWindow`, and also `width`/`height` — **all three create a new window**.
Automation that navigates repeatedly will bury the user's desktop in windows.

**Fix:** never pass them. Without a `tabId`, `chrome_navigate` opens a **tab in the existing
window**; with a `tabId` it navigates that tab. For "one tab per session" behaviour, remember the
tab id you were given and reuse it: `navigate` replaces the current tab's content, while a
deliberate "open a new tab" action passes no `tabId`.

### 6. Two browser MCP servers registered → your defaults get bypassed

This one only bites *after* you have set the four fixes above up, which makes it easy to miss.

If you register **both** the raw bridge (`chrome-mcp`) and a wrapper that applies defaults
(`chrome-compat`), the agent may call either — and it will happily call the raw one, because that is
where the `chrome_*` names live. Every default is then gone: focus stealing comes back, clicks lose
their `mousemove`, windows start multiplying again.

Observed: after a wrapper was installed, task runs still showed 27 calls to
`mcp__chrome-mcp__chrome_javascript`, 9 to `mcp__chrome-mcp__chrome_navigate` and 7 to
`mcp__chrome-mcp__chrome_click_element` — all raw — while only a handful went through the wrapper.

**Fix:** register **exactly one** browser MCP. Make the wrapper expose the raw `chrome_*` names too
(fetch the upstream tool list and re-expose it), then remove the raw server from the config. Then
whichever name the agent picks, the defaults apply.

Verify by checking what a task actually called — not by reading the config:

```bash
grep -oE 'mcp__[a-zA-Z0-9_-]+__[a-zA-Z0-9_]+' <session>.jsonl | sort | uniq -c | sort -rn | head
```

Every browser call should be under the wrapper's server name.

## Two more small traps

- `chrome_navigate` prepends `www.` to hostnames, which mangles IP addresses
  (`127.0.0.1` → `www.127.0.0.1`). Use `localhost` or a real domain. `file://` URLs are not
  supported at all.
- The extension's popup must show **Service running** and a **Connect/Disconnect** control. If the
  tools are exposed but every call fails, the extension is not connected to the local host — ask the
  user to click Connect, and restart the host process if it was killed.

## Recommended defaults for a task wrapper

If you wrap the bridge (for example to keep existing task prompts working that reference other tool
names), apply these defaults centrally:

| Behaviour | Default |
|---|---|
| `background` | `true` on every supported tool |
| clicking | hover first, then `chrome_click_element` |
| filling | hover first, then `chrome_fill_or_select` |
| new windows | never (`newWindow`/`width`/`height` stripped) |
| current tab | reuse the session's tab for `navigate`; open a new one only on explicit request |
| `chrome_read_page` | removed from the tool list |

### Close the remaining holes with an allowlist

`background: true` only covers the tools that accept it, and it is easy to forget. The durable fix
is to make the wrapper refuse anything it has not verified:

- keep an **allowlist** of tools confirmed not to steal focus, and reject the rest with a message
  listing what is allowed (bookmark UI, history, GIF recorder, userscript injection, … — all
  unverified, all blocked);
- block `chrome_switch_tab` by default — **but not permanently**. Its only job is to activate a tab,
  which is exactly what you want when **the user** needs to look at or interact with a page
  (captcha, payment confirmation, login, "check this before I continue"). Automation never needs it:
  pass `tabId` and the operation happens in the background. So: allowed, documented, and expected to
  be used only for that one purpose.

Verified with a full pass (navigate → read → find → fill → click → screenshot → scroll → JS → text)
on a background tab: **the user's active tab never changed**.

## Verify it end-to-end

Ask the user to open a new session and try:

> Use the browser tools to open `https://example.com` and read me its title.

Then, without any special instruction, check that **their active tab did not change** — that proves
the background default is working.
