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
- **12 个工具**：`index_url`、`index_local`、`list_repos`、`list_docs`、`get_doc`、`get_toc`、`get_section`、`get_section_context`、`get_section_descendants`、`search_sections`、`search_titles`、`delete_index`；
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
| 单元 / 集成 | `moon test`（含本地 HTTP 服务器起的 7 个抓取用例：200 / 相对重定向 / 循环 / 404 / 超限 / 超时 / 私网拒绝） | **95/95** |
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
moon test                          # 95/95
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

先承认：**这四个环节单独看都不是新东西**。抽取沿用 Mozilla Readability 的评分思路（D4/D5），转换用 `cmark` 做 Markdown 归一化（D6），分块检索是 BM25 的标准用法（D50）。把它们拼起来也不构成增量。

本项目的增量在**契约层**，具体是三条可验证的性质，且每条都有对应的机制与测试：

| 增量 | 是什么 | 既有组件为什么没有 | 证据 |
| --- | --- | --- | --- |
| **可验证的节身份** | 每节 = `[byte_start, byte_end)` + `sha256(content)`；取回后用 `--verify` 重算比对 | 定长切块（LangChain `RecursiveCharacterTextSplitter` 等）不产生稳定字节区间，切块随分块参数变化而漂移，无法说"我取回的就是当初那一块" | `tools/toc_check.py`：独立读磁盘字节验证连续覆盖 / UTF-8 合法 / sha256 全等 / id 唯一 |
| **标题对齐而非定长切分** | 节边界由标题决定，保留父子层级与祖先 slug 链；标题与正文永不被切开 | 定长切分不认识标题，边界落在句子中间；实测金标小节"整节进入上下文"的比例 **67%（chunk） vs 94%（section）** | `tools/retrieval_eval.py` 的 `complete` 列 |
| **确定性产物** | 同一输入逐字节可复现，并有黄金文件守护；索引版本不匹配即 fail-closed | 多数转换工具的 HTML→MD 输出随版本/依赖漂移，无法做逐字节回归 | `tools/markdown_golden.py` 4/4；`D25`/`D31` |

另外两条属于工程属性而非算法创新，但确实影响可用性：**零外部服务、零 API Key、单原生二进制**（不引入 embedding 与向量库），以及 **MCP 原生暴露 13 个工具**（检索契约直接给到 Agent，而不是让人自己拼脚本）。

**不构成增量的部分（明确排除）**：抽取算法本身、Markdown 转换算法、BM25 检索算法、以及"比现成库更快"。这些都不作为申报点的理由。

---

## 九、召回、上下文完整性与成本收益（回应初审意见二、三）

初审意见：*"按偏移定位小节也不等于完整取回成本为 O(1)，减少上下文输入不能直接推出回答质量提高；请针对真实代理任务中的召回、上下文完整性与成本收益进行清晰说明并附带对照案例。"*

两条意见都成立。**"O(1)"是我们的错误表述，已在全部文档中改正**；**"省 token ⇒ 回答更好"这一推论我们没有证据，也不再声称**。下面是可复跑的对照实验，完整数据与逐题明细见 [`docs/evidence-retrieval.md`](evidence-retrieval.md)。

### 9.1 对照案例（同一语料、同一问题集）

语料：本仓库 `docs/`，20 份文档 / 286 节 / 250 个定长块。问题集：18 个真实问题（中英混合，人工标注金标文档 + 金标小节 + 必须出现的短语）。

```
system          hit@1      hit@5   complete  avg ctx tokens
------------------------------------------------------------
section         8/18       17/18       17/18             1853
chunk           9/18       13/18       12/18             1328
full           18/18       18/18       18/18            52755
```

- `chunk` = 定长 512 字符 + 80 重叠（对应 LangChain/LlamaIndex 的常用配置）+ 块级 BM25；
- `section` = 本项目：标题对齐分节 + 节级 BM25；
- `full` = 不检索，整篇塞进上下文。

**读法**：`full` 的 100% 召回没有意义——它每次消耗 **52,755 token**，是节级方案的 28 倍，语料翻倍就超出任何上下文窗口。定长切分在 hit@1 上以 9:8 略胜，但 hit@5 只有 72%、完整性只有 67%，因为切块边界不认识标题。节级方案用 1.4 倍于切块的上下文，换到 **hit@5 94%、完整性 94%**。

**我们不掩饰的**：hit@1 上节级没有赢。收益出现在"多给几个候选时能否覆盖到"以及"覆盖到是否完整"，而不是"第一个就对"。

### 9.2 真实的取回成本（不是 O(1)）

扣掉进程启动后实测（`tools/cost_model.py`，7 次取中位数）：

| 节数 | search | fetch 单节 |
| --- | --- | --- |
| 286 | 20.7 ms | 10.3 ms |
| 1,430 | 99.4 ms | 47.9 ms |
| 5,720 | 417.8 ms | 216.4 ms |

```
单次取回 ≈ 加载并解析索引 O(节数) + 线性定位 O(节数) + 读该节字节区间 O(节字节)
斜率 ≈ 0.073 ms / 节
```

**正确的表述是**：取回的*磁盘 IO* 与文档大小无关（528 KB 文档里取一节 10.8 KB，读放大 **2%**），但*每次调用*仍要加载并扫描元数据索引，成本随节数近似线性。**已知短板**：长驻 MCP 进程尚未做索引内存缓存；上万节需要分片索引。这两条都写在 `docs/evidence-retrieval.md` 第 4 节，不作为已完成能力。

### 9.3 关于"回答质量"

本项目**没有**做端到端的答案质量评测（那需要固定模型、固定 prompt、多次采样与人工判分，规模远超当前阶段）。因此本申报书**不主张"用了 docmunch 回答更准"**。

可以主张的是三个可测量的中间量，并且都已附实测：

1. **召回**：给定 k=5，节级方案覆盖金标内容的比例 94%；
2. **上下文完整性**：金标小节整节进入上下文的比例 94%（定长切块 67%）；
3. **成本**：平均上下文 1,853 token vs 整篇 52,755 token；磁盘读放大 2%。

这三条是"回答质量不变差"的必要条件，不是充分条件。**要把它变成充分证据，下一步需要**：构造 30–50 个真实代理任务（如"按文档回答问题并引用节 id"），固定模型与 prompt，对三种上下文策略做盲评，报告正确率与 token 成本。这条已列入 `docs/p7-delivery.md` 的已知差距，本轮不做承诺。