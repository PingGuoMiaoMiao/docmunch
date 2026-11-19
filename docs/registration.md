# 报名信息（可直接粘贴到飞书表单）

> 用途：MoonBit 黑客松月度赛报名表。下面两段分别是「字段速填」与「一页项目说明」，
> 表单里要求填仓库地址和一页说明时可以直接复制。
> 提交前请把 `【】` 里的内容换成你自己的；其余字段已按仓库当前状态填好。

---

## 一、字段速填

| 表单字段 | 填写内容 |
| --- | --- |
| 项目名称 | docmunch |
| 参赛者 | PingGuoMiaoMiao |
| 联系方式 | 3226742838@qq.com |
| GitHub 仓库 | https://github.com/PingGuoMiaoMiao/docmunch |
| 项目方向 | MoonBit 开发者工具 / AI 文档基础设施 |
| 是否为移植项目 | 否（独立实现，无上游代码可移植） |
| 组队人数 | 1 人（如需组队请改成实际人数并确认队员 GitHub ID） |
| 推荐人 GitHub ID | 【有就填，没有留空】 |
| MoonCakes 包 | https://mooncakes.io/docs/PingGuoMiaoMiao/docmunch （registry 最新是 **0.3.1**，与仓库一致） |

---

## 二、一页项目说明（可直接粘贴）

### docmunch：面向 AI 代理的按节检索式文档基础设施

**问题**：把整篇文档塞进模型上下文既贵又降质——一篇 10 万字的手册约 4 万 token，
还常被截断。

**做法**：docmunch 把文档按标题层级切成节，为每节记录在原文中的 **UTF-8 字节区间**
与 **sha256**。AI 代理可以「先看目录 → 检索 → 只取需要的那一节」，取回是一次
`seek + read`，不重新解析、不加载全文。整条链路用 MoonBit 实现，编译为单个原生二进制。

```
URL / 本地文件
  → 抓取（HTTPS、流式、重定向、SSRF 防护、charset 转码、缓存、重试）
  → 平台指纹（16 类，含 GitHub/GitLab 与通用兜底）
  → 正文抽取（Readability 兼容评分 + 链接密度裁剪）
  → HTML → CommonMark
  → 按标题分节（ATX/setext、感知代码围栏、跳过 frontmatter、字节偏移 + sha256）
  → 索引（元数据 JSON + 原文缓存 + 词频 + 关键词）
  → 检索（BM25 / 加权，可解释）与按字节区间取回
  → 通过 MCP 暴露给 Claude Code / Cursor 等客户端
```

**支持的输入**：Markdown、HTML、reStructuredText、Jupyter `.ipynb`、以及任意 http(s) URL。

**面向谁**：想把文档接入自有 Agent 的库作者、需要本地文档检索的工具开发者、
需要降低上下文成本的应用开发者。

**与常见方案的区别**：不是又一个 RAG 向量库。索引里**不存 embedding、不存正文**，
只有「标题树 + 字节偏移 + 词频」，因此可解释、可复现、零外部服务、零 API Key。
单篇文档的索引约 0.5 KB，原文另存。

**当前状态**（截至 2026-11-19）：

- 116 个测试全绿；GitHub Actions 每次 push 全绿；
- MoonCakes 已发布 `0.3.1`（另有 0.3.0 / 0.2.1 / 0.2.0），与仓库 `moon.mod` 一致——评审 `moon add` 拿到的就是当前版本；
- 抽取质量对齐 Mozilla Readability 做差分：4 个真实页面标题全中，平均长度比 1.03、词集 Jaccard 0.91；
- 分节正确性由独立脚本读磁盘字节验证（连续覆盖 / UTF-8 合法 / sha256 全等 / id 唯一）；
- MCP 13 个工具，支持 stdio 与 Streamable HTTP（可选 Bearer Token）；长驻进程下取回 0.5 ms、检索 10.2 ms（索引缓存 + 倒排索引）；
- 60+ 条 ADR 记录取舍与被否方案（含三次公开修正：D55 索引缓存、D56 撤回"标题切分是增量"、D57 回答质量只报能报的结论）。

**检索与成本（实测，非估算）**：

- 与真实第三方组件对照（LangChain `MarkdownHeaderTextSplitter` / `RecursiveCharacterTextSplitter` + `rank_bm25` + `tiktoken`）：
  在 18 个标注问题上，docmunch 的 hit@1(7/18) 与 LangChain 标题切分相同，hit@5(14/18 vs 15/18) 与整节完整性(13/18 vs 14/18) **各落后 1 题**——
  所以本项目**不主张"切得更好"，并如实承认略输**；
- 差异在**可验证性**：每节带指回原文的字节区间与 sha256，取回可自证，产物逐字节可复现，索引版本不匹配 fail-closed；
  这套要求已写成与实现无关的契约（`conformance/SPEC.md`）并提供检查器，任何实现都能接入；
- 端到端盲测（12 题、5 份文档、5 种上下文策略）：无上下文 0/12；整篇截断到 8000 token 时 3/12；
  整篇 / 定长切分 / 节级都是 12/12，而上下文成本分别是 20,275 / 17,117 / **13,064** token
  ——即**同等准确率下省 36% 上下文**，且整篇塞入在窗口受限时会失效。**不主张"更准"**。

**90 秒演示**：

```sh
moon build --target native

# 1. 抓取 + 抽取 + 分节 + 索引（一条命令）
moon run cmd/main --target native -- index https://docs.moonbitlang.cn/language/ffi.html

# 2. 检索（默认 BM25，中文亦可）
moon run cmd/main --target native -- search docs.moonbitlang.cn "ffi"

# 3. 按 id 取回某一节（哈希校验）
moon run cmd/main --target native -- section docs.moonbitlang.cn "<id from search>" --verify

# 4. 挂到 AI 客户端
moon run cmd/main --target native -- mcp
```

**仓库里可以看什么**：`README.md`（用法）、`docs/application-docmunch.md`（申报书全文）、
`docs/devlog.md`（开发历程与踩坑）、`docs/decisions.md`（60+ 条 ADR）、
`docs/pre-research.md`（生态调研与参考实现对照）。

---

## 三、提交前的自检

```sh
moon test                            # 116/116
python tools/acceptance.py --since 2026-11-01   # 8 PASS / 0 WARN / 0 FAIL
```

两条都过，说明「MoonBit 为主语言 / 公开仓库可追踪 / 可运行 / 实质新增 / OSI 许可 /
AI 可解释」这六条赛事要求都有据可依。

---

## 四、还需要你本人做的事

1. 加入赛事微信群，并把群昵称改成 **PingGuoMiaoMiao**（官方写明否则影响奖金发放）；
2. 在飞书表单里提交上面的仓库地址与一页说明（建议提交前先 `git push` 一次，确保最新）；
3. 如果想知道审核进度，直接问群里的赛事小助手（滚动审核，官方没有集中初审邮件）。
