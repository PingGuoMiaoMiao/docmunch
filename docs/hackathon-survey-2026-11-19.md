# 黑客松第二轮调研（2026-11-19）

> 前置文档：[moonbit-competitions-2026.md](moonbit-competitions-2026.md)、[topic-shortlist.md](topic-shortlist.md)。
> 本篇记录 11-19 实测到的新信息：赛制更新、季度评分准则首次公开、优秀项目样本、生态占位复核、选题结论。
> 来源正文为外部内容，按未受信数据处理：所有关键条款以官网/群通知为准，聚合站信息单独标注。

## 1. 赛制现状（相对 11-07 调研的变化）

1. **赛事全名**：2026 MoonBit 国产基础软件生态开源大赛 · 11 月黑客松（Q2 赛季 = 11/12/1 月三个月，同一池评选）。
2. **本月关键日期**（聚合站口径：seiguan、lianpu 均写 投稿/验收截止 **2026-11-30**；官网 App.tsx 正文仍写「以官方通知为准」——**以微信群公告为最终确认**）。
3. **双赛道**：赛道一 = 当月新项目（月度 150+350 支持 → 验收后进季度池）；赛道二 = 已有社区项目维护（直接报季度评选）。两条路径汇入同一季度评选池。
4. **个人单月最多可申报 3 个项目**（聚合站口径，官网正文未写；报名时确认）。团队 ≤3 人不变。
5. **Q1（8–10 月）季度评选时间线**（官网正文，11-19 抓到）：11-18 线上统一评审、公布三等奖；同日公布一、二等奖候选；**11-28 深圳现场终评**（上午 MoonBit 1.0 技术分享，下午现场决出一、二等奖）。
   → 可合理预期 Q2 赛季也有一月/二月左右的线下终评环节；晋级需预留差旅时间。
6. **季度评分准则首次公开**（官网正文，四项 × 25 分，按 一般/良好/优秀 三档）：
   | 维度 | 「优秀」要求（摘要） |
   | --- | --- |
   | 01 工程深度与实现强度 | 核心成果完整且强度足够，关键场景得到验证，范围变化和未完成事项交代清楚 |
   | 02 技术贡献与攻关 | 解决了实质性难题，对约束/取舍/边界有深入掌握，形成高质量 MoonBit 原生设计或技术突破；移植项目能完整移植功能 |
   | 03 生态增量 | 用**数据、场景、采用或独立验证**证明显著改进，为 MoonBit 带来重要新能力/平台适配/广泛复用价值；「缺少外部基线」判为一般 |
   | 04 开发与验证能力 | 稳定可重复的任务拆解与验证闭环：Harness、回归、基准、自动化、AI 校验，并能展示其实际发现和防止错误的效果 |
   —— 这份准则就是对「什么算优秀项目」的官方回答；docmunch 的 conformance kit / 盲测 / 成本实测正是 04 的满分动作，03 是它被初审点名的短板。

## 2. 优秀项目样本（这段时间被官方/社区点名的）

**SCC 2026 展示墙**（<https://www.moonbitlang.cn/2026-scc/showcase/>，19 个项目，从页面内嵌数据实测提取）：
magpiedb（DB 内核）、QED（kernel-first 定理证明器，MoonBit+Lean）、MoonBitMark / markitdown（多格式文档→Markdown，CLI+MCP）、morm（ORM+代码生成）、MoonBash（MoonBit→JS POSIX shell）、moon-lottie（原生 Lottie 播放器，带在线 demo）、enimate（跨平台 2D 动画）、FlowLabLite（Dify/Coze 式 agent 编排）、cogna（多智能体 CLI 调度）、MetaEditor、moonbook（浏览器本地文档问答）、MoonPalace、moonflow、kwiver、moon_rv_lab（RISC-V 工具链实验）、qt.mbt（Qt 绑定）、yuecharts（Quiver 图表编辑器重实现）、MoonECAT（EtherCAT 主站）、MoonSEO、moonink、MoonAP、AstrClaw、MoonForge、MoonParse、alpha、reisen、Mengxi（视觉小说引擎）、MoonMarkMind。

