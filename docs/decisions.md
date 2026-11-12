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
---

## D34 — 链接密度裁剪（P7 补）

- **背景**：Sphinx 文档页的 "Reference" 区块是大段纯链接列表，被算进正文；python-asyncio 长度比 1.33×、Jaccard 0.83。
- **决策**：自底向上统计每个节点的"链接文本长度"（`a` 子树整体计入），对 `div/section/ul/ol/p/table/nav` 中文本 ≥120 字符且链接占比 ≥65% 的节点整体删除。
- **后果**：python-asyncio 长度比 1.33 → 1.27、Jaccard 0.83 → 0.86，整体平均 0.90 → 0.91；代价是纯索引页会被抽空（符合"要正文"的定位）。
- **被否**：只删 `ul/ol` —— 目录块常包在 `div`/`section` 里，删不干净。
---

## D35 — 正文检索用"每节关键词"，不做倒排索引

- **背景**：P7 的检索只打标题/路径，查询词只出现在正文时会漏（例如 "twice" 只在小节正文里）。
- **决策**：分节时提取每节 top-20 关键词（ASCII、长度 ≥3、去停用词、词频降序、同频按首次出现），存进索引；检索命中一个 +1，封顶 +5。
- **后果**：索引约增大 60%（readability 4203 → 6832 B），检索仍不读 raw；中文正文不覆盖（无空格分词）。
- **被否**：建倒排索引 —— 体积和复杂度都上一个量级，MCP 单机场景收益不匹配。

## D36 — MCP HTTP 必须带 `Mcp-Name` 等请求元数据头

- **背景**：2026-07-28 的 Streamable HTTP 要求把 JSON-RPC 的方法名/工具名镜像到头部；漏掉时服务器直接 400。
- **决策**：`--http` 模式下客户端必须发送 `MCP-Protocol-Version`、`Mcp-Method`，`tools/call` 还要 `Mcp-Name`（= `params.name`）；e2e 脚本按此实现。
- **后果**：HTTP 端点可直接被标准 MCP 客户端使用；手写客户端需要照抄这三条头。
- **被否**：在服务端放宽校验 —— 会破坏规范一致性，也让"客户端无状态"的设计退化。

---

## D37 — repo 目录身份：可读 key + `repo.json` 还原

- **背景**：早期把 repo 名直接拼进 `<root>/<repo>`，store 把 `[A-Za-z0-9._-]` 之外的字符都换成 `_`：`"a b"` 与 `"a_b"` 会落到同一目录；CLI 与 MCP 各写一套 sanitize（MCP 的 `delete` 只替换 `/`）；`delete` 由调用方自己拼路径，带空格/斜杠的名字要么删不掉、要么删错目录。
- **决策**：
  - 单一入口 `repo_key(repo)`：`[A-Za-z0-9._-]` 之外的字符变 `_`；若发生改写，追加 `-<sha256(原名)[0:8]>` 保证单射；空、`.`、`..` 这类非法目录名映射为 `repo-<sha8>`。
  - `repo_dir` / `index_file_path` / `raw_dir` / `raw_file_path` 全部接收**原始 label**，内部调用 `repo_key`；调用方不再自行 sanitize。
  - `save_index` 在 repo 目录写 `repo.json`（`{"name":"<原始名>"}`）；`list_repos` 优先读它，缺失或损坏时回退目录名，兼容旧索引。
  - `delete_repo(root, repo)` 成为独立 API，目录不存在时静默成功（幂等）。
- **后果**：空格、中文等名字可安全往返；`"a b"` 与 `"a_b"` 永不合并；目录名可能带哈希后缀，`ls` 可读性下降，但 `repo.json` 能还原原始 label。旧版无 `repo.json` 的目录仍会按目录名列出（删除时也传该目录名）。
- **被否**：URL 编码/双下划线转义（仍有长度、大小写与保留名问题，且要 decode 才能还原）；只 sanitize 不哈希（碰撞不可检测）；维护一份全局 repo 注册表（并发写入与原子性更复杂）。

## D38 — `doc_path` 规则：URL 全路径 + query 哈希，本地路径统一归一

