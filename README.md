# claude-migration-kit

**Claude 账号被封了，但你整套开发环境不用丢。**

[中文](#中文) · [English](#english)

---

## 中文

**Claude 账号被封了，但你整套开发环境不用丢。**

账号被封、停用，或者只是不想续费之后，Claude Desktop 打开是一片空白：没有会话、没有定时任务、
没有记忆。看起来全都完了。

其实没完。你的对话正文、定时任务、技能、记忆、项目文件全都还在磁盘上——只是 Claude Desktop
按账号去读**另一个文件夹**而已。

这个项目是一套**技能 + 脚本**，把旧账号里的所有东西原样搬到新账号（包括通过
[CC Switch](https://github.com/farion1231/cc-switch) 之类的第三方网关账号），让你继续用**完全一样**的
环境：同样的会话、同样的定时任务、同样的技能、同样的记忆、同样的浏览器自动化。

> **反方向也做了一个**：用网关模式跑了一段时间，现在想回到自己的 Anthropic 账号？
> 用 [`claude-restore-kit`](https://github.com/zhangwenhao66/claude-restore-kit)。
> 往回搬不只是把命令反过来跑一遍——目标分区是活的（要按 id 合并任务，不是覆盖），
> 而且机器上还留着网关的环境变量，不清掉的话登录了也照样走网关。

> 在 macOS 上实测跑通。原理与平台无关，但路径在 Linux/Windows 上不同。

### 核心原理

| 层 | 位置 | 按账号隔离？ |
|---|---|---|
| **对话正文**（真内容） | `~/.claude/projects/<路径编码>/<sessionId>.jsonl` | **否**——只按工作目录分 |
| **会话列表元数据**（标题、指针） | `~/Library/Application Support/Claude/claude-code-sessions/<账号UUID>/<组织UUID>/` | **是** |
| **规则 / 记忆 / 技能 / 任务指令** | `~/.claude/` | **否** |
| **项目文件** | 你自己放哪就是哪 | **否** |

App 是靠"扫描当前登录账号对应的那个文件夹"来生成侧边栏的。换账号后那个文件夹是空的，于是界面一片空白
——而几 GB 的对话正文一个字都没少。**把元数据复制进新账号的文件夹，东西就全回来了。** 会话元数据 JSON
里**根本没有任何账号字段**，所以既不用改数据库，也不用转换导出格式。

第二个关键事实：Claude Desktop 支持**第三方部署模式**（`"deploymentMode": "3p"`），走本地网关而不是
Anthropic 登录。3p 模式下 App 用的是**另一个数据目录**（`Claude-3p`）——同样的现象，同样的解法。

### 项目内容

| 文件 | 说明 |
|---|---|
| `SKILL.md` | Claude Code 技能。装好后直接对 Claude 说"把我的旧 Claude 账号迁到这个新账号"，它就带你走完全程。 |
| `scripts/find-partitions.sh` | 只读：找出所有账号分区，并打印**哪些任务是启用的**（这份清单要存好）。 |
| `scripts/migrate.sh` | `check` / `test` / `all`：备份 → 搬会话 → 导入任务（全停用）→ 搬 Cowork。全程只复制。 |
| `scripts/restore-enabled.sh` | 按原样恢复启用状态，**支持分批**，带 `--dry-run`。 |
| `scripts/rollback.sh` | 清单式精确回滚，只删它自己复制过的文件。 |
| `docs/01-data-layout.md` | 数据怎么存的、为什么看起来全没了。 |
| `docs/02-migration.md` | 逐步迁移与验收。 |
| `docs/03-browser-bridge.md` | 迁移后的浏览器自动化——以及它需要的 5 处修复。 |
| `docs/04-pitfalls.md` | 我们踩过的所有坑，让你不用再踩一遍。 |
| `docs/05-verification.md` | 验收清单：怎么确认真的迁好了，含焦点安全检查。 |
| `docs/06-gateway-mode.md` | **gateway/3p 账号专有**：哪些东西不一样，以及只在这种模式下才出现的坑（服务端工具、扩展、模型目录、限流）。 |

安装技能：

```bash
mkdir -p ~/.claude/skills/claude-account-migration
cp SKILL.md ~/.claude/skills/claude-account-migration/SKILL.md
```

（仓库留着别删——技能里会让 Claude 从这个仓库跑脚本。）

### 快速开始

```bash
git clone <本仓库> && cd claude-migration-kit

bash scripts/find-partitions.sh        # 1. 找源/目标分区；把启用清单存好
cp scripts/config.example.sh scripts/config.sh && $EDITOR scripts/config.sh   # 2. 填配置
bash scripts/migrate.sh check          # 3. 只读预检（Claude 开着也能跑）

# 4. 完全退出 Claude Desktop（⌘Q），然后：
bash scripts/migrate.sh test           # 只搬 20 条，重开 Claude 肉眼确认
bash scripts/migrate.sh all            # 全量；任务全部以停用状态导入

# 5. 重开 Claude，然后分批恢复启用状态：
bash scripts/restore-enabled.sh --dry-run
bash scripts/restore-enabled.sh --limit 5
```

两章建议在收尾前读：[docs/03-browser-bridge.md](docs/03-browser-bridge.md)（浏览器自动化）和
[docs/06-gateway-mode.md](docs/06-gateway-mode.md)（如果新账号是 gateway 的）。

### 什么能保住

| 资产 | 保得住？ | 说明 |
|---|---|---|
| 对话正文 | ✅ | 本来就是共享的，App 只差元数据 |
| 会话列表（标题、文件夹分组） | ✅ | 把 `local_*.json` 复制进新分区 |
| 定时任务 / Routine | ✅ | **停用状态**导入；之后分批恢复 |
| 技能、记忆、`CLAUDE.md` | ✅ | 不按账号隔离，什么都不用做 |
| 项目文件与 git | ✅ | 从头到尾没碰 |
| Cowork 会话 + 工作区 | ✅ | 独立分区，同样方法 |
| 浏览器自动化 | ⚠️ | 配对是按账号的；官方扩展要付费 plan → 见 docs/03 |
| 插件 | ❌ | 按账号从市场同步，需重装 |
| 已发布的 Artifact / claude.ai 网页对话 | ❌ | 绑死在旧账号，无法找回 |

### 环境要求

macOS、`bash`、`python3`、Claude Desktop。浏览器桥接另需 Node.js ≥ 18 与 Chrome。

### 参与贡献

如果你踩到了这个项目没提醒的坑——那是最有价值的反馈，见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可

MIT —— 见 [LICENSE](LICENSE)。

---

## English

If your Anthropic account gets banned, suspended, or you simply stop paying, Claude Desktop opens
with an empty sidebar: no sessions, no routines, no memory. It looks like everything is gone.

It isn't. Your transcripts, scheduled tasks, skills, memory and project files are all still on disk.
Claude Desktop just reads a different folder per account.

This kit is a **skill + scripts** that move everything from the old account into a new one —
including a third-party gateway account (e.g. via [CC Switch](https://github.com/farion1231/cc-switch))
— so you keep working in the exact same environment: same sessions, same routines, same skills, same
memory, same browser automation.

> **There is a repo for the other direction.** Been on a gateway for a while and want to move back
> onto a real Anthropic account? Use
> [`claude-restore-kit`](https://github.com/zhangwenhao66/claude-restore-kit). It is not this one run
> backwards: the target partition is live (tasks are merged by id, not overwritten), and the machine
> keeps gateway environment variables that make a fresh login still route to the gateway.

> Battle-tested on macOS. The technique is platform-independent; paths differ on Linux/Windows.

### The core insight

| Layer | Location | Scoped by account? |
|---|---|---|
| **Conversation transcripts** (the real content) | `~/.claude/projects/<path-encoded>/<sessionId>.jsonl` | **No** — only by working directory |
| **Session list metadata** (titles, pointers) | `~/Library/Application Support/Claude/claude-code-sessions/<accountUUID>/<orgUUID>/` | **Yes** |
| **Rules / memory / skills / task instructions** | `~/.claude/` | **No** |
| **Project files** | wherever you keep them | **No** |

The App builds the sidebar by scanning the folder for the account you are logged into. After
switching, that folder is empty — while gigabytes of transcripts sit untouched. **Copy the metadata
into the new account's folder and everything is back.** The session metadata JSON contains no account
fields at all, so there is no database to patch and no export format to convert.

A second key fact: Claude Desktop supports a **third-party deployment mode**
(`"deploymentMode": "3p"`) that routes traffic through a local gateway instead of Anthropic's login.
In 3p mode the app uses a **separate data directory** (`Claude-3p`) — same problem, same fix.

### What's in here

| File | What it is |
|---|---|
| `SKILL.md` | A Claude Code skill. Install it and just ask Claude *"migrate my old Claude account into this one"*. |
| `scripts/find-partitions.sh` | Read-only: finds every account partition, and prints **which tasks were enabled** (save that list). |
| `scripts/migrate.sh` | `check` / `test` / `all` — backup → copy sessions → import tasks (paused) → copy Cowork. Copy-only. |
| `scripts/restore-enabled.sh` | Re-enable exactly the tasks that were enabled before — **in batches**, with `--dry-run`. |
| `scripts/rollback.sh` | Precise, manifest-based undo. Only deletes what it copied. |
| `docs/01-data-layout.md` | How the storage works and why it looks gone. |
| `docs/02-migration.md` | Step-by-step migration and verification. |
| `docs/03-browser-bridge.md` | Browser automation after migration — and the five fixes it needs. |
| `docs/04-pitfalls.md` | Everything that bit us, so it doesn't bite you. |
| `docs/05-verification.md` | The checklist: how to actually confirm it worked, including the focus check. |
| `docs/06-gateway-mode.md` | **Gateway/3p accounts**: what is different, and the traps that only appear there (server-side tools, the extension, model catalog, rate limits). |

Install the skill:

```bash
mkdir -p ~/.claude/skills/claude-account-migration
cp SKILL.md ~/.claude/skills/claude-account-migration/SKILL.md
```

(Keep the repo around — the skill tells Claude to run the scripts from it.)

### Quick start

```bash
git clone <this repo> && cd claude-migration-kit

bash scripts/find-partitions.sh        # 1. find source/target; SAVE the enabled-task list
cp scripts/config.example.sh scripts/config.sh && $EDITOR scripts/config.sh   # 2. fill it in
bash scripts/migrate.sh check          # 3. read-only preflight (safe while Claude runs)

# 4. quit Claude Desktop (⌘Q), then:
bash scripts/migrate.sh test           # 20 sessions only — reopen Claude and verify
bash scripts/migrate.sh all            # everything; tasks imported PAUSED

# 5. reopen Claude, then restore the enabled set in batches:
bash scripts/restore-enabled.sh --dry-run
bash scripts/restore-enabled.sh --limit 5
```

Browser automation is a separate chapter: [docs/03-browser-bridge.md](docs/03-browser-bridge.md).

### What is preserved

| Asset | Preserved? | Notes |
|---|---|---|
| Conversation transcripts | ✅ | Already shared; the App just needs the metadata |
| Session list (titles, folders) | ✅ | Copy `local_*.json` into the new partition |
| Scheduled tasks / routines | ✅ | Imported **paused**; re-enable in batches |
| Skills, memory, `CLAUDE.md` | ✅ | Not account-scoped — nothing to do |
| Project files & git | ✅ | Never touched |
| Cowork sessions + workspaces | ✅ | Separate partition, same technique |
| Browser automation | ⚠️ | Pairing is account-scoped; the official extension needs a paid plan → see docs/03 |
| Plugins | ❌ | Marketplace-synced; reinstall them |
| Published Artifacts / claude.ai chats | ❌ | Tied to the old account; unrecoverable |

### Requirements

macOS, `bash`, `python3`, Claude Desktop. For the browser bridge: Node.js ≥ 18 and Chrome.

### Contributing

Found a problem this kit doesn't warn about? That is the most useful thing you can report —
see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
