# docmunch 技术预研报告

- 调研日期：2026-11-07
- 方法：官方文档/仓库源码直读 + MoonCakes 注册表实测（本机 3,457 个包索引）+ arXiv API 检索
- 证据等级：✅ 直接读到源码或官方文档 · ⚠️ 只到 README 层 · ❓ 未能验证
- 对应决策记录：[`decisions.md`](decisions.md)

---

## 0. 三个改变方案的前提

### 0.1 参考仓库是空的

`PingGuoMiaoMiao/docmunch` 只有 `LICENSE`(MIT) 和一个 10 字节的 README（内容是 `# docmunch`），**没有任何代码**。仓库 2026-11-07 当天创建，`git tree` 里只有两个文件。

- 证据：<https://api.github.com/repos/PingGuoMiaoMiao/docmunch/contents/>
- 结论：不存在"照搬一份 MoonBit 翻译"的路径，只能按需求重新设计。

### 0.2 Markdown 不需要 C-FFI

`moonbit-community/cmark` 已是纯 MoonBit 的 CommonMark 工具包，带源码位置信息，支持表格/脚注/公式，并自带 CLI。

- 证据：<https://github.com/moonbit-community/cmark.mbt>
- 结论：预研阶段设想的 "extern C + cmark" 方案直接作废。

### 0.3 MCP 不需要 Node SDK

`colmugx/mcp` 是纯 MoonBit 的 MCP SDK，含 server/client/host、stdio 与 streamable HTTP、参数 schema 预编译校验。

- 证据：<https://github.com/colmugx/mcp.mbt>
- 结论："编译到 JS 复用 `@modelcontextprotocol/sdk`"的方案不采用。

### 0.4 一条合规红线

`jgravelle/jdocmunch-mcp` 的许可证写着 "Free for non-commercial use; commercial use needs a one-time license"，GitHub 标记为 `NOASSERTION`，**不是 OSI 许可**。黑客松要求 OSI 许可并披露来源。

- 证据：<https://api.github.com/repos/jgravelle/jdocmunch-mcp>
- 结论：只研究其**设计、契约与算法**，代码 clean-room 重写；不复制任何实现文件。

---

## 1. 技术预研结论表

