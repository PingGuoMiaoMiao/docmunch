# docmunch 项目申报书

## 基本信息

| 项 | 内容 |
| --- | --- |
| 项目名称 | **docmunch**：面向 AI 代理的按节检索式文档基础设施（MoonBit 实现） |
| 参赛者 | PingGuoMiaoMiao |
| 联系方式 | 3226742838@qq.com |
| GitHub 仓库链接 | https://github.com/PingGuoMiaoMiao/docmunch |
| 项目方向 | MoonBit 开发者工具 / AI 文档基础设施（对应赛事推荐清单「通用文件格式转换库」方向） |
| 是否为移植项目 | **否**。项目为独立实现，无上游代码可移植（说明见 §7.1） |
| 有效 MoonBit 代码量 | **6,184 行 / 43 个 `.mbt` 文件**（含测试；生产代码约 4,868 行） |
| 当前状态 | 可构建、可运行、可复现；**95 个单测全绿**；8 项验收自检全部通过；38 个提交、49 条 ADR |

---

## 一、项目简介

docmunch 解决的是**大模型读文档太贵**这个问题：把一整篇文档（少则几千、多则十几万字）塞进上下文，既浪费 token 又降低回答质量。

docmunch 的做法是先把文档**按标题层级切成节**，给每一节记下在原文里的**字节区间**和**内容哈希**；之后 AI 代理可以「先看目录 → 检索小节 → 只取需要的那一节」，取回成本是一次 `seek + read`，不需要重新解析、也不需要把全文塞进上下文。

整条链路用 MoonBit 从零实现，编译为单个原生二进制：

```
URL / 本地文件
   → 抓取（HTTPS、流式、重定向、SSRF 防护、charset 转码）
   → 平台识别（16 类文档框架）
   → 正文抽取（Readability 兼容评分，去掉导航/广告/页脚）
   → HTML → CommonMark
   → 按标题分节（ATX/setext、感知代码围栏、跳过 frontmatter、UTF-8 字节偏移）
   → 索引（元数据 JSON + 原文缓存 + 每节 sha256 + 关键词）
   → 检索与按字节区间取回（读放大实测 2%）
   → 通过 MCP 暴露给 Claude Code / Cursor 等 AI 客户端
```

它面向三类使用者：想把文档接入自有 Agent 的**库作者**、需要本地文档检索能力的**工具开发者**、以及希望降低上下文成本的**应用开发者**。

**与常见方案的区别**：不是又一个 RAG 向量库，索引里不存 embedding、不存正文，只用「标题树 + 字节偏移 + 关键词」这套可解释、可复现的结构；单机、零外部服务、零 API Key 即可运行。

---

## 二、核心功能范围

### 2.1 抓取层

- HTTPS 抓取，支持流式读取（边下边算，超限立即中断，不必先下完再判断）；
- 支持 `CONNECT` 代理（native 后端）；
- 手动跟随 3xx，**每一跳都重新做 SSRF 校验**：默认拒绝 loopback / RFC1918 / 链路本地地址，https→http 降级一律拒绝；
- 按 WHATWG Encoding Standard 做字符集转码（Content-Type 或 `<meta charset>` 嗅探），GBK/Big5/Shift_JIS 页面不再乱码；
- 原始响应按 `sha256(URL)` 落盘缓存（epoch TTL，默认 24h），仅对网络类错误做有界重试；
- 内容类型白名单、单页体积上限、超时统一由运行时取消。

### 2.2 抽取层

- 基于 `moonbit-community/html`（WHATWG 取向，8,221 条 html5lib 用例）做正文抽取；
- 在解析器的可变树上**原地**清洗：删 script/style/nav/footer/aside/form 等，按 `role`、`hidden`/`aria-hidden`、class/id 的**整词**负向信号剪枝；
- Readability 兼容的候选打分：段落按文本长度、逗号数、正负向信号加权，分数向父节点与祖父节点传播；
- 链接密度裁剪：文本 ≥120 字符且链接占比 ≥65% 的区块整体丢弃（解决目录型残留）；
- 元数据提取：`title`（含去 `[id]` 前缀、去 `| Site`/`·`/`—` 后缀、去站点名前缀）、`byline`、`site_name`、`lang`。

