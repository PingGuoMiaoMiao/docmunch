# P6 MCP 服务：stdio 上的 8 个工具

- 时间：2026-11-08
- 目标：把索引与检索能力通过 MCP 暴露给 AI 客户端（Claude Code / Cursor 等）
- 结论：**`docmunch mcp` 用 stdio 跑通，10 项端到端断言全部通过**

## 1. 协议版本：2026-07-28（无 `initialize`）

`colmugx/mcp@0.18.2` 实现的是 **MCP 2026-07-28**，它是 stateless 的：

- 没有 `initialize` 握手，第一件事是 `server/discover`；
- 每个请求的 `params._meta` 必须带：
  - `io.modelcontextprotocol/protocolVersion`
  - `io.modelcontextprotocol/clientCapabilities`
  - `io.modelcontextprotocol/clientInfo`

第一版 e2e 直接发 `initialize`，服务器回 `-32601 Method not found`；补上 `_meta` 后才进入发现流程（ADR D32）。

## 2. 工具面（8 个，D10）

| 工具 | 参数 | 返回 |
| --- | --- | --- |
| `list_repos` | — | `{repos:[...]}` |
| `index_url` | `url`, `repo?` | `{repo, doc, title, sections}` |
| `index_local` | `path`, `repo?` | `{repo, doc, sections}` |
| `get_toc` | `repo` | `{repo, sections:[{id,level,title,path,bytes,parent}]}` |
| `get_section` | `repo`, `id`, `verify?` | `{verified, markdown}` |
| `get_section_context` | `repo`, `id` | `{ancestors, children, section:{...,markdown}}` |
| `search_sections` | `repo`, `query`, `limit?` | `{hits:[{id,level,title,score}]}` |
| `delete_index` | `repo` | `{deleted}` |

`index_url` / `index_local` 内部复用 P1–P5 的完整链路：fetch → detect → extract → Markdown → split → store。

## 3. 端到端验证（不依赖 MCP SDK）

`tools/mcp_e2e.py` 用**裸 JSON-RPC over stdio**（换行分隔）驱动服务器，避免"用同一个 SDK 验证同一个 SDK"：

```
ok   server/discover
ok   tools/list has 8 tools
ok   index_local
ok   get_toc
ok   search_sections
ok   get_section verified
ok   get_section content
ok   get_section_context ancestors
ok   list_repos
ok   delete_index

all MCP e2e checks passed
```

覆盖点：发现握手、工具清单（名称集合完全匹配）、索引 8 节文档、TOC、检索命中 `Installation`、按 id 取回且 **hash 校验为 true**、祖先链含 `Readability.js`、仓库列表、删除索引。

## 4. 过程中修掉的两个 bug

| 现象 | 根因 | 修法 |
| --- | --- | --- |
| 构建服务器时报 `bad schema: Invalid character '{'` | 属性片段 `{"type":"string",...}` 已自带花括号，外层又包了一层 `{...}`，生成 `"properties":{{...}}` | 属性助手改为生成 `"name":{...}` 整条目，外层只包一次 |
| `Method not found: initialize` | 2026-07-28 是无状态协议，没有 initialize | 改 `server/discover` + 每请求 `_meta` |

## 5. 已知差距

| 差距 | 影响 | 计划 |
| --- | --- | --- |
| 只有 stdio，没有 HTTP | 远程接入需要 SSH/本地 | P6.1 可选 `run_http` |
| 没有认证 | 本机单用户场景可接受 | 远程前必须加 |
| 没有 resources/prompts | 只能用工具 | 暂不需要 |
| `delete_index` 的 repo 名直接落成目录名 | 只做了 `/`→`_` 处理 | 与 D29 对齐，统一走 sanitize |

## 6. 复现

```sh
moon build --target native
python tools/mcp_e2e.py            # 10 项断言
moon run cmd/main --target native -- mcp --root .doc-index   # 手动挂到 MCP 客户端
```
