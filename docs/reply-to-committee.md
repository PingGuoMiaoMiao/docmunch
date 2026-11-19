# 对初审意见的回复与材料补充（可直接粘贴发送）

> 用途：发给组委会 / 答复初审。仓库对应 commit 范围 `e5cecb4..1bd16c9`。
> 提交前请确认仓库已 push、`python tools/acceptance.py --since 2026-11-01` 为 8 PASS。

---

## 正文

尊敬的 MoonBit 开源大赛组委会：

感谢初审意见。三条意见我都接受，其中两条是我表述错误，已改正并补了实测数据；第三条按意见做了受控实验。下面逐条说明，所有数据都可在仓库里复跑。

**先给结论（两屏以内）：**

1. **"取回 O(1)"是我写错了。** 已改为实测模型：单次取回 = 加载解析索引 O(节数) + 定位 O(节数) + 读该节字节；斜率约 0.073 ms/节。同时把短板修了：长驻进程索引缓存使取回 278 ms → 0.5 ms，倒排索引使检索 536 ms → 10.2 ms。
2. **"独立增量"我收回了一条主张。** 用真实 LangChain 组件重测后，我的检索质量**不比它好，hit@5 还落后 1 题**（14/18 对 15/18）。剩下的增量是**可验证性**：每节带指回原文的字节区间与 sha256、取回可自证、产物逐字节可复现。这套要求已写成与实现无关的契约，并有独立实现通过检查器。
3. **"省上下文 ≠ 回答更好"成立，我做了两组实验。** 单点事实题上三种策略全部 12/12（打平，只能证明省 36% 上下文）；补的"答案横跨小节"难题上，分节检索 **8/8 全对（1.000）**，定长切块 **4 对 4 半对（0.750）**，多花 50% 上下文。
4. 两处修正对我都不利，我都改了并留了记录（`docs/decisions.md` D56/D59/D61）。

### 一、关于"取回成本 O(1)"——这条是我错了

原文写"按偏移定位小节，取回成本 O(1)"，这不成立。实测（`tools/cost_model.py`，同一台机器，7 次中位数）：

真实成本是 `加载解析索引 O(节数) + 定位 O(节数) + 读该节字节 O(节字节)`，实测斜率约 **0.073 ms/节**（286 → 5,720 节时，检索 20.7 → 417.8 ms）。**能成立的表述是**：取回的磁盘 IO 与该节大小有关、与文档大小无关（528 KB 文档里取一节 10.8 KB，读放大 2%），但每次调用仍要扫描元数据索引。

顺带把这条短板修了：新增长驻进程索引缓存（`docs/decisions.md` D55），MCP 服务器按 repo 缓存已解析的索引，失效条件为 mtime 变化 + 写路径显式失效。5,980 节 / 9.3 MB 索引下实测：

```
                          get_section   search_sections
cold CLI (每请求重解析)      255.0 ms        517.5 ms
MCP 首次调用                 207.0 ms        234.9 ms
MCP 缓存后（中位数）            0.6 ms        248.7 ms
```

取回 255 ms → 0.6 ms（约 457 倍），不再随索引体积增长。**检索仍未优化**（BM25 全量扫描，约 249 ms），如实列出。

### 二、关于"独立增量"——我撤回了一条主张，改成可验证的那条

我原来把"标题对齐切分"当作核心增量，并用我自己写的定长切块做对照，得出"完整性 94% vs 67%"。**这个对照不成立**，因为 baseline 是我自己实现的。改用真实第三方组件（LangChain `MarkdownHeaderTextSplitter` / `RecursiveCharacterTextSplitter`、`rank_bm25`、`tiktoken`）在同一语料、同一批 18 个标注问题上重跑：

```
system          hit@1     hit@5   complete   ctx tokens
recursive      6/18     12/18       4/18           1371
md_header      7/18     15/18      14/18           1403
docmunch       7/18     14/18      13/18           1353
full_doc      18/18     18/18      18/18          72514
```

**docmunch 与 LangChain 的标题切分器处于同一水平，而且在两个指标上各落后 1 题**（hit@5 14 vs 15、完整性 13 vs 14）。因此"我们切得更好"这条主张撤回（`docs/decisions.md` D56）——不是"打平所以不必提"，而是"我们确实没赢"。

剩下的增量不在质量维度，在**可验证性**维度：

| 能力 | LangChain 定长切分 | LangChain 标题切分 | docmunch |
| --- | --- | --- | --- |
| 检索质量 | 基准 | 与 docmunch 相同 | 与 md_header 相同 |
| 产出指回原文的字节区间 | ✗ | ✗ | ✓ |
| 取回后重算 sha256 自证 | ✗ | ✗ | ✓ |
| 重复运行逐字节可复现 | ✗ | ✗ | ✓ |
| 索引版本不匹配即 fail-closed | N/A | N/A | ✓ |
| 单原生二进制 / MCP 原生 | ✗ | ✗ | ✓ |

