# P8 增强：正文检索与 MCP HTTP 传输

- 时间：2026-11-08
- 背景：P7 交付时的两个已知缺口——「检索不覆盖正文」和「MCP 只有 stdio」
- 结论：**52 个单测通过；正文词检索可用；HTTP 传输 6 项端到端断言通过**

## 1. 正文检索：关键词进索引

### 设计（D35）

分节时为每一节提取最多 20 个关键词，随索引一起持久化：

- 只取 ASCII 词（长度 ≥3），转小写，去掉常见停用词（the/and/for/…）；
- 按词频降序取前 20，同频按首次出现顺序（稳定，可复现）；
- 检索时每个命中关键词 +1，**封顶 +5**——正文证据弱于标题（标题 +20/+10/+5），避免长文档靠词频压过精确标题。

代价与边界：

| 项 | 数值 |
| --- | --- |
| 索引体积增长 | `/~60%`（readability 4203 B → 6832 B；python 990 B） |
| 检索延迟 | 无变化（仍不读 raw，中位数与空命令基线持平） |
| 中文正文 | **不覆盖**：CJK 没有空格分词，正文命中仍靠标题/路径（已写入 docstring） |

### 验证

- `core`：关键词按词频排序、停用词被过滤、短词被过滤、数字保留；
- `index`：查询只出现在正文里的词（`twice`）能命中对应小节，且只有它一条。

### 索引版本

`index_version` 1 → **2**。旧索引加载时直接返回 `None`（D31 的 fail-closed 语义），下次 `index` 会重建，不需要手工清理。

## 2. MCP HTTP 传输

`docmunch mcp --http --port 4240` 启动 Streamable HTTP 端点 `POST /mcp`（stdio 仍是默认）。

服务器的头部校验（2026-07-28 规范）要求：

| 头部 | 要求 |
| --- | --- |
| `MCP-Protocol-Version` | 必须存在且等于 `2026-07-28` |
| `Mcp-Method` | 等于 JSON-RPC 的 `method` |
| `Mcp-Name` | `tools/call` 时必须等于 `params.name` |
| `Accept` | `application/json, text/event-stream` |

缺 `Mcp-Name` 时服务器返回 400（`-32020 HeaderMismatch`）——这是这一轮踩到的坑，写进 D36。

### 验证

`tools/mcp_http_e2e.py` 用标准库 `urllib` 起服务、发请求、关进程：

```
ok   server/discover
ok   tools/list has 8 tools
ok   index_local
ok   search_sections
ok   get_section verified
ok   delete_index
all HTTP MCP e2e checks passed
```

## 3. 回归指标（本轮结束）

| 指标 | 结果 |
| --- | --- |
| `moon test` | 52/52 |
| 抽取（4 fixture） | 标题 4/4，平均长度比 1.03，Jaccard 0.91 |
| Markdown 黄金文件 | 4/4 无漂移 |
| 分节字节契约 | 4/4 |
| MCP stdio e2e | 10/10 |
| MCP HTTP e2e | 6/6 |
| 索引 / 检索 / 取回 | 54–300 ms / 19.1 ms / 18.9 ms（基线 19.1 ms） |

## 4. 复现

```sh
moon build --target native
moon test

# 正文词检索
moon run cmd/main --target native -- index fixtures/markdown/readability-readme.md --repo local
moon run cmd/main --target native -- search local npm

# HTTP MCP
python tools/mcp_http_e2e.py
# 或手动挂客户端：
moon run cmd/main --target native -- mcp --http --port 4240
```
