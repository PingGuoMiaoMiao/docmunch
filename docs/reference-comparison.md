# 参考实现对照与重构计划

- 对照日期：2026-11-11
- 参考代码：`D:\reference\jdocmunch-mcp`（`git clone --depth 1` 自 https://github.com/jgravelle/jdocmunch-mcp ）
- 另一个"参考仓库" https://github.com/PingGuoMiaoMiao/docmunch 是空仓库（只有占位 README），**没有可对照的代码**，它就是本项目自己的仓库。

---

## 1. 先回答"这项目到底有没有用"

诚实版结论：**对"一次性读一篇短文档"没用；对"反复查一套文档的 AI 代理"有用。**

有价值的四个场景：

| 场景 | 不用的代价 | 用了的收益 |
| --- | --- | --- |
| AI 代理反复查同一套文档 | 每次都把整页塞进上下文 | 先看目录（~200 token）再取一节（~400 token） |
| 单篇文档很长（>1 万 token） | 触发截断、丢中间内容 | 按节取，永不截断 |
| 需要"稳定的节地址" | 重新生成 chunk，ID 每次变 | id + 字节偏移 + sha256，改文也能定位漂移 |
| 本地/离线/无 API Key | 向量库要部署、要 key | 单二进制，零外部服务 |

什么时候确实不该用它：只读一次、文档很短、只需要全文搜索——直接 `grep` 或把全文丢给模型更省事。

作为参赛项目，它的说服力不在"算法新颖"，而在**工程完整度 + 可复现证据**（79 测试、差分指标、字节契约脚本、两套 MCP 端到端）。

---

## 2. 参考实现的真实规模（实测）

| 指标 | jdocmunch-mcp | 本项目 docmunch |
| --- | --- | --- |
| 语言 | Python | MoonBit |
| 源码文件 | **139 个 `.py`** | 31 个 `.mbt` |
| 源码体积 | **1.70 MB**（约 4 万行） | 约 6,000 行 |
| MCP 工具 | **64 个** | 8 个 |
| 支持格式 | Markdown、MDX、HTML、RST、AsciiDoc、JSON、XML、OpenAPI、Jupyter、org-mode、Godot、Office、OCR | Markdown、HTML |
| 检索 | **BM25**（k1=1.2，可配 b）+ posting cache + 可选 embedding | 加权打分（标题/路径/关键词） |
| 语义检索 | 有（Gemini / OpenAI / 本地模型） | 无（刻意不引入） |
| 交付形态 | Python 包 + CLI + MCP 服务 | 单个原生二进制 + CLI + MCP 服务 |
| 许可证 | NOASSERTION（free for non-commercial） | Apache-2.0 |

> 结论：参考实现是一个成熟产品，不是一个教学项目。我们**不追求功能对齐**（否则 4 万行对 6 千行毫无胜算），而是保持"窄而深"：只做 Markdown+HTML 的高质量链路，把可复现性做到位。

---

## 3. 参考实现的架构（读源码得出）

```
src/jdocmunch_mcp/
├── server.py             158 KB  MCP 工具注册（64 个 tools）
├── parser/               17 files 160 KB
│   ├── sections.py        19 KB  Section 模型、slug、id、content_hash、references/tags/inline_code
│   ├── markdown_parser.py 24 KB  frontmatter、MDX 预处理、prose view、fenced code block 捕获
│   ├── html / rst / asciidoc / json / xml / openapi / notebook / org / godot / office / ocr
│   └── hierarchy.py              parent_id / children 回填
├── storage/              8 files 197 KB
│   ├── doc_store.py      138 KB  save_index / load_index / 原子写 / seek 读区间 / 内存缓存
│   ├── retirements.py           索引淘汰
│   ├── token_tracker.py         token 节省统计（写 _savings.json）
│   └── corpus_claims / replay_log / repo_groups
├── retrieval/            19 files 197 KB
│   ├── bm25.py            10 KB  BM25（字段加权、df 上限、k1/b 可配）
│   ├── posting_cache.py   26 KB  倒排表缓存
│   ├── scoring / tokenize / dedup / freshness / confidence / verdict
│   └── boilerplate / code_compress / offload / related / prune
├── embeddings/           5 files 117 KB   向量生成（Gemini/OpenAI/本地）+ worker
├── cli/                  6 files 105 KB   init / index-local / index-repo / watch
├── tools/                68 files 626 KB  每个 MCP 工具一个实现文件
├── summarizer/                          标题 → AI 摘要
└── watch.py / handoff.py                文件监听、会话交接
```

### 3.1 数据模型（与本项目几乎一致）

```python
@dataclass
class Section:
    id: str            # "repo::doc_path::heading_slug#level"
    repo, doc_path, title, level, parent_id, children
    byte_start: int    # UTF-8 字节偏移
    byte_end: int
    content_hash: str  # sha256(slice)
    summary, tags, references, embedding, code_blocks, inline_code, metadata, anchor, alias_ids
```

`to_dict()` **不写 `content`**——索引只存元数据，正文留在 raw 文件里。这与本项目 D8 的取舍完全一致，说明这套"元数据 + 偏移"的设计是经过实战验证的。