### 2.3 Markdown 层

- 自研 HTML → CommonMark 渲染器：标题、段落、强调、行内代码、围栏代码块（保留语言标注）、有序/无序列表、引用块、GFM 管道表、链接、图片、分隔线；
- 相对链接按页面 URL **绝对化**（`/docs/x` → `https://…/docs/x`），产出可直接分享的文档；
- 输出确定性：同一输入逐字节可复现（有黄金文件守护）。

### 2.4 分节层

- 标题识别：ATX（`#`…`######`）与 setext（`===`/`---`）；
- 感知 ``` / ~~~ 代码围栏，围栏内的 `#` 不会被误判成标题；
- 跳过 YAML frontmatter（`---` 开头到闭合行），其字节归入 preamble；
- 每节记录 **UTF-8 字节偏移** `[byte_start, byte_end)` 与 **sha256(content)**；
- 层级化稳定 ID：`{repo}::{doc_path}::{祖先slug链}/{slug}#{level}`，兄弟插入不引起其他分支改号；非 ASCII 标题用内容哈希做 slug，避免位置号漂移。

### 2.5 索引与检索

- 布局：`<root>/<repo>/index.json`（只存元数据，不存正文）+ `<root>/<repo>/raw/<sha256(doc_path)>.bin`（原文缓存）；
- 写入走 temp + rename 原子替换；`index_version` 不匹配即视为未索引（fail-closed，宁可重建不返回半残数据）；
- 每节附带最多 20 个正文关键词（去停用词、按词频排序、同频按首次出现），使「词只出现在正文里」的查询也能命中；
- 检索默认 **BM25**（k1=1.2、b=0.75，字段权重 title 3 / path 2 / body 1），旧的加权打分保留为 `--mode weighted`；
- 取回走 `File::read_at(position=byte_start)`，**不加载整篇文档**；`--verify` 会重算 sha256 与索引比对。

### 2.6 MCP 服务

- 实现 MCP **2026-07-28**（无状态协议：`server/discover` + 每请求 `_meta`）；
- **13 个工具**：`index_url`、`index_local`、`index_dir`、`list_repos`、`list_docs`、`get_doc`、`get_toc`、`get_section`、`get_section_context`、`get_section_descendants`、`search_sections`、`search_titles`、`delete_index`；
- 传输：stdio（默认）与 Streamable HTTP（`--http --port`）；
- `get_section` / `get_section_context` 支持 `max_bytes`（默认 8000）截断，返回 `truncated`/`total_bytes`，避免一次调用撑爆客户端上下文；
- 索引写操作由共享互斥锁串行化，HTTP 并发调用不会互相覆盖。

### 2.7 CLI

12 个子命令：`fetch`、`detect`、`extract`、`markdown`、`toc`、`index`、`search`、`section`、`repos`、`delete`、`mcp`、`smoke`。诊断信息走 stderr，stdout 只留数据，可直接进管道。

---

## 三、交付物说明

### 3.1 功能边界（Scope）

**本期包含**：单文档的「抓取 → 抽取 → Markdown → 分节 → 索引 → 检索/取回 → MCP 暴露」完整闭环；本地文件与 URL 两种入口；stdio 与 HTTP 两种 MCP 传输。

**本期明确不含**（避免范围失控）：

- 嵌入向量检索与语义重排（检索只做可解释的加权打分）；
- 整站爬取与链接发现（一次只处理一个给定 URL/文件）；
- RST / AsciiDoc / Jupyter Notebook 解析（本期只做 Markdown 与 HTML）；
- 纯 CSR 页面的 JS 渲染（拿不到内容的站点如实标为限制）；
- 多实例共享索引目录的分布式锁。

### 3.2 预期使用方式

```sh
# 1. 索引一篇在线文档（自动抓取、抽取、分节、落盘）
moon run cmd/main --target native -- index https://docs.moonbitlang.cn/language/ffi.html

# 2. 检索
moon run cmd/main --target native -- search docs.moonbitlang.cn "ffi"

# 3. 按 id 取回某一节（带哈希校验）
moon run cmd/main --target native -- section docs.moonbitlang.cn "<id>" --verify

# 4. 挂到 AI 客户端（stdio）
moon run cmd/main --target native -- mcp
#    或 Streamable HTTP
moon run cmd/main --target native -- mcp --http --port 4240
```

