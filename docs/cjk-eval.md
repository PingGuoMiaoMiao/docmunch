# 中文检索评测：不用分词词典，会不会更差？

- 时间：2026-11-19
- 问题：docmunch 的中日韩文用**重叠 bigram** 切分，不带任何词典。词典分词（jieba）是中文检索的常规做法，那不用词典是不是要付质量代价？
- 复跑：`python tools/cjk_eval.py`

## 1. 方法

三个分词器喂**同一个 BM25**（`rank_bm25.BM25Okapi`）、**同一批分节**（docmunch 在 `docs/` 上切出的 329 节）、**同一组 18 个标注问题**，唯一变量是分词：

| 分词器 | 规则 | 外部依赖 |
| --- | --- | --- |
| `char` | 每个 CJK 字一个 token（词表最小） | 无 |
| `bigram` | 重叠 bigram，**docmunch 实际使用的方案** | 无 |
| `jieba` | 词典分词（jieba 0.42.1） | 有 |

英语/数字部分三者一致（按 ASCII 词切、小写）。指标准义与 `docs/evidence-retrieval.md` 相同：命中 = 前 k 条里存在"属于金标文档且包含标注短语"的节。

## 2. 结果

```
corpus: 26 docs, 347 sections, 18 questions, k=5

tokenizer       hit@1      hit@5     vocab  note
------------------------------------------------------------
char           5/18      14/18        2828  no dictionary, largest vocab
bigram         7/18      14/18       13113  no dictionary, what docmunch ships
jieba          7/18      15/18        4988  dictionary segmentation, extra dependency
```

## 3. 结论

1. **hit@1 上 bigram 与 jieba 相同（7/18）**，char 落后 2 题（5/18）——单字切分明显更差。
2. **hit@5 上 jieba 15/18，bigram 14/18，char 14/18**。**bigram 比词典分词少命中 1 题。**
3. 因此正确结论是：**bigram 与词典分词基本持平、略低 1 题**——不能说"不劣于"，更不能说"优于"。1 题的差距在 18 题样本里属于噪声，但我们没有理由声称优势。
4. **代价是词表更大**：bigram 12,521 个 term，jieba 4,847 个，char 2,755 个。索引因此更大（term 越多，`terms` 字段越长），换来的是零词典依赖。

**因此可以主张**：中文检索不需要引入分词词典，重叠 bigram 就能达到 jieba 的水平——这对"单二进制、零外部依赖"的定位是必要的，否则要么内嵌词典（体积），要么调用外部服务（违背定位）。

**不能主张**：bigram 比 jieba 更好。

## 4. 局限

| 局限 | 说明 |
| --- | --- |
| 样本小 | 18 题、24 份文档、单次运行；1 题的差距不构成统计显著 |
| 语料单一 | 全部是本项目文档，领域词集中（索引、分节、MCP），未覆盖口语/新闻/法律等中文文本 |
| 只测检索 | 没有测下游问答质量中文分词的差异 |
| 未测混合语言 | 中英混排查询只覆盖了几题，且本项目文档本身就以中英混排为主 |

要补强的话，最短路径是换一个**非本项目**的中文语料（例如某开源项目的中文文档站）重跑同一脚本，看结论是否稳定。

## 5. 复跑

```sh
moon build --target native
pip install rank-bm25 jieba
python tools/cjk_eval.py            # 表 1
python tools/cjk_eval.py --json c.json   # 逐分词器明细，含未命中题目标题
```
