# MoonBit 黑客松选题短名单（2026 十一月赛）

> 配套主报告：[`moonbit-competitions-2026.md`](./moonbit-competitions-2026.md)
> 筛选原则来自官方口径：「优先选择边界清晰、能够在一个月内交付并验证的项目。」（[赛事官网](https://moonbitlang.github.io/Hackathon2026/)）

---

## 1. 官方推荐项目方向（来自 2026 SCC 推荐清单）

赛事组在 [2026 软件合成挑战赛推荐项目清单](https://www.moonbitlang.cn/files/2026-scc/2026%20%E8%BD%AF%E4%BB%B6%E5%90%88%E6%88%90%E6%8C%91%E6%88%98%E8%B5%9B%E6%8E%A8%E8%8D%90%E9%A1%B9%E7%9B%AE%E5%85%B7%E4%BD%93%E6%B8%85%E5%8D%95.pdf)（`sources/scc-2026-recommended-topics.pdf`，5 页）中给了 12 个方向：

| # | 方向 | 参考项目 |
| --- | --- | --- |
| 1 | 跨平台 2D 图形绘制库 | Skia、TGFX、Cairo |
| 2 | 跨平台动画绘制库 | Lottie、dotLottie、Rive、Ruffle |
| 3 | 通用文件格式转换库（PDF/Excel/Doc → Markdown） | MarkItDown |
| 4 | 游戏图形处理库（raylib 绑定） | raylib |
| 5 | 游戏引擎 MoonBit 绑定（GDExtension） | Godot 4、Unreal |
| 6 | 通用图表编辑器（Web + wasm） | Excalidraw、draw.io |
| 7 | 代码编辑组件（高亮/历史/搜索） | CodeMirror、Monaco |
| 8 | 桌面开发框架 | Electron、Tauri |
| 9 | 软件开发管理软件（Git + 工单 + MR） | Forgejo、GitLab |
| 10 | 定理证明器 | HOL Light |
| 11 | 语法解析器（增量、错误恢复、Grammar DSL、WASM 分发） | tree-sitter |
| 12 | 中大型电子游戏 | — |

> 这份清单是 **SCC** 的推荐清单，不是十一月赛的强制要求；但对「什么算系统型软件」有参考价值。

---

## 2. 生态现状核对（避免重新发明轮子）

基于本机 MoonCakes 索引（3,457 个包）实测：

| 领域 | 已有包 | 对本选题的影响 |
| --- | --- | --- |
| 快照/黄金测试 | 未发现 snapshot / golden / approval / insta 类包 | ✅ 空白，可做 |
| 文档解析 | `moonbitlang/pdflite` 0.4.1、`moonbitlang/docx2html` 0.7.1、`moonbitlang/mbtexcel` 0.3.1 | ⚠️ 底层已有，**不要重写解析器**，做上层统一 |
| PDF→MD | `pdf2md`、`pdflite` | ⚠️ 同上 |
| SQL 引擎 | `uiwcvb/moonsql`（纯 MoonBit 嵌入式关系引擎）、`sqlite` 绑定系列 | ⚠️ 重叠明显，需强差异化 |
| MoonBit 语法 | `tonyfettes/tree_sitter_moonbit`（官方 grammar）、`tree_sitter_moonbit_quotation` | ✅ 可直接复用来做分析工具 |
| Lint / 静态分析 | 未发现可扩展的 MoonBit lint 规则引擎 | ✅ 空白，可做 |
| tree-sitter 生态 | `tree-sitter` + 20+ 语言 grammar | ⚠️ 官方 #11 已有大量移植 |
| MCP | `marianoguerra/mcp`、`mcp-server`、`mcp-sdk`、`mcp-client` | ⚠️ 已较拥挤 |
| 电子表格/公式 | `bobzhang/spreadsheet`、`FrozenLemonTee/formulas-calculator` | ⚠️ 重叠 |
| 图表/SVG/图编辑 | `svg`、`diagrams-*`、`moonbit-chart` 系列 | ⚠️ 重叠 |
| Protobuf | `moonbitlang/protobuf` 0.2.0 + `protoc-gen-mbt` | ⚠️ 已有官方实现 |

**结论**：能"从零造一个大家都缺的大件"的空间已经不大；评审更看重的是 **工程边界、测试质量、可维护性、真实可用**（官方原话），所以「在薄弱处做深」比「造新轮子」更稳。

---

## 3. 候选 A：`moon-snap` —— MoonBit 快照测试工具

| 项 | 内容 |
| --- | --- |
| 方向 | 开发者工具 |
| 一句话 | 给 MoonBit 加内联快照/黄金测试：一行断言记录输出，失败时给人看的 diff，`--update` 一键更新 |
| 为什么值得做 | 生态里没有 insta/golden 类包；而黑客松的评审维度里「测试覆盖/工程质量」占很高权重，工具自己就是卖点 |
| MVP 范围 | `snap_eq` / `snap_str` API、可读快照文件格式、diff 渲染（行级 + 字符级）、`MOON_SNAP_UPDATE=1` 更新、CI 只读模式、并发安全、`moon test` 下工作目录约定 |
| 明确不做 | 不做宏改造编译器、不做 IDE 插件、不做快照云端服务 |
| 复用 | `moonbitlang/core` 标准库（文件读写、格式化）；`moonbitlang/x` |
| 4 周分解 | W1 存储格式 + 断言 API；W2 diff 渲染 + 更新模式；W3 并发/路径/CI 边界 + 自举测试；W4 文档、示例、真实项目接入验证 |
| 验收演示 | 在仓库里对一个真实 MoonBit 项目跑 `moon test` → 故意改输出 → 展示 diff → `--update` 后全绿 |
| 风险 | 与 `moon test` 进程模型/工作目录的配合（先用环境变量与相对路径规避） |
| 差异化 | 空白领域，几乎无竞争者 |

## 4. 候选 B：`docmunch` —— 文档 → Markdown 统一转换与分块库

| 项 | 内容 |
| --- | --- |
| 方向 | 数据处理 / AI 应用（对应官方清单 #3） |
| 一句话 | 把 PDF / DOCX / XLSX 转成「带来源定位的 Markdown」，并直接可切成 RAG 友好的 chunk |
| 为什么值得做 | 官方点名的方向；AI 时代最真实的文档预处理需求；底层解析包已成熟，投入产出比高 |
| MVP 范围 | 统一 Document IR（段落/标题/列表/表格/图片/页码锚点）→ Markdown 输出；`--source-map` 让每段可回溯到原页/单元格；`chunk` 子命令输出带 metadata 的 JSONL；CLI 一条命令跑通 |
| 明确不做 | 不重写 PDF/DOCX/XLSX 解析器（直接依赖官方包）；不做 OCR；不做在线服务 |
| 复用 | `moonbitlang/pdflite`、`moonbitlang/docx2html`、`moonbitlang/mbtexcel`、`moonbitlang/ooxml`、`moonbit-community/flate` |
| 4 周分解 | W1 IR + DOCX/XLSX 通路 + 黄金文件测试；W2 PDF 通路 + 表格保真；W3 source map + chunking；W4 CLI/文档/评测集与对比报告 |
| 验收演示 | 仓库带 10+ 个样例文件，`moon run cli -- sample.docx -o out.md` 一键生成；`moon test` 用黄金文件比对 |
| 风险 | ① PDF 文本层提取（CJK 断行、双栏）② 依赖包 API 仍在 0.x 变动 ③ 容易做成"胶水"，必须用 IR + source map + chunk 证明深度 |
| 差异化 | 不是再造解析器，而是统一 IR 与来源定位——正是现有三个包都缺的那一层 |

## 5. 候选 C：`moonlint` —— 可扩展的 MoonBit 静态分析/规则引擎

| 项 | 内容 |
| --- | --- |
| 方向 | 开发者工具（软件分析框架） |
| 一句话 | 基于 `tree_sitter_moonbit` 的可扩展 lint 引擎：规则插件化、输出 JSON 诊断、可接入 CI |
| 为什么值得做 | 生态里有语法树但**没有规则引擎**；静态分析是"系统型软件"的典型形态 |
| MVP 范围 | 解析 MoonBit 源码 → AST 遍历框架 → 8–12 条真实规则（未使用变量、过深嵌套、`unwrap` 滥用、命名一致性、文档缺失…）→ `--format json|sarif` → 规则配置与 suppress 注释 |
| 明确不做 | 不做类型检查（交给 moonc）、不做自动修复的完整实现、不做 LSP 服务 |
| 复用 | `tonyfettes/tree_sitter_moonbit`、`moonbitlang/core/json` |
| 4 周分解 | W1 语法树接入 + 规则框架；W2 6 条规则 + 测试；W3 输出格式 + 配置 + 性能；W4 真实仓库试跑 + 文档 + 报告 |
| 验收演示 | 对 moonbitlang/core 或本仓库跑一遍，输出诊断与统计；规则写错的用例会被测试抓住 |
| 风险 | ① tree-sitter 绑定是 C 代码，跨后端（wasm/native）可能踩坑 ② 规则质量决定观感 |
| 差异化 | 不做语法树（已有），做「规则 + 工程化」，与官方 #11 不撞车 |

## 6. 候选 D：`moonquery` —— 面向 CSV/JSON 的列式分析引擎

| 项 | 内容 |
| --- | --- |
| 方向 | 数据处理（数据库内核） |
| 一句话 | 对 CSV/JSON 文件直接跑 SQL 子集：列式内存布局 + 向量化聚合 + CLI |
| 为什么值得做 | 工程纵深最大，最能体现"系统型软件"；end-to-end 演示直观 |
| MVP 范围 | SQL 子集（SELECT / WHERE / GROUP BY / HAVING / ORDER BY / LIMIT / 基础 JOIN）+ 聚合函数 + 类型推断 + `EXPLAIN` + 基准数据 |
| 明确不做 | 不做事务/索引/并发写、不做完整 SQL 标准、不做分布式 |
| 复用 | `moonbitlang/core/json`、`csv` 解析包、`moonbitlang/async`（大文件流式读） |
| 4 周分解 | W1 词法/语法 + AST；W2 绑定与类型推断 + 表达式求值；W3 列式执行 + 聚合/排序/连接；W4 CLI、基准、文档 |
| 风险 | **已存在 `uiwcvb/moonsql`（纯 MoonBit 嵌入式关系引擎）**，容易被评审认为重复；必须用「列式 + 分析型 + 文件直查」讲清差异，否则不建议选 |
| 差异化 | 行式嵌入式引擎 vs 列式分析引擎，目标场景不同；但差异化说服成本高 |

---

## 7. 评分矩阵（1–5 分，5 最好）

| 维度 | A 快照测试 | B 文档转换 | C Lint 引擎 | D 列式 SQL |
| --- | --- | --- | --- | --- |
| 一个月可交付 | 5 | 4 | 4 | 3 |
| 工程纵深 | 3 | 4 | 4 | 5 |
| 测试可自动化 | 5 | 4 | 4 | 4 |
| 演示效果 | 3 | 5 | 4 | 4 |
| 生态差异化 | 5 | 4 | 4 | 2 |
| 依赖风险（越高越稳） | 5 | 3 | 3 | 4 |
| **合计** | **26** | **24** | **23** | **22** |

## 8. 推荐顺序

1. **首选 B（docmunch）**：官方清单 #3 直接命中，「真实需求 + 演示直观 + 复用成熟底层」三点都占；只要把 IR/source map/chunk 做扎实，就不会被认为只是胶水。
2. **稳妥备选 A（moon-snap）**：空白领域、几乎无依赖风险，拿"完成支持 + 通过验收"最稳；缺点是系统纵深弱一档。
3. **冲季度奖选 C（moonlint）**：题材新颖、工程化程度高，但 tree-sitter 绑定有踩坑概率。
4. **不建议 D**：与 `moonsql` 正面重叠，解释成本高于收益。

> 最终选题由你拍板。若你更想在自己熟悉的方向上投入（例如你已经用过某类库），"熟悉度"应当压过上面的排序。

## 9. 决策清单（选之前先回答这 6 个问题）

1. 有没有一个**你会在自己项目里真的用**的场景？（评审会问"谁需要它"）
2. 一个月后**能演示的最强 90 秒**是什么？（能不能一句话说清）
3. 核心难点是否**可控**？（依赖包是否稳定、是否有已知方案）
4. 测试能不能**自动跑**？（黄金文件/快照/基准）
5. 和现有包相比，你的**差异化**能不能在 README 第一屏讲清？
6. 开发历程文章（可解释性）有没有**真实素材**？（取舍、踩坑、AI 怎么用）

## 10. 四周通用节奏模板

| 周 | 目标 | 产出 |
| --- | --- | --- |
| W1 | 打通最小闭环 | CLI 能跑、测试骨架、README quickstart、首个 commit 在报名当天 |
| W2 | 核心功能 | 主路径实现 + 单元测试 |
| W3 | 工程质量 | 错误处理、边界、集成测试、CI |
| W4 | 可解释性 | 文档、示例、开发历程文章、验收演示脚本 |

> 官方验收要求「可复现」：同一输入多次运行结果一致。涉及随机/并发的部分要显式固定种子或排序。