- **背景**：旧实现取 URL 最后一段，`https://host/a/index.html` 与 `https://host/b/index.html` 都变成 `index.html`，后索引的文档覆盖前一个；`toc` 直接用原始路径（Windows 下含 `\`），与 `index`/`search` 得到的 section id 不一致。
- **决策**：
  - `doc_path_for_url(url)`：取 URL pathname，去掉首尾 `/`；为空时用 `index`；无 query/fragment 时追加 `.md`；有 query/fragment 时追加 `-<sha256(完整URL)[0:8]>.md`；解析失败回退 `index.md`，保证不会写出 repo 目录。
  - `normalize_local_path(path)`：`\` → `/`，去掉重复前导 `./`，折叠连续 `/`，保留前导 `/`（绝对路径仍是绝对路径）。
  - CLI 与 MCP 的 `index` / `toc` / `index_local` 全部走这两个函数，不再各自实现。
- **后果**：同 host 不同路径不再互相覆盖；同路径不同 query 的页面也能区分；`/README.md` 会得到 `README.md.md`（规则恒定追加），同一 URL 的不同拼写会得到不同文件名。section id 在 CLI、MCP、`toc` 之间一致。
- **被否**：只取 pathname（query 页面仍碰撞）；把 URL 编码后的完整路径当 `doc_path`（索引里不可读，仍要处理 `..` 与长度）；直接使用完整 URL（`:`、`?` 等字符对文件系统不友好）。

## D39 — MCP 响应 `max_bytes` 截断

- **背景**：`get_section` / `get_section_context` 返回整节 Markdown，长文档的一节可达数百 KB，直接塞进模型上下文会挤爆；客户端也无法预知响应大小。
- **决策**：两个工具 schema 新增 `max_bytes`（integer，默认 8000，`0`/`-1` 表示不截断）；Markdown 经 `truncate_utf8` 按 UTF-8 码点边界截断；响应新增 `truncated: Bool` 与 `total_bytes: Int32`（截断前 UTF-8 字节数）；`verified` 仍按截断前的完整 section 计算。
- **后果**：默认响应有上限，客户端可按需调大；截断不会劈开多字节字符；客户端可据 `truncated`/`total_bytes` 决定是否用更大 `max_bytes` 重取（v1 没有 offset 分页）。旧客户端忽略新字段不受影响。
- **被否**：服务端固定 8KB 硬截断（无法取全文）；按字符/字节硬切（可能产生无效 UTF-8）；响应分页（需要 cursor 状态，v1 复杂度不划算）。

## D40 — fetch 缓存 TTL + 可读缓存 + 有限重试

- **背景**：P1 只写 `.bin` + `.meta`，命中时无法还原 status/content_type；每次 fetch 都重新触网；瞬时网络错误直接失败；TTL 若用 `@async.now()`（单调时钟）对比文件 mtime（epoch）会永远失配。
- **决策**：
  - `FetchOptions += cache_ttl_ms`（默认 86,400,000 = 24h）与 `max_retries`（默认 2）；CLI 新增 `--cache-ttl MS`、`--retries N`。
  - `load_cached(root, key, ttl_ms)` 返回 `CachedEntry{body, status, content_type}`；TTL 用 `@env.now()`（epoch）对比 `.bin` 的 mtime；`ttl_ms <= 0` 表示永不新鲜（只写不读）；meta 缺字段回退 `200`/`""`，无 meta 视为未命中；损坏条目抛 `CacheError`，fetch 侧按未命中处理。
  - 缓存命中时 `platform` / `charset_warning` 由 body 重算，`from_cache = true`；命中仍受当前 `max_bytes` 限制，条目过大按未命中走网络。
  - 只有 `NetworkError` 可重试（`is_retryable`），线性退避 `200ms * attempt`；整个重试预算仍在 `with_timeout` 内。
- **后果**：重复 fetch 不再触网，瞬时抖动可自愈；TTL 以文件系统时钟为准，跨进程/重启有效。已知限制：命中时不重放重定向链，`final_url` 报告请求 URL（meta 仍保存真实值）；缓存命中同样返回 4xx/5xx，与网络路径语义一致。
- **被否**：不读缓存（重复抓取慢且对站点不友好）；用进程内 `now()` 做 TTL（跨进程失效且与 mtime 不可比）；对所有错误重试（超时/策略拒绝重试只会翻倍延迟）。

## D41 — frontmatter 跳过与围栏感知的空白压缩

- **背景**：YAML frontmatter 里 `key: value` 行的下一行就是 closing `---`，setext 规则把它误判成 H2，frontmatter 内容泄漏成一节；Markdown 转换的全局空白压缩会把 `<pre>`/围栏代码块里的连续空行压掉，破坏代码可读性与黄金文件。
- **决策**：
  - `split_document`：首行（允许 U+FEFF 前缀，trim 后）为 `---` 时，向下找第一个 trim 后为 `---` 或 `...` 的行作为结束；标题扫描从下一行开始，跳过的字节归入 preamble；未闭合则退回普通文本（`scan_start = 0`）。
  - `squash_blank_lines` 改为行级：跟踪 ``` / ~~~ 围栏，围栏内逐行原样保留（含连续空行），围栏外连续空行压到最多 1 个；末尾保证单个 `\n`。
