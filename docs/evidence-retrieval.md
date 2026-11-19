# 检索证据：召回、上下文完整性与成本（已用真实组件重做）

- 时间：2026-11-18（第二版，第一版结论部分作废）
- 触发：初审驳回要求"针对真实代理任务中的召回、上下文完整性与成本收益进行清晰说明并附带对照案例"
- 复跑：`python tools/retrieval_compare.py`、`python tools/cost_model.py`、`python tools/cache_bench.py`

## 0. 这一版推翻了第一版的什么

第一版用的是我自己写的定长切块和自写 BM25 做对照，据此得出"标题对齐切分让整节完整性从 67% 提升到 94%"。初审意见指出这不足以证明增量，**这个批评是对的，而且比我当时以为的更严重**：

> 用真实的 LangChain 组件重跑后，标题切分器（`MarkdownHeaderTextSplitter`）在三个质量指标上与 docmunch **完全打平**。

所以本文件第一版里"标题对齐是增量"、"完整性 94% vs 67%"两条**作废**，不再作为申报理由。保留的结论只有下面这些。

## 1. 对照系统（全部为真实第三方实现）

| 系统 | 实现 | 说明 |
| --- | --- | --- |
| `recursive` | `langchain_text_splitters.RecursiveCharacterTextSplitter(chunk_size=512, chunk_overlap=80)` | 业界最常用的定长递归切分 |
| `md_header` | `langchain_text_splitters.MarkdownHeaderTextSplitter(#, ##, ###)` | LangChain 官方的标题感知切分 |
| `docmunch` | 本项目：标题对齐分节 + 字节偏移 + sha256 | 本项目 |
| `full_doc` | 不检索，全文入上下文 | "文档不大就整篇贴" |

检索打分：三者统一用 `rank_bm25.BM25Okapi` + 同一套分词（ASCII 词 + CJK bigram），因此差异只来自**切分方式**。
token 计数：`tiktoken cl100k_base`，非估算。

语料：本仓库 `docs/`，21 份文档。
问题集：18 个真实问题，人工标注（金标文档 + 金标小节标题 + 必须出现的短语），在 `tools/retrieval_compare.py` 的 `GOLD` 里逐条可核对。

## 2. 结果

```
corpus: 21 docs, 299 docmunch sections, 328 recursive chunks, 268 header splits; k=5

system          hit@1     hit@5   complete   ctx tokens
-------------------------------------------------------
recursive      5/18     15/18       7/18           1242
md_header      7/18     15/18      14/18           1268
docmunch       7/18     15/18      14/18           1212
full_doc      18/18     18/18      18/18          72514

average gold-section size: 270 tokens
```

指标定义：

- **hit@k**：前 k 条结果中，是否有内容属于金标文档且包含标注短语；
- **complete**：金标小节是否**整节**进入上下文。允许重新渲染带来的空白差异（对 `MarkdownHeaderTextSplitter` 这类重建文本的实现公平起见，按"金标小节每一非空行都出现"判定）；
- **ctx tokens**：交给模型的上下文 token 数（tiktoken）。

## 3. 结论（只写数据支持的）

1. **检索质量没有增量**：`docmunch` 与 LangChain 的标题切分器在 hit@1（7/18）、hit@5（15/18）、完整性（14/18）上完全一致，上下文大小也几乎相同（1212 vs 1268 token）。**"我们切得更好"这个主张不成立。**
2. **切分方式本身确实有影响，但那是既有库的能力**：定长切分（`recursive`）完整性只有 7/18，而两种标题感知切分都是 14/18。这个差异属于"用不用标题切分"，不属于本项目。
3. **整篇塞入的 100% 召回不可用**：72,514 token，是检索方案的 **约 60 倍**。对 21 份文档就已经如此，语料再大会直接超出上下文窗口。
4. **所以真正的差异不在质量，在"能不能验证"**：见第 5 节。

## 4. 成本：实测（含本轮修复）

### 4a. 冷进程（CLI 每次调用重新加载索引）

| 节数 | search | fetch 单节 |
| --- | --- | --- |
| 286 | 20.7 ms | 10.3 ms |
| 1,430 | 99.4 ms | 47.9 ms |
| 5,720 | 417.8 ms | 216.4 ms |

即：`加载解析索引 O(节数) + 线性定位 O(节数) + 读节字节 O(节字节)`，斜率约 0.073 ms/节。**这也是"O(1)"说法错误的原因，已在全部文档改正。**

### 4b. 长驻进程（本轮新增索引缓存，D55）

MCP 服务器是长驻进程，索引按 repo 缓存一次（mtime 失效 + 写路径显式失效）：

```
corpus: 20 copies, 420 docs, 5980 sections, index 9308 KB

path                     get_section  search_sections
-----------------------------------------------------
cold CLI (parse each)        278.3 ms          535.5 ms
MCP first call               223.4 ms          243.1 ms
MCP cached (median)            0.5 ms           10.2 ms
```

- **取回：278 ms → 0.5 ms（约 553 倍）**，且不再随索引体积增长——只剩 `read_at`；
- **检索：536 ms → 10.2 ms（约 52 倍）**——本轮加入倒排索引（D58），查询只访问含查询词的节；冷启动 CLI 仍需重建 postings（约 240 ms @ 6,580 节）。

磁盘读放大：528 KB 文档中取一节 10.8 KB，**读放大 2%**（`tools/cost_model.py`）。这部分与文档大小无关，只与节大小有关。

## 5. 真正的差异：可验证性（能力对照，非质量指标）

| 能力 | `recursive` | `md_header` | docmunch |
| --- | --- | --- | --- |
| 切分/检索质量 | 基准 | 与 docmunch 相同 | 与 `md_header` 相同 |
| **产出可定位的字节区间**（`[start, end)` 指回原文） | ✗ | ✗ | ✓ |
| **取回后可重算哈希自证**（`--verify` → sha256 一致） | ✗ | ✗ | ✓ |
| **重复运行逐字节可复现**（黄金文件回归） | ✗（切分参数/版本变则变） | ✗ | ✓（4 份黄金文件逐字节） |
| 索引版本不匹配即 fail-closed | N/A | N/A | ✓ |
| 单原生二进制、无 Python 运行时 | ✗ | ✗ | ✓ |
| MCP 原生接口 | ✗ | ✗ | ✓（13 个工具） |

这张表是**能力有无**，不是"更好"。它的意义是：如果使用者需要"我取回的这一段，能证明就是原文的那一段"，现有切分库给不了，docmunch 给得了。

## 6. 仍然没有的证据

- **端到端评测已做，但无法区分优劣**：12 题盲评下三种检索策略都是 12/12，差异只在上下文成本（见 `docs/e2e-agent-eval.md`）。本文件仍不主张"用 docmunch 回答更准"。
- **冷启动进程没有 postings 缓存**：CLI 每次调用仍要重建倒排（约 240 ms @ 6580 节），只有长驻进程享受 10 ms 的查询延迟。
- **只有 18 道题、语料只有本项目文档**，存在选择偏差；换了语料结果可能不同，欢迎复跑。

## 7. 复跑

```sh
moon build --target native
pip install langchain-text-splitters rank-bm25 tiktoken

python tools/retrieval_compare.py            # 第 2 节：真实组件对照
python tools/cost_model.py                   # 第 4a 节：冷进程成本
python tools/cache_bench.py --copies 20      # 第 4b 节：长驻进程缓存效果
```
