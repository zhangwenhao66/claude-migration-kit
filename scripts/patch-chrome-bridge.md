# Patching mcp-chrome-bridge

Two small patches make `mcp-chrome-bridge` usable. Both live in
`node_modules/mcp-chrome-bridge/dist/mcp/`. **`npm update` overwrites them — re-apply after
upgrading.**

Back up before editing:

```bash
B="$(npm root -g)/mcp-chrome-bridge/dist/mcp"
cp "$B/mcp-server.js"        "$B/mcp-server.js.bak"
cp "$B/mcp-server-stdio.js"  "$B/mcp-server-stdio.js.bak"
```

---

## Patch 1 — allow more than one client

**File:** `mcp-server.js`

**Problem:** `getMcpServer()` caches a singleton `Server`, but an MCP `Server` can only be
connected once. The second client — or any client after an unclean disconnect — gets HTTP 500
`"Already connected to a transport"`.

**Fix:** return a fresh `Server` on every call.

Replace the body of `getMcpServer` with:

```js
const getMcpServer = () => {
    const server = new index_js_1.Server({
        name: 'ChromeMcpServer',
        version: '1.0.0',
    }, {
        capabilities: { tools: {} },
    });
    (0, register_tools_1.setupTools)(server);
    return server;
};
```

(keep the `require` lines and the `exports` lines as they are).

---

## Patch 2 — remove the hanging tool

**File:** `mcp-server-stdio.js`

**Problem:** `chrome_read_page` never returns on some setups, and because it is the source of
`ref` values, it takes the ref-based workflow down with it.

**Fix:** drop it from the tool list and short-circuit calls.

The tool list is built in `setupTools`:

```js
// before
server.setRequestHandler(types_js_1.ListToolsRequestSchema, async () => ({ tools: chrome_mcp_shared_1.TOOL_SCHEMAS }));

// after
server.setRequestHandler(types_js_1.ListToolsRequestSchema, async () => ({
    tools: chrome_mcp_shared_1.TOOL_SCHEMAS.filter((t) => t && t.name !== 'chrome_read_page'),
}));
```

And guard the call handler:

```js
const handleToolCall = async (name, args) => {
    if (name === 'chrome_read_page') {
        return { content: [{ type: 'text', text: 'chrome_read_page is unavailable here (it hangs). Use chrome_get_web_content instead.' }], isError: true };
    }
    try {
        ...
```

The same filter is harmless to add in `register-tools.js` (used by the HTTP server) for
consistency.

---

## Verify

```bash
node --check "$B/mcp-server.js" && node --check "$B/mcp-server-stdio.js"

# tool list should no longer contain chrome_read_page
printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
 '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
 | mcp-chrome-stdio 2>/dev/null | grep -o 'chrome_read_page' | head -1
# expected: no output
```

For patch 1, open two clients at once and call a tool from both — both should succeed.