### 3.3 测试规划

| 层次 | 手段 | 当前结果 |
| --- | --- | --- |
| 单元 / 集成 | `moon test`（含本地 HTTP 服务器起的 7 个抓取用例：200 / 相对重定向 / 循环 / 404 / 超限 / 超时 / 私网拒绝） | **115/115** |
| 抽取质量 | 与 Node 版 Mozilla Readability 做差分（4 个真实页面） | 标题 4/4，平均长度比 1.03，词集 Jaccard **0.91** |
| Markdown | 4 份黄金文件逐字节比对 | 4/4 稳定 |
| 分节契约 | 独立脚本读磁盘字节校验：连续覆盖、UTF-8 合法、sha256 全等、ID 唯一 | 4/4 通过 |
| MCP | 裸 JSON-RPC 客户端端到端（不依赖 MCP SDK 自证） | stdio 10/10、HTTP 7/7 |
| 性能 | `tools/bench.py`（进程包含） | 索引 42–148 ms/篇；检索 19.1 ms、取回 18.9 ms（空命令基线 19.1 ms） |
| 验收自检 | `tools/acceptance.py`（六条验收标准脚本化） | 8 PASS / 0 FAIL |
| 可维护性 | 改造后最长文件 486 行、最长函数 149 行、跨包重复纯文本函数 0 处 | 见 `docs/maintainability.md` |

### 3.4 文档覆盖