- **后果**：frontmatter 不再产出假标题，preamble + 正文的 `byte_start`/`byte_end` 仍连续覆盖全文；代码块内容保真（行级处理会把 CRLF 归一为 LF，与生成器输出一致）。以 `---` 开头且存在闭合行的普通文档会被当 frontmatter 跳过，属于可接受的语义变化。
- **被否**：引入完整 YAML 解析器（只为找块边界，依赖过重）；只跳过第一行（多行 frontmatter 仍泄漏）；用正则替换压空行（嵌套围栏与 `~~~` 容易误伤）。
---

## D42 — `extract_main` 必须显式处理"候选容器直接挂在 body 下"

- **背景**：docs-verifier 在 T5 手工复核时发现，`<body><article><h1>…</h1><p>≥25 字符</p></article></body>` 这类极简页面会让 `extract` / `markdown` 死循环（CPU 100%）。根因：候选的父节点就是 body 时，折叠循环向上走到 document 节点、删光 body 子节点，随后 unwrap 循环对 document 节点反复调用 `unwrap_node`（它是 no-op），永不终止。
- **决策**：① 候选父节点 == body 时直接返回 body（无需折叠）；② 折叠循环与 unwrap 循环都以 `document_root` 为终止边界；③ 补两条回归测试（浅层 article、body 级单段落）。
- **后果**：极简 HTML 立即返回；fixtures 与既有行为不变（全部 72 个测试通过）。
- **被否**：给循环加迭代上限 —— 只是把死循环变成静默截断，没消除根因。
---

## D43 — DNS rebinding 只做"二次解析"缓解，不宣称已修复

- **背景**：`check_target` 解析一次域名做私网校验，而 HTTP 客户端连接时会再解析一次；攻击者控制的 DNS 可以在这两次之间把答案切到私网（TOCTOU）。当前 `@socket` 只提供单地址 `Addr::resolve`，也没有"按 IP 连接 + 保留 Host"的客户端 API，无法彻底钉住地址。
- **决策**：在请求前再做一次解析，若第二次已是私网则直接 `Blocked`；不要求两次结果相同（CDN 轮询会误杀）。
- **后果**：窗口变窄但没有消失；文档与 p7 的已知差距如实标注为"缓解"。彻底修复需要自建 HTTP 客户端或上游暴露 pinned-IP 连接。
- **被否**：要求两次解析结果完全相等 —— 会破坏正常的多 A 记录站点。

## D44 — MCP 索引写入用共享 Mutex 串行化

- **背景**：HTTP 传输按请求并发执行，而 `build_index` 是"读索引 → 合并 → 写回"，两个并发 `index_url`/`index_local` 会互相覆盖（实测：无锁时 3/3 丢失一篇文档）。
- **决策**：`build_server` 里创建一个 `Array[Mutex]`（数组是引用类型，保证闭包共享同一把锁），`index_url`/`index_local`/`delete_index` 三个写路径 `acquire` + `defer release`。
- **后果**：并发索引正确；读路径（search/get_section）不加锁，保持并发。锁粒度是"整个索引写操作"，对单机场景足够。
- **被否**：每个 repo 一把锁 —— 需要引用计数与生命周期管理，收益不足以抵消复杂度。
---

## D45 — 响应体按 WHATWG charset 解码，不再一律 lossy UTF-8

- **背景**：P9 审计遗留：GBK/Big5/Shift_JIS 页面被 `decode_lossy` 当 UTF-8 解，索引里存的是乱码，`charset_warning` 只是贴了个标签。
- **决策**：新增依赖 `LL728/moon_encoding@0.2.0`（WHATWG Encoding Standard 全 40 种编码，Apache-2.0）；从 `Content-Type` 的 `charset=`（支持引号）或前 1 KiB 的 `<meta charset>` 嗅探标签，命中非 UTF-8 时真正转码；标签未知/转码失败才回退 lossy 并置 `charset_warning=true`。
- **后果**：中文 GBK 站点可正确入库；新增依赖与 4 个单测（GBK 头、meta 嗅探、未知标签、带引号标签）。
- **被否**：只检测不转码 —— 等于把乱码写进索引；自写 GBK 表 —— 数据量大且易错。

