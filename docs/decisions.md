# 决策记录（ADR）

格式：编号 / 决策 / 背景 / 后果 / 被否方案。依据来源见 [`pre-research.md`](pre-research.md)。

---

## D1 — native 优先，JS 只做测试 oracle

- **背景**：MCP 服务器要单二进制分发；`moonbitlang/async` 在 JS 后端只实现了 IO 无关 API 与 fetch。
- **决策**：产物只面向 native（Windows/macOS/Linux）；JS 后端仅用于跑对照测试。
- **后果**：不能用 npm 生态的现成库，但能保证"下载即用"。
- **被否**：全栈 JS 后端 —— stdio/文件/进程都会踩未实现的原语。

## D2 — HTTP 抽象层 + `async/http` 默认实现

- **背景**：官方 `async/http` 有 HTTPS / CONNECT 代理 / 流式，但库标注 experimental；mio 功能更宽（压缩、H2/H3）但多协议自称实验。
- **决策**：定义 `docmunch/http` 内部接口（fetch / stream / headers / redirects），默认实现 `async/http`，mio 作为可替换实现保留。
- **后果**：换 transport 只改一个包；代价是多一层间接。
- **被否**：直接绑死 `async/http` 调用点 —— 未来迁 `core/async` 或换库会全面返工。

## D3 — 在 html5-mbt 之上自建 arena DOM

- **背景**：`moonbit-community/html` 只有只读扁平树 + 6 个访问器，没有 createElement/appendChild/remove/clone。
- **决策**：解析结果一次性导入自有 arena（`Array[Node]` + parent/first_child/next_sibling 索引），实现 insert_before / remove / clone / unwrap / set_attr / text。
- **后果**：多一层数据拷贝（一次），换取完整可写树；节点 ID 稳定便于测试。
- **被否**：fork 上游解析器 —— 上游 8,221 条用例全绿的维护成本太高。

## D4 — Readability 兼容子集，不逐行移植

- **背景**：Readability 是 ~2,000 行 JS，深度依赖完整 DOM 与大量启发式。
- **决策**：实现其算法主干：候选打分（tag 权重 + class/id 正则 + 链接密度 + 短文本惩罚）、top-N 候选、兄弟合并、清理白/黑名单；不追求逐行等价。
- **后果**：可用性与可解释性优先；与 JS 版存在行为差异，需在 README 声明。
- **被否**：完整移植 —— 一个月内无法验证，且会掩盖真正的工程取舍。

## D5 — Node 版 Readability 只作测试 oracle

- **背景**：需要一个"正确性参照"，但不能引入运行时依赖。
- **决策**：`tools/oracle/` 用 Node + `@mozilla/readability` 生成期望输出；只有测试脚本会用到它。
- **后果**：差分测试可量化；CI 需要 Node（可设为可选 job）。
- **被否**：不设参照 —— 无法回答"抽取质量到底够不够"。

## D6 — Markdown 用 cmark，不引入 C-FFI

- **背景**：`moonbit-community/cmark` 已是纯 MoonBit 实现且保留源码位置。
- **决策**：Markdown 生成与校验全部走 cmark；不引入 cmark(C)/pulldown-cmark/comrak。
- **后果**：零构建复杂度；若将来必须 FFI，选 cmark C 版（C ABI 稳定、可用 `moonbit.h` 管生命周期）。
- **被否**：Rust 系 Markdown 库 —— 需要 staticlib + C ABI 包装 + panic/allocator 边界处理。

## D7 — Section ID 与 jdocmunch 同构

- **背景**：`{repo}::{doc_path}::{hierarchical_slug}#{level}` 已被验证能让兄弟插入不引起 ID 漂移。
- **决策**：沿用该格式与层级 slug 链；非 ASCII 标题（如中文）slug 为空时回退为 `sec{index}`。
- **后果**：未来可做索引迁移与对照测试；中文标题的可读性略差，v1.1 再用音译/哈希前缀改善。
- **被否**：纯自增 ID —— 一插入就全部重编号。

## D8 — 索引只存元数据 + 原文缓存

- **背景**：正文塞进索引会让索引体积与写入成本随语料线性膨胀。
- **决策**：索引 JSON 只存 Section 元数据（含字节偏移），正文留在原文缓存；写入用 temp + rename 原子替换；`INDEX_VERSION` 不匹配即失效重建。
- **后果**：取回 O(1)；代价是索引与缓存必须同生命周期管理。
- **被否**：全量正文索引 —— 简单但违背"省 token"的初衷。

## D9 — 增量：文件级 sha256，Section 哈希只做校验