16 份文档：预研报告（含生态能力盘点与参考实现拆解）、49 条 ADR 决策记录（每条含背景/决策/后果/**被否方案**）、P1–P8 每阶段的实现说明与实测数据、可维护性评估、参考仓库对照与重构计划。README 提供 quickstart 与全部 CLI 用法。

---

## 四、技术路线说明

### 4.1 系统架构与模块划分

按管线阶段分包，每个包一个职责、依赖单向：

| 包 | 职责 |
| --- | --- |
| `core` | 共享模型：`Section` / `DocIndex`、slug 与 ID 规则、UTF-8 字节计数、关键词提取 |
| `http` | 抓取、SSRF 策略、重定向规则、缓存与重试、charset 转码、URL/路径命名、平台指纹 |
| `extract` | DOM 辅助 + Readability 兼容抽取 + 元数据 |
| `md` | HTML → CommonMark |
| `section` | 标题分节、字节偏移、内容哈希 |
| `index` | 存储、检索打分、`get_section` 取回 |
| `mcp` | MCP 工具契约与响应封装 |
| `cmd/main` | CLI（12 子命令） |

### 4.2 关键技术选型（以及为什么拒绝某些选项）

| 选型 | 理由 |
| --- | --- |
| **纯 MoonBit，零 C-FFI** | Markdown 已有 `moonbit-community/cmark`、HTML 已有 `html5-mbt`、MCP 已有 `colmugx/mcp`，不存在必须绑 C 的环节；少一层 ABI 就少一类构建事故 |
| **native 优先** | 单二进制分发；`async` 在 JS 后端的 IO 原语仍不完整 |
| **不引入 embedding** | 检索保持可解释、可复现、零外部服务；正文命中用「每节关键词」这一层轻量索引解决 |
| **自行渲染 HTML→CommonMark** | 抽取层已把 DOM 剪成正文容器，再交给第二个 HTML 库重解析是重复劳动且会丢清洗结果 |
| **索引只存元数据** | 取回只读该节字节区间（实测读放大 **2%**）；索引体积不随正文线性膨胀（单 URL 索引 502 B / 原文 5,292 B）。代价：每次调用仍加载并扫描索引，成本随节数线性（实测 0.073 ms/节），见 `docs/evidence-retrieval.md` |
| **确定性优先** | 同一输入必须逐字节可复现（黄金文件 + 单元测试都依赖这点）；曾因 `Map` 遍历顺序导致产物漂移，改为文档序决胜 |

### 4.3 大模型与智能体工具在开发过程中的作用

开发全程使用 AI 编码代理（Claude Code / Codex 系列）参与：需求拆解、API 调研（读依赖的 `.mbti` 与 README 而非凭记忆）、代码生成、测试编写、文档撰写。

但**质量闸门全部是自动化、可复现的，不依赖模型自评**：

- 每个阶段结束必须 `moon test` 全绿 + 外部校验脚本全绿才允许进入下一阶段；
- 抽取质量用 Node 版 Readability 做差分，不是"看起来差不多"；
- 分节正确性用独立脚本读磁盘字节验证，不信任进程内字符串；
- 每一处取舍（尤其是被否的方案）写进 ADR，共 49 条——这也是「AI 可解释」要求的落点：能说清"为什么这样写"以及"为什么没那样写"。

实测 AI 生成的代码并非一次正确：审计阶段发现并修复了 12 类真实缺陷（极简 HTML 抽取死循环、URL doc_path 互相覆盖、并发写索引丢文档、GBK 乱码入库等），每一条都补了回归测试。这部分过程记录在 `docs/p7-delivery.md` 的修复表里。

---

## 五、风险分析与应对

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 上游库仍标注 experimental（`moonbitlang/async` 未来由 `core/async` 取代） | 升级可能破坏 API | 锁小版本；所有调用收敛在 http 包的 shim 层，迁移只改一处 |
| 抽取质量随站点差异波动（实测 arXiv 0.87 / Sphinx 1.27） | 少数站点正文偏多或偏少 | 差分测试量化；已知偏差写进文档而非掩盖；链接密度裁剪已改善 Sphinx 一档 |
| MCP 协议持续演进（本项目实现 2026-07-28） | 旧客户端不兼容 | 单点实现、协议版本集中在常量；不自行发明扩展 |
| Windows 路径与文件系统语义（保留名、末尾点、大小写） | 索引目录冲突 | `repo_key` 单射映射 + `repo.json` 保存原始名；已覆盖 `CON`/`foo.`/`Repo` 等用例 |
| 非 UTF-8 页面 | 正文乱码 | 按 WHATWG label 真转码；未知标签才回退并置 `charset_warning` |
| 纯 CSR 页面无内容 | 抽不出来 | 明确标注为已知限制，不做 JS 渲染 |
| 索引与原文强绑定（原文一变偏移即失效） | 缓存脏数据 | 每节 sha256 + `index_version` fail-closed，版本不符即要求重建 |

---

## 六、相关研究与实践基础

- **参考实现**：[jgravelle/jdocmunch-mcp](https://github.com/jgravelle/jdocmunch-mcp)（Python，206★）。研究了它的 section ID 方案、UTF-8 字节偏移、文件级 sha256 增量与 11 个工具的契约；因其许可证为非商业（NOASSERTION），**只参考设计、代码独立重写**。
- **算法参考**：[mozilla/readability](https://github.com/mozilla/readability)（Apache-2.0），用于抽取评分与测试期差分 oracle。
- **学术依据**：HiChunk（[arXiv:2509.11552](https://arxiv.org/abs/2509.11552)）证明多级文档结构化可评测且优于扁平切分；CHORUS（[arXiv:2505.01485](https://arxiv.org/abs/2505.01485)）、CLI-RAG（[arXiv:2507.06715](https://arxiv.org/abs/2507.06715)）均采用「尊重文档结构的层级切分」；工程实现 structchunk 给出「结构优先于长度」的切分取舍。本项目采用「标题层级决定检索粒度 + 字节偏移决定取回成本」的分工。
- **生态基础**：`moonbit-community/html`、`moonbit-community/cmark`、`colmugx/mcp`、`moonbitlang/async`、`tonyfettes/url`、`LL728/moon_encoding`、`gmlewis/sha256`（全部 Apache-2.0 或同等 OSI 许可）。

---

## 七、补充材料

### 7.1 为什么不是「移植项目」

本项目的仓库 https://github.com/PingGuoMiaoMiao/docmunch 在开发开始时是一个空仓库（仅占位 README），不存在可以搬运的上游代码；生态中最完整的设计参考 `jgravelle/jdocmunch-mcp` 为非商业许可，不适合直接复制。因此本项目按「先做技术预研（生态能力盘点 + 参考设计拆解 + 算法依据），再独立实现」的路径推进，全部代码为本项目原创，仅在设计契约层面参考公开文档。

### 7.2 可复现证据

```sh
moon build --target native
moon test                          # 115/115
python tools/compare.py            # 抽取差分：4/4，1.03 / 0.91
python tools/markdown_golden.py    # 黄金文件：4/4
python tools/toc_check.py          # 分节字节契约：4/4
python tools/mcp_e2e.py            # MCP stdio：10/10
python tools/mcp_http_e2e.py       # MCP HTTP：7/7
python tools/bench.py              # 性能
python tools/acceptance.py --since 2026-11-01   # 验收自检：8 PASS
```

### 7.3 开源合规

仓库根 `LICENSE` 为 Apache-2.0；`moon.mod` 声明同一许可；全部第三方依赖为 OSI 许可并在 README 与预研文档中列明来源；测试用的 HTML 快照来源标注在 `fixtures/README.md`，仅用于离线测试。
---

## 八、相对既有组件的独立增量（回应初审意见一）

初审意见：*"正文抽取、格式转换、标题分节和关键词检索的组合具有使用价值，但尚未充分证明相较既有文档转换与检索组件的独立增量。"*

先承认三件事，因为它们是事实：

1. **抽取**沿用 Readability 的评分思路（D4/D5），**转换**用 `cmark`（D6），**检索**是标准 BM25（D50）——都不是本项目发明的；
2. **"标题分节"也不是本项目发明的**。LangChain 的 `MarkdownHeaderTextSplitter` 就做这件事。我用真实组件重跑后，两者处于同一水平——**而且我们在 hit@5 与完整性上各落后 1 题**（数据见 §9.1），因此**撤回**上一版"标题对齐是我们的增量"这一主张；
3. 因此，"把四个环节串起来"本身不构成增量。

真正剩下的增量只有一条，而且它不在质量维度，在**可验证性**维度：

| 能力 | LangChain 定长切分 | LangChain 标题切分 | docmunch |
| --- | --- | --- | --- |
| 检索质量（hit@5 / 整节完整性） | 12/18 · 4/18 | 15/18 · 14/18 | 14/18 · 13/18 |
| 产出指回原文的**字节区间** | ✗ | ✗ | ✓ |
| 取回后**重算 sha256 自证** | ✗ | ✗ | ✓（`--verify`） |
| **重复运行逐字节可复现** | ✗ | ✗ | ✓（4 份黄金文件） |
| 索引版本不匹配即 **fail-closed** | N/A | N/A | ✓ |
| 单原生二进制 / 无 Python 运行时 | ✗ | ✗ | ✓ |
| MCP 原生接口 | ✗ | ✗ | ✓（13 个工具） |
| 倒排索引（查询只访问候选节） | ✗（每次全量打分） | ✗（每次全量打分） | ✓（D58） |

一句话：**docmunch 不声称检索更准，它声称"取回的这一段可以被证明就是原文的那一段"，并且这件事在 MoonBit 生态里没有第二家做。**

这条增量对谁有用：需要引用可追溯（合规、审计、教学材料）的 Agent；需要把文档切片契约固定下来、跨版本回归的团队；以及要在 MoonBit 里做文档检索、不想为此引入 Python 运行时的人。

**明确排除在申报点之外的**：抽取算法、Markdown 转换、BM25、以及"比现成库更快/更准"。这些都不作为理由。

---

## 九、召回、上下文完整性与成本收益（回应初审意见二、三）

初审意见：*"按偏移定位小节也不等于完整取回成本为 O(1)，减少上下文输入不能直接推出回答质量提高；请针对真实代理任务中的召回、上下文完整性与成本收益进行清晰说明并附带对照案例。"*

两条都成立：**"O(1)" 是错误表述，已在全部文档改正；"省 token ⇒ 回答更好"没有证据，不再声称。** 下面是可复跑的实测，完整数据在 [`docs/evidence-retrieval.md`](evidence-retrieval.md)。

### 9.1 对照案例：真实组件、同一语料、18 个标注问题

对照系统全部是第三方真实实现：`RecursiveCharacterTextSplitter(512, 80)`、`MarkdownHeaderTextSplitter`（LangChain 官方），检索统一用 `rank_bm25.BM25Okapi`，token 用 `tiktoken` 实数。语料为本仓库 21 份文档。

```
system          hit@1     hit@5   complete   ctx tokens
-------------------------------------------------------
recursive      6/18     12/18       4/18           1371
md_header      7/18     15/18      14/18           1403
docmunch       7/18     14/18      13/18           1353
full_doc      18/18     18/18      18/18          72514
```

- **我们比 `md_header` 略差**：hit@1 相同（7/18），hit@5 落后 1 题（14 vs 15），完整性落后 1 题（13 vs 14）。所以"切得更好"不但不成立，我们在这一组上是略输的；
- **定长切分确实更差**（完整性 4/18 vs 13–14/18），但那是"用不用标题切分"的差异，属于既有库的能力；
- **整篇塞入不可用**：72,514 token，是检索方案的约 **60 倍**；21 份文档就如此。

### 9.2 成本：实测（不是 O(1)）

冷进程（CLI 每次重载索引）：

| 节数 | search | fetch 单节 |
| --- | --- | --- |
| 286 | 20.7 ms | 10.3 ms |
| 1,430 | 99.4 ms | 47.9 ms |
| 5,720 | 417.8 ms | 216.4 ms |

`单次取回 ≈ 加载解析索引 O(节数) + 定位 O(节数) + 读节字节 O(节字节)`，斜率约 **0.073 ms/节**。这是"O(1)"说法错误的原因。

本轮新增**长驻进程索引缓存**（D55）后（5,980 节 / 9.3 MB 索引）：

```
                          get_section   search_sections
cold CLI (parse each)        278.3 ms        535.5 ms
MCP first call               223.4 ms        243.1 ms
MCP cached (median)            0.5 ms         10.2 ms
```

- **取回 278 ms → 0.5 ms（约 553 倍）**，不再随索引体积增长；
- **检索 536 ms → 10.2 ms（约 52 倍）**：新增倒排索引（D58）后查询只访问含查询词的节。冷启动 CLI 仍需重建 postings（约 240 ms @ 6,580 节），这一点如实列出。

磁盘读放大：528 KB 文档中取一节 10.8 KB，**2%**。这部分与文档大小无关，只与节大小有关。

### 9.3 关于"回答质量"：做了实验，但结论有限

初审指出"减少上下文输入不能直接推出回答质量提高"——这条推论我们撤回，改为实测。
方法：独立子代理出 12 道题（含标准答案），每个策略由独立子代理作答（只读自己的上下文，禁止读仓库），再由独立子代理对 A–E 匿名列判分。全部脚本在 `tools/e2e_*.py`，完整记录在 [`docs/e2e-agent-eval.md`](e2e-agent-eval.md)。

```
strategy      correct   partial   wrong    score   ctx tokens  per-question
---------------------------------------------------------------------------
none                0         0      12    0.000          518            43
full_trunc          3         2       7    0.333         8556           713
full               12         0       0    1.000        20275          1690
recursive          12         0       0    1.000        17117          1426
docmunch           12         0       0    1.000        13064          1089
```

三条读数：

1. **无上下文组 0/12**——语料没有被模型记住，控制组成立；
2. **"整篇塞入"在窗口受限时崩到 0.333**（同样 12 题，只给前 8000 token，7 题答案不在上下文里）——这是不检索策略的真实失效模式；
3. **三种检索策略准确率打平（都是 12/12），差异在成本**：docmunch 13,064 token，定长切分 17,117（多 31%），整篇 20,275（多 55%）。摊到每题是 1,089 / 1,426 / 1,690。

**可以主张**：在这组任务上，节级检索把上下文成本降到整篇的约 2/3，**准确率不降**；而整篇塞入一旦超出窗口就急剧失效。
**不能主张**：docmunch 比定长切分更准（打平）、或"回答质量更高"。

**这个实验不能证明什么**（写在 `docs/e2e-agent-eval.md` 第 4 节）：12 题全是单点事实，存在天花板效应；样本小、单次运行、无置信区间；作答与判分同源模型；判分只有三档。要真正区分优劣，需要多跳/比较/否定型问题与第二款模型复核——这是下一步，不是已完成的工作。