为了让这条"增量"不是自说自话，我把它写成了**与实现无关的一致性契约** `conformance/SPEC.md`（六条规则：唯一稳定 id、字节区间连续覆盖、边界落在字符边界、内容哈希可重算、无空小节、产物确定性），并提供 `conformance/check.py`：任何实现都可以拿自己的 index.json + 原文缓存跑一遍。`conformance/selftest.py` 会故意把真实索引破坏五种方式（哈希错、留空洞、id 重复、空节、切在字符中间），验证检查器确实能逐条报出违规——一个"什么都通过"的检查器没有意义。

### 三、关于"减少上下文不能推出回答质量提高"——这条也成立，我做了受控实验

撤回该推论，改为实测。方法：由一个**独立代理**读 5 份文档出 12 道题（含标准答案）；每个上下文策略由**各自的独立代理**作答，且只允许读自己的上下文文件、禁止读仓库；再由**另一个独立代理**对 A–E 匿名列判分，判分员不知道哪列对应哪个策略。结果（`docs/e2e-agent-eval.md`）：

```
strategy      correct   partial   wrong    score   ctx tokens  per-question
none                0         0      12    0.000          518            43
full_trunc          3         2       7    0.333         8556           713
full               12         0       0    1.000        20275          1690
recursive          12         0       0    1.000        17117          1426
docmunch           12         0       0    1.000        13064          1089
```

三条读数：

1. **无上下文组 0/12**——这批文档没有被模型记住，控制组成立，其他组的分数确实来自材料；
2. **整篇塞入在窗口受限时崩到 0.333**（同样 12 题，只给前 8000 token，7 题答案根本不在上下文里）；
3. **三种检索策略准确率打平（都是 12/12），差异在成本**：docmunch 13,064 token，定长切分 17,117（多 31%），整篇 20,275（多 55%）。

**可以主张**：在这组任务上，把上下文成本降到整篇的约 2/3，准确率不降；整篇塞入一旦超出窗口就急剧失效。
**不能主张**：docmunch 比定长切分更准，或"回答质量更高"。这个实验的局限（12 题全是单点事实、存在天花板效应、单次运行、作答与判分同源模型）写在 `docs/e2e-agent-eval.md` 第 4 节，没有隐藏。

### 三之二：补一组"答案横跨小节"的难题，这里确实分出了差别

上面 12 题全部满分，只能说明它们测不出差异。我又做了 8 道**专测分节失败模式**的题：答案需要同一小节内相距 **727–3,664 字符**的两个事实，512 字符的定长块装不下（`docs/e2e-hard.md`）。

| 策略 | 上下文含两个事实（机械匹配） | 答题得分 | 上下文 token |
| --- | --- | --- | --- |
| `docmunch` | **8/8** | **1.000**（8 题全对） | 16,722 |
| `recursive`（512 字符块） | **2/8** | 0.750（4 对 4 半对） | 11,147 |
| `none`（控制） | — | 0.000 | 624 |

即：**多花 50% 上下文，换 0.25 的准确率**。定长切块在 6/8 的题上根本拿不到第二个事实——这不是模型答得糙，是证据不在上下文里。

**限定同样明确**：这组题是为探测该失败模式**构造**的，分节占优是设计使然，不能反推"普遍更准"；真实查询中横跨小节的比例我没有测。单点事实题上三种策略仍然全部满分。

**这个失败模式有多普遍？** 没有真实查询日志，测不了"问题分布"，但结构那一半可以测（`tools/section_shape.py`）：358 个小节里 **26% 超过一个 512 字符块**（中位 313 字符，平均一个小节要 1.35 个块才覆盖完整），标注过的 18 个问题里 **6 个（33%）的金标小节需要多块**。所以"单块拿不全"不是边角料——至少四分之一的内容结构上放不进一个块。但不能反推"四分之一的真实提问会踩中"。

### 四、本轮补充的三项引擎级工作（都可复跑）

初审之后我没有只改文字，也补了三处能测量、能被外部验证的东西。

**4.1 倒排索引：查询不再全量打分**

原先 BM25 每次查询给所有节打分，成本 O(节数)。现在建 `词 → [(节, 加权 tf)]` 的倒排表（字段权重与原来一致：title 3 / path 2 / body 1），查询只访问含查询词的节。有单测断言**倒排结果与扫描结果逐条相同（id 与分数）**，所以这是提速而不是换排序。