- **背景**：需要"只重解析变化文件"，但又要能发现取回内容漂移。
- **决策**：`file_hashes` 做增量判断；`Section.content_hash` 仅在 `get_section(verify=true)` 时校验。
- **后果**：语义清晰、可解释；不做过设计（不做块级去重）。
- **被否**：内容寻址存储 —— v1 复杂度收益比不划算。

## D10 — MCP 先做 8 个工具，stdio 优先

- **背景**：jdocmunch 有 11+ 个工具，其中 `doc_resolve_repo`、`get_toc_tree` 等是后期演进产物。
- **决策**：v1 工具集 `index_url`、`index_local`、`list_repos`、`get_toc`、`get_section`、`get_section_context`、`search_sections`、`delete_index`；transport 先 stdio，HTTP 可选。
- **后果**：契约面小、易维护；缺树形 TOC，可用 `get_toc` + `parent_id` 自行组装。
- **被否**：一次对齐全部工具 —— schema 维护成本压过收益。

## D11 — 检索用加权打分，不做 embedding

- **背景**：jdocmunch 的加权打分在文档检索上已验证；embedding 需要外部服务或本地模型。
- **决策**：标题精确/子串/词重叠 + 摘要 + 标签 + 正文词（封顶）加权；结果为摘要，正文按需取。
- **后果**：零依赖、可解释、可复现；语义泛化弱于向量检索。
- **被否**：v1 引入向量 —— 会把项目变成"又一个 RAG 基建"，且破坏确定性验收。

## D12 — 结构化并发 + 每域名限流

- **背景**：抓站点必须可控，`async` 提供 task group 且有取消语义。
- **决策**：所有网络任务挂在 `with_task_group` 下；每域名并发上限、请求超时、单页体积上限。
- **后果**：失败会取消同组任务，不会留下孤儿请求。
- **被否**：无限制并发 —— 既不合规也不稳定。

## D13 — 默认拒绝私网地址

- **背景**：MCP 服务器跑在用户本机，`index_url` 可被诱导访问 `127.0.0.1` 等内部服务。
- **决策**：默认拒绝 loopback/RFC1918/link-local，除非显式开启 `allow_private`；只跟同域重定向；Content-Type 白名单。
- **后果**：本地文档站点需要显式开关（可接受）。
- **被否**：信任调用方 —— 与"默认安全"冲突。

## D14 — 锁 `async@0.22.x`，预留迁移 shim

- **背景**：官方明示 `moonbitlang/async` 将被 `moonbitlang/core/async` 取代，API 仍会变。
- **决策**：锁小版本；`http` 与 `fs` 两处只经由内部 shim 调用。
- **后果**：升级成本集中在一个文件。
- **被否**：直接用 `core/async` —— 仍是实验包，需 `allow-experimental-packages`。

---

## D15 — 缓存键与布局

- **背景**：P1 需要缓存原始字节，P4/P5 的字节偏移又依赖"同一份原文"。
- **决策**：键 = `sha256(url)`；布局 `<root>/raw/<key>.bin` + `<key>.meta`（文本 key=value，便于人读）；写入走 tmp + rename 原子替换。
- **后果**：同 URL 稳定命中；URL 不同即不同文件。meta 里记 `final_url`，便于识别重定向后的真实来源。
- **被否**：按 `host/path` 直接落盘 —— 需要 URL 规范化，且路径穿越风险更大。

## D16 — 超时用 `with_timeout` 包住整条链路

- **背景**：`async` 是协作式调度，超时必须由运行时取消，而不是在循环里看表。
- **决策**：`fetch` 入口用 `@async.with_timeout(timeout_ms, ...)` 包住 DNS + 连接 + 读体；超时映射为 `Timeout`，其余错误按 `FetchError::_` 透传、未知错误降级为 `NetworkError`。
- **后果**：超时能真正中断 socket 读；代价是超时粒度为整次请求（不含重试预算）。
- **被否**：每个 read 单独计时 —— 语义复杂且无法约束 DNS/TLS 握手。

## D17 — 手动跟随 3xx，每跳都过策略

- **背景**：`@http.Client` 是否自动跟随重定向未在文档中声明，且自动跟随会绕过 SSRF 检查。
- **决策**：用 `get_stream` 自己处理 3xx：读 `Location` → `skip_response_body` → 解析相对地址 → `redirect_allowed` 校验 → 下一跳重新 `check_target`。上限 `max_redirects`（默认 5）。
- **后果**：每一跳都可审计；跨域 https 跳转允许，https→http 一律拒绝。
- **被否**：依赖库自动跟随 —— 安全策略不可见。

## D18 — 4xx/5xx 返回结果而非抛错

