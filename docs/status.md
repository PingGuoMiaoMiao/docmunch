# 当前状态快照（2026-11-20 实测）

> 用途：提交报名表/回复组委会时直接取数，不必从多份文档里拼接。
> 每一条都给出**取值方式**，所以过期了也能自己重算，而不是相信这份文档。
> 本文件是快照：数字属于 2026-11-20 14:45（UTC+8）。

## 关键事实

| 项 | 值 | 怎么取的 |
| --- | --- | --- |
| 仓库版本 | `0.3.1` | `moon.mod` 的 `version` |
| MoonCakes 已发布版本 | `0.2.0` / `0.2.1` / `0.3.0` / **`0.3.1`（最新，与仓库一致）** | `mooncakes.io/api/v0/manifest/PingGuoMiaoMiao/docmunch` |
| MoonCakes 下载 | 50 | 同上 `downloads` |
| 测试 | **116 / 116 全绿** | `moon test --target native` |
| 验收自检 | **8 PASS / 0 WARN / 0 FAIL** | `python tools/acceptance.py --since 2026-11-01` |
| 文档一致性 | **6 / 6 通过** | `python tools/consistency.py` |
| 提交数 | 见命令（每次提交都会变，不写死） | `git rev-list --count HEAD` |
| 最近提交 | 见命令 | `git log -1 --date=short` |
| GitHub Star / Fork / Issue | 1 / 0 / 0 | `gh api repos/PingGuoMiaoMiao/docmunch` |
| CI | 全绿（本提交） | `gh run list --limit 1` |


## 全新 clone 演练（2026-11-20 实测）

模拟评审：在空目录 `git clone`（152 个文件，无 `.mooncakes`、无 `_build`），
照文档逐条执行：

| 命令 | 退出码 | 结果 |
| --- | --- | --- |
| `moon test --target native` | 0 | **116/116**，17.6 s（含首次依赖下载） |
| `python tools/selfcheck.py` | 0 | 15 项：14 pass / 0 warn / 1 skip |
| `python tools/acceptance.py --skip-build` | 0 | 7 pass / 1 warn（WARN 是"跳过构建"的提示） |
| `python tools/consistency.py` | 0 | **7 ok / 0 fail** |
| `python tools/markdown_golden.py` | 0 | 黄金文件逐字节一致 |
| `python tools/toc_check.py` | 0 | 分节字节契约通过 |
| `python conformance/selftest.py` | 0 | 五种注入违规全部被检查器报出 |
| `moon run cmd/main -- --help` | 0 | 打印 `docmunch 0.3.1`（与 `moon.mod` 一致） |
| `... detect <文档站 URL>` | 0 | `platform=moonbit` |
| `... toc <fixture> --verify` | 0 | 每节 `hash_ok=true` |
| `... index-dir docs --repo selfcheck` | 0 | 28 篇 / 379 节 |

**这条演练本身就是主张**：本文件的数字，评审在干净机器上都能复现，不必先相信作者。
未覆盖：非 Windows 平台，以及首次依赖下载的网络耗时（本机 registry 有缓存）。

> 要动手提交：见 [submit-now.md](submit-now.md)。

## 对外可主张 / 不可主张

**可以主张**（每条都有可复跑证据）：

- 已发布到 MoonCakes（0.3.1），且**外部模块能从 registry 解析、编译并跑通完整链路**
  （建索引 → BM25 检索 → 按 id 取回并校验 sha256；
  `python tools/consumer_check.py --version 0.3.1`）；
- 检索质量与 LangChain 标题切分器**同一水平**，且在两个指标上各落后 1 题
  （hit@5 14/18 vs 15/18、完整性 13/18 vs 14/18）——本项目**不主张"切得更好"**；
- 端到端盲测中三种检索策略准确率打平，差异在成本：docmunch 13,064 token vs
  定长切分 17,117 vs 整篇 20,275；**不主张"回答更准"**；
- 每节带指回原文的字节区间与 sha256，产物逐字节可复现，索引版本不匹配 fail-closed；
  这套要求写成与实现无关的契约（`conformance/SPEC.md`），并有独立实现通过检查器。

**不能主张**：

- "已被采用"——依赖者 0、star 1、fork 0、issue 0；`docs/adoption.md` 列了
  "什么才算真采用"，当前四项全为 0；
- "比某方案更准"——见上，两组实验都是打平或略输；
- "取回 O(1)"——已撤回，改为实测成本模型（斜率约 0.073 ms/节）。

## 三处修正记录（可解释性）

初审提出的三条意见都已处理并留档：

1. "取回 O(1)"表述错误 → 改为实测成本模型，并补长驻进程索引缓存
   （取回 278.3 ms → 0.5 ms，约 553 倍）与倒排索引（检索 535.5 ms → 10.2 ms，约 52 倍）；
2. "标题切分是独立增量"撤回 → 换真实第三方组件重测，承认略输 1 题，
   增量改为**可验证性**，并写成可被外部实现的契约；
3. "省上下文 ⇒ 回答更好"撤回 → 做了两组受控盲测，只报能报的结论。

对应决策记录：`docs/decisions.md`（D55–D61 为修正链）。

## 门禁抓到的自身错误（部分）

这套检查不是装饰：它在两周里拦下过过期的测试数、重复/缺失的 ADR 编号、
与程序实际输出不符的 transcript、发布包里混进的工作区成员、以及
"0.3.1 未发布"这条在六份文档里同时写错的事实。明细见
`docs/decisions.md` D62/D65/D68/D69/D72。