### 3.2 分节算法

1. `content_bytes = content.encode("utf-8")`，全程按**字节**累加（不是字符）；
2. 先定位 frontmatter 结束字节 `fm_byte_end`，把这段 blank 掉防止误判；
3. 逐行扫描：遇到标题就 `_open_heading` 开新节，`_finalize_section` 记录 `current_byte_start..byte_end`；
4. 定稿时顺便抽取 `code_blocks`（语言 + 内容 + 自己的字节区间）、`references`（链接）、`tags`、`inline_code`；
5. 第二遍 `hierarchy.py` 用层级栈回填 `parent_id` / `children`。

### 3.3 存储与取回

- `save_index` 写 JSON（元数据）+ raw 文件，原子替换；
- 取回：`fh.seek(byte_start)` 再读 `byte_end - byte_start`，**不加载整篇**（`doc_store.py:1900` / `:2271`）。

### 3.4 检索

BM25，字段加权（title / summary / tags / content），`k1=1.2`、`b` 可配、df 有上限，配 `posting_cache.py` 做倒排缓存；再叠加 embedding 余弦相似度。

### 3.5 我们尚未实现的部分

embedding、BM25、posting cache、OCR、10+ 格式、文件监听、64 个工具、token 节省统计、索引淘汰与会话交接。

---

## 4. 本项目的真实优势与短板

**优势（应当守住）**

1. 单二进制、零外部服务、零 API Key；
2. 输出确定性：同一输入逐字节可复现（黄金文件 + 文档序决胜）；
3. 可复现证据链完整：抽取差分对齐 Mozilla Readability、分节字节契约脚本、两套 MCP 端到端；
4. 47 条 ADR 记录取舍与**被否方案**，可解释性强。

**短板（对照参考实现）**

| 短板 | 影响 | 优先级 |
| --- | --- | --- |
| 检索只有加权打分，没有 BM25 | 多关键词、长文档场景召回明显弱于参考实现 | **P0** |
| 工具只有 8 个 | 缺"整篇取回""文档列表""子节批量"等常用动作 | **P0** |
| 只有 2 种格式 | 评审清单里 RST/ipynb/OpenAPI 都算加分项 | P1 |
| 无增量跳过 | 已算文件 sha256，但索引层每次都全量重解析 | P1 |
| 无批量并发 | 一次只处理一个 URL，建库慢 | P2 |
| 无 embedding | 语义检索缺失（但与本项目定位冲突，建议只留接口） | P3 |

---

## 5. 重构计划（渐进式，不做大爆炸重写）

**不建议整体重构**：79 个测试 + 8 项验收全绿，模块边界（core/http/extract/md/section/index/mcp）已经清晰，推倒重来的收益远小于风险。建议按阶段增强，每阶段结束跑全量校验。

### 阶段 A：检索升级（1–2 天）—— 最高性价比

- 移植 BM25 思路到 `index/search.mbt`：字段加权（title / keywords / path）、`k1=1.2`、`b=0.75`、df 上限；
- 索引里补 `token_count`（每节词数）与 `doc_freq`（全局词频），检索时算 idf；
- 保留现有加权打分作为 fallback（`search_sections` 增加 `mode=weighted|bm25`）；
- 验收：现有检索测试不回归；新增 5 个 BM25 排序断言。

### 阶段 B：工具面补齐（1 天）

新增 4 个工具，凑到 12 个（对齐参考实现里最常用的）：
`get_doc`（整篇 Markdown）、`list_docs`、`get_section_descendants`、`search_titles`。

### 阶段 C：增量与并发（2–3 天）

- 索引层按文件 sha256 跳过未变文档（引用已算好的 `content_hash`）；
- 批量索引：`index_many` 用 `async` 结构化并发 + 每域名限速（限流器已有）。

### 阶段 D（可选）：第三种格式

优先 RST（文档站最常见）或 ipynb（AI 场景常见），各配一组黄金文件。

### 每阶段的硬性约束

1. `moon test` 全绿、`moon fmt --check` 通过；
2. `tools/compare.py` / `markdown_golden.py` / `toc_check.py` / `mcp_e2e.py` / `mcp_http_e2e.py` 全绿；
3. 索引结构一旦变更，`index_version` 递增（fail-closed，旧索引自动重建）；
4. 决策写入 `docs/decisions.md`，被否方案一并记录。

---

## 6. 参考代码怎么用

- 位置：`D:\reference\jdocmunch-mcp`（已 clone，未纳入本项目仓库）；
- **只读参考**：其许可证为 NOASSERTION（free for non-commercial），**不能复制代码**，只能学习设计与算法思路；
- 建议看这几处：
  - `src/jdocmunch_mcp/parser/sections.py`（数据模型 + id/slug 规则）
  - `src/jdocmunch_mcp/parser/markdown_parser.py`（字节偏移分节 + code block 捕获）
  - `src/jdocmunch_mcp/storage/doc_store.py`（原子写 + seek 读区间）
  - `src/jdocmunch_mcp/retrieval/bm25.py`（BM25 公式，阶段 A 的主要参考）
  - `src/jdocmunch_mcp/server.py`（64 个工具的参数与返回形状）