- **背景**：MCP 工具需要把 404 如实报告给用户，而不是让整次调用失败。
- **决策**：`fetch` 只在"取不到 HTTP 响应"时抛错；拿到响应后无论状态码都返回 `FetchResult`（含 status）。
- **后果**：调用方负责判定；`TooLarge`/`Timeout`/`Blocked` 仍是错误，因为它们没有可用的响应体。
- **被否**：4xx 抛错 —— 与"把文档站当数据源"的用法冲突（重定向到登录页很常见）。

## D19 — 平台 marker 顺序：框架优先于托管商

- **背景**：`docs.python.org` 页面里同时含 `sphinx` 与 `readthedocs` 字样，首轮被误判为 ReadTheDocs。
- **决策**：HTML marker 按"具体框架 → 托管平台"排序（sphinx 先于 readthedocs）；`*.readthedocs.io` 由域名规则兜底命中 ReadTheDocs。
- **后果**：Sphinx 站点判为 `sphinx`，RTD 托管站判为 `readthedocs`。
- **被否**：只留域名规则 —— 自建 Sphinx 站会全部落到 generic。
---

## D20 — 不建 arena，直接改写 parser 的可变树

- **背景**：预研假设 `moonbit-community/html` 只读；实际它有 `append_child` / `remove_child` / `insert_before`，但 `Node` 构造器包内可见（`Cannot create values of the read-only type`），既不能造节点也不能跨文档克隆。
- **决策**：放弃自建 arena DOM，改为在 parser 的树上原地清洗、剪枝、unwrap，再 `to_html()` 截取 `<body>`。
- **后果**：省掉一整层数据拷贝，抽取退化为"删除 + 序列化"；代价是没有节点克隆能力，无法像 Readability 那样把兄弟节点搬进容器。
- **被否**：写一套自己的 Node 表示再重建树 —— 先把 8,221 条 html5lib 用例的解析结果搬过来，成本远超收益。

## D21 — class/id 负向信号必须整词匹配

- **背景**：Docusaurus 的主包装层带 `__docusaurus_skiptocontent_fallback`，GitHub 的 README 容器叫 `sharedmarkdowncontent__…`；子串匹配 `skip` / `share` 会把整页内容删光。
- **决策**：把 `class/id/itemprop` 切成小写 token（任意非字母数字为分隔），负向/正向词都做**整词**比较。
- **后果**：`share-buttons` 仍被删，`sharedmarkdowncontent` 保留；一次修好两个 fixture。
- **被否**：把 `share`/`skip` 从词表里删掉 —— 治标，下一站还会踩别的词。

## D22 — 容器定位用"祖先链折叠 + unwrap"

- **背景**：最初的做法是"剪掉 `<body>` 里除候选父节点以外的直接子节点"，但候选的父节点往往不是 body 的直接子节点，于是整个内容树（body 唯一子节点）被删掉。
- **决策**：从容器逐层向上，每层只保留通往容器的那一个孩子，到达 body 后再删旁支，最后把容器之上的包装层 `unwrap` 掉。
- **后果**：抽取结果就是容器本身，序列化不含整页外壳。
- **被否**：直接在容器子树内序列化 —— parser 没有提供"序列化任意子树"的 API。

## D23 — 标题清洗的三条规则

- **背景**：真实 `<title>` 常带站点后缀/前缀与 arXiv 的 `[id]` 前缀，Readability 会做清洗。
- **决策**：① 去掉开头 `[…]`；② 去掉 `| · — –` 分隔的后缀（后缀 ≤40 字符）；③ 若标题以 `{site_name} - ` 开头则去掉前缀。
- **后果**：三个 fixture 标题全部命中；代价是极少数以 `Site - ` 开头的正文标题会被误剪。
- **被否**：完全照搬 Readability 的标题候选打分 —— 依赖 h1/站点名多轮比较，收益不足以覆盖复杂度。
---

## D24 — 自研 HTML→Markdown，而不是引第三方转换器

- **背景**：`hustcer/html2md` 依赖另一套 HTML DOM；`moonbit-community/cmark` 只做 Markdown→AST→HTML，没有反向渲染。
- **决策**：在抽取层剪好的同一棵 DOM 上直接渲染 CommonMark，规则表见 `docs/p3-markdown.md` §1。
- **后果**：少一次重解析、输出可控可测；代价是表格/嵌套列表等边角要自己维护。
- **被否**：先转 HTML 再调 cmark —— 方向不对，cmark 不做 HTML 输入。

## D25 — 候选容器必须按文档顺序决胜

- **背景**：黄金文件"更新后立即校验"全部漂移；根因是 `best_candidate` 遍历 `Map` 取最大分，并列时哈希顺序不同导致容器选择在进程间不稳定。
- **决策**：改为按 `collect_elements` 的文档顺序遍历，分数**严格大于**才替换。
- **后果**：同一输入逐字节可复现，黄金文件才有意义。
- **被否**：给分数加随机扰动之外的 tie-break —— 文档顺序本身就是最自然的稳定序。