6,580 节 / 10.3 MB 索引实测：

```
                          get_section   search_sections
cold CLI (parse each)        278.3 ms        535.5 ms
MCP first call               223.4 ms        243.1 ms
MCP cached (median)            0.5 ms         10.2 ms
```

**检索 249 ms → 10.2 ms（约 24 倍），取回 553 倍。** 冷启动 CLI 仍要重建 postings（约 240 ms），这条在本报告和 `docs/evidence-retrieval.md` 里都如实写出。

**4.2 中文评测：不用分词词典会不会更差**

docmunch 的中文按重叠 bigram 切分、不带词典。用同一个 BM25、同一批 329 节、同一组 18 个标注问题对比三种分词（`tools/cjk_eval.py`）：

```
tokenizer       hit@1      hit@5     vocab
char           5/18      14/18        2828
bigram(本案)   7/18      14/18       13113
jieba          7/18      15/18        4988
```

hit@1 上 bigram 与 jieba 相同（7/18），char 落后 2 题；hit@5 上 jieba 15/18、bigram 14/18。**bigram 比词典分词少 1 题，所以结论是"基本持平、略低"，不能说"不劣于"或"优于"。** 代价是词表约 2.6 倍。这条支持了"单二进制、零词典依赖"的设计取舍。

**4.3 采用记录：只写能核对的数据**

`docs/adoption.md` 把"数据"和"证据"分开：

| 指标 | 数值 |
| --- | --- |
| MoonCakes 下载 / 依赖者 | 37 / **0** |
| GitHub star / fork / issue | 0 / 0 / 0 |
| 近 14 天克隆 | 180 次 / 67 个独立来源 |

下载量不等于采用，所以补了两条硬证据：

1. `tools/consumer_check.py`：在临时目录新建**独立 MoonBit 模块**，从 registry 写 `PingGuoMiaoMiao/docmunch@0.3.1`，编译并运行成功——证明发布出去的包能被外部真实消费；
2. `conformance/reference_impl.py`：一个与 docmunch **零共享代码**的约 70 行 Python 实现，按同一份 `SPEC.md` 产出索引，`conformance/check.py` 判定 `all rules passed`——证明契约不是只对自家实现成立。

**我没有主张"已被采用"**：依赖者、fork、issue、第三方通过检查器的记录当前都是 0，这一点写在文档里。

### 五、材料位置与复跑

| 内容 | 位置 |
| --- | --- |
| 申报书（含第八、九节的逐条回应） | `docs/application-docmunch.md` |
| 检索与成本证据 | `docs/evidence-retrieval.md` |
| 端到端实验 | `docs/e2e-agent-eval.md` |
| 一致性契约与检查器 | `conformance/SPEC.md`、`conformance/check.py` |
| 决策记录（含 D55–D60 六次修正） | `docs/decisions.md` |
| 倒排索引与性能 | `index/inverted.mbt`、`tools/cache_bench.py` |
| 中文评测 | `docs/cjk-eval.md`、`tools/cjk_eval.py` |
| 采用记录与外部消费验证 | `docs/adoption.md`、`tools/consumer_check.py` |
| 契约的独立实现 | `conformance/reference_impl.py` |

```sh
moon build --target native
moon test                                   # 115/115
python tools/acceptance.py --since 2026-11-01

pip install langchain-text-splitters rank-bm25 tiktoken
python tools/retrieval_compare.py           # 真实组件对照
python tools/cost_model.py                  # 成本模型
python tools/cache_bench.py --copies 20     # 索引缓存效果
python conformance/selftest.py              # 契约检查器自测
python conformance/reference_impl.py --src docs/p5-index.md --out /tmp/ref
python conformance/check.py --index /tmp/ref/index.json --raw /tmp/ref/raw
python tools/consumer_check.py --version 0.3.1   # 外部模块消费已发布版本
python tools/cjk_eval.py                    # 中文分词对照（需 jieba）
```

如果还需要哪一维度的补充数据，请告知，我可以按指定语料/指定问题集重跑。

此致

陈永祺（PingGuoMiaoMiao）
3226742838@qq.com
https://github.com/PingGuoMiaoMiao/docmunch

---

## 提交前检查（给自己看）

- [ ] 仓库已 push 到最新 commit
- [ ] `python tools/acceptance.py --since 2026-11-01` → 8 PASS / 0 WARN
- [ ] 飞书报名表已用新版"一页说明"覆盖（见 `docs/registration.md`）
- [ ] 微信群昵称已改为 GitHub ID
- [ ] 若走邮件回复，邮件与表格内容保持一致，不要出现两个版本的申报描述