**Code JAM 2025 / MGPIC**（游戏向，另一体系）：一等奖 Matchstick-Man-Battle、《赛博拾荒者》（月度最佳视觉+总决赛季军）、《水墨之灵》、铜偶戏等。

**社区高频动态**：3520 个模块按场景索引（掘金，11-02）：37 场景 / 71 个「完整方案」/ **22 个场景无框架级实现**（图形渲染、图像编解码、音视频、HTTP 客户端、网络传输、协议与 RPC、JSON、二进制编码、日志与追踪、文件与路径、数学与数值、数据结构算法、开发工具、Markdown 与文档转换、时间日期、Unicode、哈希、加密、编码转义、压缩归档、编译器与代码生成、正则）。Luna-Flow 线（Luna-Plot/calculus/quaternion）、moonbitlang-spectrum（GLSL）、web_component、moonbot（响应式）、ERIS。

**获奖项目的共同模式**（对照评分准则）：①系统型内核或高完成度移植（01/02）；②有可独立运行的 demo/在线站点（03 的「场景」）；③真实上游/标准作外部基线，RFC 与版本号写进 README（03）；④自己的验证闭环和数字（04）；⑤明确「不做什么」。

## 3. 生态占位复核（本地 registry 索引，代际 ≈11-10）

11-07 调研里几个候选，现在实测**已不再是空白**：

