# P5 索引层：存储、检索与 O(1) 取回

- 时间：2026-11-08
- 目标：把 P4 的分节结果落成「元数据 JSON + 原文缓存」，支持检索与按字节区间取回
- 结论：**4 个索引单测通过；CLI 端到端（本地文件 + 真实 URL）跑通，哈希校验为 true**

## 1. 存储布局（D8）

```
<root>/<repo>/index.json                  # 只有元数据，没有正文
<root>/<repo>/raw/<sha256(doc_path)>.bin  # 原文，字节偏移指向这里
```

真实产物（索引一个 URL 后）：

```
.doc-index/docs.python.org/index.json      502 B
.doc-index/docs.python.org/raw/18f97a….bin  5292 B
```

两个刻意的选择：

- **raw 文件名用 `sha256(doc_path)`**，不是原始路径：避免路径穿越，也避免 `a/b/c.md` 产生嵌套目录（D29）；
- **索引里不存正文**：正文只在 raw 里，取回时按 `byte_start/byte_end` 读。

写盘全部走 temp + rename，索引 JSON 带 `index_version`，版本不匹配直接当作「未索引」要求重建（D31）。

## 2. 检索（D30）

`search(repo, query)` 只对索引里的元数据打分（不读正文）：

| 命中 | 分数 |
| --- | --- |
| 标题与查询完全相等 | +20 |
| 标题包含查询 | +10 |
| 每个查询词出现在标题 | +5 |
| 每个查询词出现在文档路径 | +2 |

按分数降序、同分保持文档顺序，默认返回前 10 条。选择理由：不需要 embedding、结果可解释、单次检索不碰磁盘正文。

## 3. 取回

```
docmunch section <repo> <id> --verify
verified=true bytes=202
## Installation

Readability is available on npm:
```

`--verify` 会把取回内容重新做 sha256 与索引里的 `content_hash` 比对；实现走 `File::read_at(position=byte_start, len=byte_end-byte_start)`，**不加载整篇文档**。

## 4. 验证

单测（`moon test -p .../index`，4 个）：

1. build → load → search → get_section_text（含 hash 校验）；
2. 同一文档重复索引保持幂等（sections 不翻倍）；
3. 检索排序：精确标题优先；
4. 未索引的 repo 返回 `None` 而不是报错。

CLI 端到端：

```
$ docmunch index fixtures/markdown/readability-readme.md --repo local
repo=local doc=fixtures/markdown/readability-readme.md sections=8 docs=1
$ docmunch search local readability
score=17 level=1 id=local::fixtures/markdown/readability-readme.md::readability-js#1 title=Readability.js
$ docmunch section local "…::installation#2" --verify
verified=true bytes=202
$ docmunch index https://docs.python.org/3/library/asyncio.html
repo=docs.python.org doc=asyncio.html.md sections=1 docs=1
```

## 5. 已知差距

| 差距 | 影响 | 计划 |
| --- | --- | --- |
| 没有 `delete_index` | 只能手动删目录 | P5.1 |
| 检索不打正文 | 查"函数名只出现在正文里"的节会漏 | P5.1 可选：正文词加权（要付读盘代价） |
| 没有并发写锁 | 两个 CLI 同时索引同一 repo 可能互相覆盖 | 单用户场景可接受，MCP 服务端（P6）内串行化 |
| 索引版本变更即丢弃 | 升级 schema 需要重建 | 有意为之（fail-closed） |

## 6. 复现

```sh
moon build --target native
moon run cmd/main --target native -- index fixtures/markdown/readability-readme.md --repo local
moon run cmd/main --target native -- search local readability
moon run cmd/main --target native -- section local "local::fixtures/markdown/readability-readme.md::readability-js/installation#2" --verify
```