## D26 — Markdown 输出前把相对链接绝对化

- **背景**：抽取出的文章里大量 `/docs/x`、`next.html` 这类相对链接，脱离原页面后不可用。
- **决策**：转换前遍历 `a[href]` / `img[src]`，用 WHATWG 解析器按页面 URL 补齐；`#`、`mailto:`、`data:` 保持原样。
- **后果**：`docmunch markdown <url>` 直接产出可分享的文档；本地文件模式（无 base）保持相对。
- **被否**：在渲染阶段做字符串替换 —— 容易误伤代码块里的 URL。
---

## D27 — 非 ASCII 标题用内容哈希做 slug

- **背景**：`slugify` 只保留 ASCII 字母数字，中文标题全部退化为 `sec{位置号}`；一旦在前面插入一节，后续所有 ID 漂移。
- **决策**：slug 为空时取 `h` + `sha256(标题)` 前 8 位；ASCII 标题维持原规则。
- **后果**：中文标题 ID 稳定、可去重，但不可读；需要可读 ID 时用标题本身（已存在 `title` 字段）。
- **被否**：拼音/音译 —— 引入词典依赖，且中文多音字会制造新的不稳定。

## D28 — 分节前清洗标题噪声

- **背景**：HTML→Markdown 会带出零宽空格（Docusaurus 锚点）、`¶`（Sphinx headerlink）、NBSP、BOM；它们会让 slug 变空、标题显示异常。
- **决策**：`sanitize_title` 剥离 U+200B / U+FEFF / U+00A0 / U+00B6，再 trim。
- **后果**：标题与 slug 在真实站点上稳定；代价是正文里若有纯排版用的零宽字符也会被去掉（无害）。
- **被否**：在 Markdown 转换层清洗 —— 只能覆盖我们自己生成的 Markdown，用户直接喂的 .md 仍会脏。
---

## D29 — raw 文件名用 `sha256(doc_path)`

- **背景**：原文缓存要按 `doc_path` 定位，但 `doc_path` 可能是 `docs/a/b.md`，直接拼路径既有穿越风险又会制造嵌套目录。
- **决策**：文件名 = `sha256(doc_path).bin`，索引里保留可读的 `doc_path`。
- **后果**：无路径穿越、目录扁平；代价是 `ls raw/` 不可读，需要 `index.json` 对照。
- **被否**：URL 编码后的路径 —— 仍然要处理 `..`、大小写与长度限制。

## D30 — 检索只打元数据，不读正文

- **背景**：正文词匹配需要把 raw 读进来，每次检索都要付 I/O 代价。
- **决策**：v1 只对标题与 `doc_path` 打分（+20/+10/+5/+2），正文匹配交给 `get_section`。
- **后果**：检索恒定开销、结果可解释；代价是"词只在正文里"的节会漏。
- **被否**：v1 就做正文全文检索 —— 需要倒排索引，超出 P5 范围。

## D31 — 索引版本不匹配即视为未索引

- **背景**：schema 演进后旧 JSON 可能缺字段，强行反序列化会得到半残索引。
- **决策**：`index_version` 不等于当前值时 `load_index` 返回 `None`，调用方重建。
- **后果**：升级后第一次访问会重建，宁可慢一次也不返回错数据。
- **被否**：向后兼容迁移 —— 现在只有一个消费者，迁移代码是纯负担。
---

## D32 — MCP 走 2026-07-28 无状态协议：`server/discover` + 每请求 `_meta`

- **背景**：`colmugx/mcp@0.18.2` 的默认协议是 MCP 2026-07-28；直接发 `initialize` 会得到 `-32601 Method not found`，缺 `_meta` 会得到 `-32602`。
- **决策**：客户端先 `server/discover`；每个请求的 `params._meta` 带 `protocolVersion` / `clientCapabilities` / `clientInfo`。e2e 脚本按此实现。
- **后果**：与旧版（2025-11-25）客户端不兼容；SDK 提供 `LegacyClient` 兜底，但我们的服务端只讲新协议。
- **被否**：兼容双协议 —— 会在服务端引入两套握手状态机，P6 不值得。

## D33 — e2e 用裸 JSON-RPC 而不是同一套 SDK

- **背景**：用 SDK 客户端验证 SDK 服务端，协议层的问题会互相掩盖（比如两边都错同样字段）。
- **决策**：`tools/mcp_e2e.py` 手写换行分隔的 JSON-RPC 2.0，只依赖标准库。
- **后果**：协议细节（`_meta`、`resultType`）暴露得很直接；代价是脚本要自己处理超时与进程生命周期。
- **被否**：Node 版官方 SDK —— 引入 npm 依赖，且会掩盖 MoonBit 侧的序列化差异。