| 能力项 | MoonBit 现状 | 建议方案 |
| --- | --- | --- |
| **HTTP：HTTPS** | [`moonbitlang/async/http`](https://github.com/moonbitlang/async/blob/main/src/http/README.mbt.md) 的官方测试直接请求 `https://www.moonbitlang.com`；根 README 写明 "HTTPS client support" + "TLS support via OpenSSL"。**✅ 结论：native 后端 HTTPS 可用。** | 默认用 `async/http`。 |
| **HTTP：流式** | 同一份 README：`@http.Client` 既是 `@io.Writer` 也是 `@io.Reader`，可 `request → 写 body → end_request → 分块读`。**✅ 结论：支持流式，不必整包读入。** | 大页面用流式读 + 上限截断。 |
| **HTTP：代理** | 根 README 明确列出 "`CONNECT` based HTTP/HTTPS proxy support"；http README 补充"proxy 在 JS 后端不支持"。**✅ 结论：native 支持 CONNECT 代理，JS 后端不支持。** | 代理作为可选配置，native-only。 |
| **HTTP：第三方库** | [`oboard/mio`](https://github.com/oboard/mio)（README 现名 reqbest）0.5.4：HTTP/1.1 + 实验性 H2/H3、流式、代理、gzip/deflate/br/zstd、JS Fetch；[`q2316367743/moonhttp`](https://github.com/q2316367743/moonhttp) 0.6.0：axios 风格 + 流式/SSE/自动重定向；[`moonbitstack/moonhttp`](https://github.com/moonbitstack/moonhttp) 0.15.1 是 sans-IO 协议族（"Bytes in, events out; no sockets"）。**⚠️ 结论：mio 功能面最宽但 H2/H3 自称实验性；官方 async 最稳。** | 抽象 `docmunch/http` 接口，默认 `async/http`，mio 可替换。 |
| **HTML：合规度** | [`moonbit-community/html`](https://github.com/moonbit-community/html5-mbt) 0.2.3：WHATWG 取向的 tokenizer + 23 个插入模式，**8,221/8,221 条 html5lib 用例通过**；自述不含 fragment parsing 等场景。**✅ 结论：整文档解析够用。** | 选定它做唯一 HTML 入口。 |
| **HTML：DOM 能力** | 同一 README 的 API 表：`parse / parse_with_errors / tokenize`，DOM 只有 `dump / to_html / get_children / get_parent / get_tag_name / get_attribute / get_text_content`。**❌ 结论：只读扁平树，没有 createElement/appendChild/remove/cloneNode/querySelector，Readability 的原地改写跑不了。** | 自建 arena DOM（见 §3）。 |
| **HTML：选择器** | 3,457 个包里没有 selector/querySelector 类库（只有 `css`/`crater-css` 等 CSS 解析器）。**❌ 结论：没有选择器引擎。** | 不引入选择器，用标签 + class/id 正则做候选筛选。 |
| **HTML：备选实现** | [`bobzhang/html_parser`](https://github.com/bobzhang/html_parser) 0.2.1（JustHTML 移植，含 sanitizer）；[`marianoguerra/html`](https://github.com/marianoguerra/shrubbery-mb) 0.1.1（宽容解析 + printer + 诊断）；[`hustcer/html2md`](https://github.com/hustcer/html2md) 0.1.3（HTML→CommonMark）。**✅ 结论：HTML→MD 已有实现可参考，但 DOM 操作同样弱。** | DOM 层自研；html2md 作对照实现。 |
| **Markdown** | [`moonbit-community/cmark`](https://github.com/moonbit-community/cmark.mbt) 0.4.12：CommonMark + 源码位置 + 表格/脚注/数学公式 + CLI；[`mizchi/markdown`](https://github.com/mizchi/markdown.mbt) 0.8.4 是增量 CST(GFM) 但依赖极重；[`shiguri-01/markdown`](https://github.com/shiguri-01/markdown.mbt) 0.1.1 事件驱动 + mdast、零依赖。**✅ 结论：纯 MoonBit 已够用，不需要 FFI。** | 用 `cmark`。 |
| **C-FFI 能力（备用）** | [官方 FFI 文档](https://docs.moonbitlang.cn/language/ffi.html)：`extern "C" fn f() -> T = "sym"`、`#external type T`（C 侧 `void*`）、`moon.pkg` 的 `native-stub`/`cc-link-flags`、`moonbit.h` 的 `moonbit_incref/decref` 与 `moonbit_make_external_object`。**✅ 结论：C ABI 绑定可行，但本轮不需要。** | 不引入 FFI。 |
| **正则** | [`moonbitlang/regexp`](https://github.com/moonbitlang/regexp.mbt) 0.3.6：VM 执行、可预测复杂度；支持捕获组、命名组、`\p{L}`、**反向引用 `\1`（官方警告可能指数级）**；README 顶部标注 **alpha，API 仍会变**。**⚠️ 结论：平台检测/噪声过滤够用，要锁版本。** | 只用捕获组 + 字符类，禁止在正文上跑回溯型模式。 |
| **文件系统** | `moonbitlang/async/fs`（文件 IO + 目录遍历）、`async/process`、`async/shell`；README 标注 Linux/macOS/**Windows(IOCP)** 全支持。**✅ 结论：fs/process 齐全。** | 原子写（temp + rename）用 `async/fs`。 |
| **路径** | 2026-11-05 更新：路径库已合入标准库，`moonbitlang/core/path` 提供 `extname/basename/dirname` 与 `/` 拼接。**✅ 结论：不必自己写。** 来源：<https://www.moonbitlang.cn/updates/2026/11/05/index> | 用 `core/path`。 |
| **MCP / JSON-RPC** | [`colmugx/mcp`](https://github.com/colmugx/mcp.mbt) 0.18.2：MCP 2026-07-28、`run_stdio()`/`run_http()`、客户端/host、schema 预编译校验；[`marianoguerra/mcp-server`](https://github.com/marianoguerra/mcp-mb) 0.10.1 是零依赖路由核心 + transport trait。**✅ 结论：纯 MoonBit 能做 stdio MCP 服务器。** | 用 `colmugx/mcp`。 |
| **JSON / 哈希** | `moonbitlang/core/json`（官方 JSON 已迁入 core）；注册表有 `sha256`/`sha1`/`md5`/`crc32`。**✅ 结论：序列化与内容哈希都有现成件。** | 索引 JSON + sha256。 |
| **字符集** | `async` 不做 charset 嗅探；注册表有 `0Ayachi0/GB18030` 等编码包。**⚠️ 结论：中文站点要自己嗅探转码，但不是阻塞项。** | v1 只处理 UTF-8，非 UTF-8 降级并告警。 |

---

## 2. 参考实现与算法原理

### 2.1 jdocmunch-mcp 拆解

| 条目 | 结论 | 来源 |
| --- | --- | --- |
| **工具契约（11 个）** | `index_local`、`index_repo`、`delete_index`、`list_repos`、`doc_resolve_repo`、`get_toc`、`get_toc_tree`、`get_document_outline`、`search_sections`、`get_section`、`get_sections`、`get_section_context`。`get_section` 用字节偏移 seek 读，`verify` 可重算哈希校验缓存完整性。 | [SPEC.md](https://raw.githubusercontent.com/jgravelle/jdocmunch-mcp/master/SPEC.md) |
| **章节树构建** | 第一遍扁平解析（每个标题一条 Section），第二遍 `wire_hierarchy()` 用"打开的标题层级栈"回填 `parent_id`/`children`；第一个标题之前的内容是 level-0 根节。 | [ARCHITECTURE.md](https://raw.githubusercontent.com/jgravelle/jdocmunch-mcp/master/ARCHITECTURE.md) |
| **字节偏移记录** | 逐行累加 `len(line.encode("utf-8"))`，**按 UTF-8 字节而非字符计数**，因此可直接 `seek()`。索引只存偏移，不存正文。 | 同上 |
| **增量索引** | `file_hashes: {path: sha256}` 做文件级增量；`Section.content_hash` 做取回校验；`INDEX_VERSION` 不匹配即全量重建；内存缓存键 `路径 + mtime_ns`。 | 同上 + SPEC |
| **Section ID** | `{repo}::{doc_path}::{slug}#{level}`，slug 是标题 lowercase + 非字母数字转连字符，并**前缀祖先 slug 链**（`installation/prerequisites`），使兄弟插入不引起 ID 漂移。 | 同上 |
| **检索打分** | 标题精确 +20 / 标题子串 +10 / 标题词重叠 +5 · 摘要子串 +8 / 摘要词重叠 +2 / 标签 +3 / 正文词 +1（封顶 5），命中 0 分剔除，结果不带正文。 | ARCHITECTURE.md |
| **响应信封** | `_meta.latency_ms / sections_returned / tokens_saved / total_tokens_saved / cost_avoided`，累计值持久化到 `_savings.json`。 | SPEC.md |

### 2.2 分块策略：标题层级切分 vs 字节偏移

两者不是二选一，而是分工：

- **标题层级切分决定"检索粒度"**：把文档切成语义自洽的单元，按层级组织成树。这是 RAG 侧关心的事。
- **字节偏移决定"取回成本"**：索引只记 `byte_start/byte_end`，取一节是 `seek + read`，**O(1)**，不需要重新解析、也不需要把正文塞进索引。

代价是索引与原文强绑定：原文一变偏移就失效。jdocmunch 用 `content_hash` + `INDEX_VERSION` 兜底，代价是"校验"而不是"增量纠正"。

学术侧旁证（均可核验）：

| 工作 | 要点 | 来源 |
| --- | --- | --- |
| HiChunk / HiCBench | 多级文档结构化 + Auto-Merge 检索；指出扁平 RAG 评测对 chunking 质量不敏感（evidence sparsity） | <https://arxiv.org/abs/2509.11552> |
| CHORUS | 层级树状 chunking + 元数据，用于文档类 RAG | <https://arxiv.org/abs/2505.01485> |
| CLI-RAG | 尊重文档结构的层级切分 + 双阶段检索（文档级 → 节级） | <https://arxiv.org/abs/2507.06715> |
| Retrieval Taxonomy | 把 Atomic vs Hierarchical 列为"粒度层"的核心权衡 | <https://arxiv.org/abs/2601.20131> |
| structchunk（工程实现，非论文） | Markdown 结构感知切分，**表格按行边界拆**保住语义完整 | <https://github.com/yzp0111/structchunk> |

> ❓ 更正：任务里提到的 "Overlap-based Heading-aware Chunking" 在 arXiv 检索不到对应论文（`all:"heading-aware"` 命中 21 条，全是 attention head 相关工作）。该术语不作为引用使用。

### 2.3 Readability 的输入输出边界

`new Readability(document, options).parse()`：

- **输入**：必须是 DOM Document（浏览器 `document` 或 jsdom 构造的文档）。`parse()` 会**原地改 DOM**，官方建议传 `document.cloneNode(true)`。
- **输出**：普通对象 `{title, content, textContent, length, excerpt, byline, dir, siteName, lang, publishedTime}`，其中 `content` 默认是 HTML 字符串（可用 `serializer` 换成 DOM 节点）。
- **Node.js 用法**：需要外部 DOM 库（jsdom），并把页面 URL 传进去以便相对链接绝对化。

来源：<https://github.com/mozilla/readability>

**与 MoonBit 解析器的对接结论**：html5-mbt 输出的是 node-id 扁平树 + 只读访问器，**不能直接对接**，必须有适配层；但适配层不必实现完整 DOM——把 Readability 实际用到的操作收敛到约 12 个原语即可（见 decisions D3/D4）。

---

## 3. 架构决策

### 3.1 管线切分：哪些纯 MoonBit、哪些必须 FFI

| 环节 | 实现方式 | 依据 |
| --- | --- | --- |
| fetch | **纯 MoonBit**（`async/http`，TLS 由库内部绑 OpenSSL） | HTTPS/CONNECT/流式均有官方文档 |
| platform detect | **纯 MoonBit**（`regexp` + 域名表） | 捕获组够用 |
| extract | **纯 MoonBit**（html5-mbt + 自建 DOM + Readability 兼容评分） | 无现成可变 DOM |
| HTML → Markdown | **纯 MoonBit**（`cmark`） | 保源码位置 |
| section split | **纯 MoonBit** | 纯计算 |
| index/store | **纯 MoonBit**（core/json、async/fs、sha256） | 现成包 |
| serve | **纯 MoonBit**（`colmugx/mcp`） | SDK 完整 |

**结论：整条管线 0 处"必须 FFI"。** 唯一可能需要 FFI 的非 UTF-8 转码也有纯 MoonBit 包可用。

### 3.2 三个具体取舍

**① Markdown 若必须走 C-FFI，选哪个 C 库？**
选 **cmark（C）**：纯 C 无 C++ 运行时依赖；C ABI 稳定，`#external type` 映射 `void*` 无歧义；可用 `moonbit_make_external_object` + `moonbit_decref` 把 `cmark_node*` 生命周期挂到 GC 上；`native-stub` + `cc-link-flags` 直接链接。pulldown-cmark / comrak 是 Rust，要先编 `staticlib` 再暴露 C ABI，还要处理 panic 跨边界与 allocator 一致性，成本明显更高。**但本轮结论是不需要 FFI。**

**② MCP 走纯 MoonBit 还是编译到 JS 复用 Node SDK？**
走 **纯 MoonBit + stdio**：SDK 已实现 JSON-RPC 与 schema 校验；`async` 在 JS 后端的 IO 原语仍未实现；单二进制分发体验远好于"要求用户装 Node"；且"MoonBit 为主语言"本身就是评审加分项。

**③ Readability 兼容到什么程度算够？**
三个可验收指标（fixture 20 页）：标题准确率 ≥ 80%、正文与 Node oracle 的 token 级相似度 ≥ 0.85、噪音节点残留率 ≤ 10%。达不到就降级为"可读抽取"并在 README 写明，不假装等价。

### 3.3 决策清单

完整 ADR 见 [`decisions.md`](decisions.md)。摘要：

| # | 决策 |
| --- | --- |
| D1 | native 优先，JS 只做测试 oracle |
| D2 | `docmunch/http` 接口 + `async/http` 默认实现 |
| D3 | html5-mbt 之上自建 arena DOM |
| D4 | Readability 兼容子集，不逐行移植 |
| D5 | Node 版 Readability 仅作测试 oracle |
| D6 | Markdown 用 cmark，不引入 C-FFI |
| D7 | Section ID 与 jdocmunch 同构 |
| D8 | 索引只存元数据 + 原文缓存，原子写 + 版本门控 |
| D9 | 增量：文件级 sha256；Section 哈希只做取回校验 |
| D10 | MCP 8 个工具，stdio 优先 |
| D11 | 检索用加权打分，不做 embedding |
| D12 | 结构化并发 + 每域名限流 + 超时/体积上限 |
| D13 | 默认拒绝私网地址（SSRF） |
| D14 | 锁 `async@0.22.x`，预留 `core/async` 迁移 shim |

---

## 4. 路线图

| 阶段 | 周期 | 交付物 | 退出标准 |
| --- | --- | --- | --- |
| P0 脚手架 | 0.5 天 | 模块 + 分包含包 + CI | `moon build`/`moon test` 通过 |
| P1 fetch + detect | 3 天 | 流式抓取、缓存、限流、SSRF 防护、平台识别 | 10 个真实站点抓取成功；安全用例被拒 |
| P2 extract | 5 天 | arena DOM + 评分 + 元数据 | 差分三项指标达标 |
| P3 markdown | 2 天 | HTML→CommonMark 规范化 | 20 组黄金文件通过 |
| P4 section split | 3 天 | 标题层级 + 层级 slug + 字节偏移 + 哈希 | 切片不变量测试全绿 |
| P5 index/store | 3 天 | JSON 索引 + 缓存 + 检索 + 取回 | 100 篇 < 5s；取回 P95 < 5ms |
| P6 MCP serve | 3 天 | 8 工具 stdio server | 真实 MCP 客户端端到端通过 |
| P7 加固交付 | 3 天 | 文档、benchmark、LICENSE、示例集 | 黑客松验收六条自检全过 |

**非目标**：embedding 检索、文件监听增量、RST/AsciiDoc/ipynb、SaaS 部署。

---

## 5. 证据附录（本机实测）

| 项 | 结果 |
| --- | --- |
| MoonBit 工具链 | `moon 0.1.20261028 (e1e1f15 2026-10-28)` |
| 注册表索引 | `~/.moon/registry/index` 共 **3,457** 个包索引文件 |
| `moonbit-community/html` | 0.2.3，repo `moonbit-community/html5-mbt` |
| `moonbit-community/cmark` | 0.4.12，repo `moonbit-community/cmark.mbt` |
| `moonbitlang/regexp` | 0.3.6（alpha） |
| `moonbitlang/async` | README 标注 experimental，未来由 `moonbitlang/core/async` 取代 |
| `colmugx/mcp` | 0.18.2，MCP 2026-07-28 |
| `jgravelle/jdocmunch-mcp` | Python，206★，master 分支，SPEC.md 33,917 B / ARCHITECTURE.md 10,845 B |
| `PingGuoMiaoMiao/docmunch` | 空仓库（LICENSE + 10 B README） |