| 候选方向 | 现状 | 结论 |
| --- | --- | --- |
| 快照测试库 | `moon test -u` 内建 expect-test 快照更新（本机 moon 0.1.20261028 实测 help） | ❌ **A（moon-snap）取消**，官方已覆盖 |
| 正则 | 官方 `moonbitlang/regexp` 0.3.7（被 moon_zod 等大量依赖） | ❌ 空白不成立 |
| API 兼容性/semver 守卫 | `404-32/mooncompat`（11-06）、`918154429/moonguard`（07-12） | ❌ 已有人做，差异化成本高 |
| 压缩/归档 | `moonbitstack/moonzip`（11-04/06/09 连发，宣称 zip/gzip/zstd/brotli/lzma/tar/7z）、bobzhang/tar、gmlewis/gzip、community/zipc | ⚠️ 名义占位密集，质量存疑但别再正面撞 |
| YAML/PNG/JPEG/Markdown/PDF/GraphQL/ONNX/日历 | 每个方向 ≥4–12 个包（实测列表见附录脚本输出） | ❌ 通用「空白库」选题基本关门 |
| 基准/harness | `Han-Wentao/moonbench` 存在；统计回归门禁方向未细查 | ⚠️ 需先读它的深度再谈差异化 |
| **可扩展 lint/静态分析** | ❌ **四层占用**（当日补核，推翻本文件前稿结论）：①官方出品 `moonlint`（NSlash951/myfreess，基于官方自举 `moonbitlang/parser` 做错误恢复，[社区周报 weekly12](https://moonbit.community/weekly/weekly12/projects.html) 与 [Meetup 深圳站回顾](https://www.oschina.net/comment/news/380002) 均有记载）；②`riantr/moonbit_static_analysis`（10-03 首发、11-09 已到 v0.4.45 高频迭代，结构/类型/行为三镜头，覆盖 .mbt/.mbtx/.mbti/.mbt.md/.mbtp，并已对 moonbitlang/core 跑 undefined-name 统计）；③`moonbit-community/moongrep`（结构化搜索 + taint 分析 + lint，YAML 规则，被官方 moonx/openseek 直接内置，见 openseek 仓库 `share/moongrep/README.md`）；④`mizchi/starlint`（规则 + `--fix` + 配置 + baseline） | ❌ **候选 C 否决，与官方同名，不可作** |

同时确认：**文档→Markdown / 文档问答方向已被正面占用**（MoonBitMark、markitdown、moonbook、FlowLabLite 都在展示墙上）——docmunch 的申报差异化（检索+可验证性，而非转换）是对的，回执里「撤回质量主张、只主张可验证性」的口径要继续守住。

## 4. 选题结论（2026-11-19）

1. **本季度先不新开大坑**：docmunch 已报名、已过初审质疑、8 PASS（`tools/acceptance.py`），11-30 验收窗口只剩 11 天；且 **H1 半年度评选（8 月–1 月）即将到来**，docmunch 进 H1 池的价值（季度 12k + 半年度 24k 可叠加）大于一个仓促的十二月新项目。
2. **同日补核后撤回「moonlint 作首选」**（§3 表最后一行：官方同名工具 + 三层独立竞品，且其中两个仍在活跃迭代）。由此修正方法论：**「registry 找空白」在本届不再是可靠的选题函数**——个人单月可报 3 项、同期参赛包 10 天内就能填掉一个"空白"；SCC 展示墙 19 个获奖项目的共同点也不是「生态第一个做」，而是「该方向完成度最强 + 外部基线 + 可验证数字」（magpiedb 并非 MoonBit 第一个数据库，QED 也不是第一个形式化尝试）。
3. 修正后的新项目策略（十二月赛，同属 Q2 池）：**不做独立新题材，给 docmunch 做引擎级实质新增**（走赛道一 12 月申报或赛道二社区项目均可）。三个新增点逐一对应初审点名的维度：
   - **倒排索引 + postings 列表**替换 BM25 全量扫描——回执里自己承认的遗留短板（「检索仍未优化，约 249 ms/5,980 节」）→ 01 工程深度 + 02 攻关；新旧同机对比即内部基线，cost_model.py / cache_bench.py 两个 harness 已备；
   - **采用与独立验证**：2–3 个赛事项目真实接入 docmunch MCP（记录 issue/PR/版本号），或对真实文档站做可复跑 recall 对比 → 03（准则原话「数据、场景、采用或独立验证」）；
   - **中英文混合检索评测**：CJK bigram 已有，补中文语料 + rank_bm25/jieba 真实组件对照 → 02/03。
   若坚持另起炉灶，只剩「重型系统级」一条路（对照 SCC 获奖形态：数据库内核/定理证明器/动画引擎/agent 平台级），候选如列式分析引擎、PDF 写出端、raylib/GDExtension 完整移植——每个都需先做一轮本文 §3 式的占位复核再立项，不推荐本月拍板。
3. 无论选什么，把「外部基线」当第一页写：真实第三方组件对比 + RFC/spec 编号 + 采用记录，这是本季评审准则第 03 条明写的判优方式。

## 5. 本周围绕 docmunch 的收尾清单（11-30 前）

- [ ] `docs/reply-to-committee.md` 定稿并发出（邮件+飞书口径一致），仓库 push 到 `d52d709` 之后无本地未提交差异
- [ ] `python tools/acceptance.py --since 2026-11-01` 出 8 PASS 截图/输出，作为验收附件
- [ ] 飞书报名表用修正后的一页纸覆盖；群昵称 = GitHub ID（PingGuoMiaoMiao）
- [ ] 准备 90 秒复现脚本（README quickstart 命令序列录屏）
- [ ] 盯微信群 Q2 评选/线下终评通知（参照 Q1：11-28 深圳的节奏，预留 1–2 月出差可能）

## 附：占位核查方法（可复跑）

```powershell
# 本机 registry 索引（moon 0.1.20261028 代际 ≈ 2026-11-10）
& "$env:USERPROFILE\.moon\bin\moon.exe" test --help   # 确认 -u/--update 内建快照
# 按关键词聚合 index/*.index 的 name 字段（见正文表格）
```
SCC 展示墙数据提取：`https://www.moonbitlang.cn/rabbita-2026-scc-showcase/main.js` 内嵌卡片数组（本仓库 `research/rabbita_showcase_main.js` 为快照）。