## D46 — 缓存命中保留真实 final_url

- **背景**：缓存 meta 里存了 `final_url`，但命中时 `FetchResult.final_url` 回填的是请求 URL，重定向过的页面从缓存读时平台指纹与路径会偏。
- **决策**：`CachedEntry` 增加 `final_url`；命中时优先用 meta 值，并据此重建 `Target` 计算平台指纹。
- **后果**：缓存命中的结果与网络路径一致；`from_cache` 语义不变。
- **被否**：缓存只存 body —— 无法还原重定向后的身份。

## D47 — JSON 派生改为显式 `extend`，消除隐式方法提升

- **背景**：`derive(ToJson, FromJson)` 会触发 `implicit_impl_as_method` 警告，工具链明确指出该行为未来会移除；升级后会直接编译失败。
- **决策**：保留 derive，同时显式声明 `pub extend Section with ToJson::{to_json}` 等 4 条 extend。
- **后果**：`moon check` 的 derive 警告从 4 条降到 0；行为不变（73 个测试含索引 JSON 往返）。
- **被否**：手写 `to_json/from_json` —— 与派生逻辑重复，字段一改就漂移。
---

## D48 — 纯文本工具抽成零依赖包 `core/text`

- **背景**：`find_sub` / `split_lines` / `json_escape` / `truncate_utf8` 原本散在 `http` 里。`http` 同时依赖 `async`/`url`/`sha256`/`moon_encoding`，所以只想要一个字符串函数的包（`md`、`mcp`）宁可自己再实现一遍，也不愿把整套传输栈拖进来——于是出现 3 处重复实现。
- **决策**：新建零依赖包 `core/text`，只放纯函数（子串查找、分行、JSON 转义、UTF-8 安全截断），`extract` / `md` / `index` / `mcp` / `cmd` 与 `http` 本身共用它。
- **后果**：删掉 3 份重复扫描；`mcp` 对 `http` 的依赖只剩真正的传输需求；`core/text` 有 9 个独立单测。
- **被否**：让 `md` 直接依赖 `http` —— 会把 async 运行时、TLS、URL 解析拖进一个纯转换包，编译产物与理解成本都上升。

## D49 — MCP 工具改为"一个工具一个注册函数"

- **背景**：`build_server` 曾是一个 264 行的函数，8 个工具的 schema、参数解析、业务调用、错误包装全内联。加第 9 个工具只会让它更长，且无法单独阅读某个工具的契约。
- **决策**：拆成 `register_<tool>(server, root[, gate])`，只读工具放 `tools_read.mbt`，写工具放 `tools_write.mbt`（写工具额外收共享 `gate` 互斥锁）；`build_server` 只保留 15 行组装。
- **后果**：新增工具 = 一个函数 + 一行注册；工具契约可单独阅读；`server.mbt` 从 414 行降到 171 行（其中 150 行是共享助手）。
- **被否**：用表驱动（把 8 个工具塞进一个数组循环注册）——闭包类型各异，会引入大量动态派发，可读性反而更差。
---

## D50 — 默认检索改为 BM25，旧加权打分保留为可选模式

- **背景**：旧打分是整数加法（标题 +20/+10/+5、路径 +2、正文词 +1 封顶 5），没有词频、没有逆文档频率、没有长度归一化。实测同一查询下前两名常并列（6/6/1/1），无法区分。
- **决策**：默认走 BM25（`k1=1.2`、`b=0.75`，字段权重 title 3 / path 2 / body 1）；词频在分节时算好存进索引（`terms` 重复展开 + `tokens`），检索时只读元数据。旧打分保留为 `SearchMode::Weighted`，CLI `--mode`、MCP `search_sections.mode` 可切换。索引版本 2 → 3。
- **后果**：得分有梯度（89/87/63/63），稀有词自动获得更高权重；索引体积略增（readability 6.8 KB → 约 9 KB）；旧索引需重建（fail-closed 已保证）。
- **被否**：引入倒排表/posting cache —— 千级小节内查询仍是毫秒级，收益不足以抵消新数据结构与失效逻辑；也否掉了纯 embedding 方案（违背「零外部服务」定位）。