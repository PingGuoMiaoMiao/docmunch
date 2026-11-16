# 自举演示：用 docmunch 索引它自己的文档

> 这不是"跑通一次"的记录，而是可以随时复跑的冒烟测试：`python tools/selfindex.py`。
> CI 每次 push 都会跑它。

## 为什么做这个

一个文档检索工具最诚实的验收方式是**拿它自己的文档当语料**：如果它连自己 19 份文档
都切不好、搜不准，那它对别人的文档也没什么说服力。

而且这条路走的是**用户路径**（`index-dir` → `search` → 再 `index-dir`），
不是内部 API，所以顺带验证了 CLI 的参数解析、目录遍历、增量跳过是否真的能用。

## 实测

环境：Windows / MoonBit 0.1.20261028 / native 目标。

```
$ docmunch index-dir docs --repo docmunch-docs --root .doc-index
repo=docmunch-docs files=19 changed=19 skipped=0 failed=0 docs=19 sections=279
```

19 份文档 → **279 个节**（`docs/decisions.md` 一个文件就贡献了 50+ 节，因为每条 ADR
都是三级标题）。

再跑一次，走增量路径：

```
$ docmunch index-dir docs --repo docmunch-docs --root .doc-index
repo=docmunch-docs files=19 changed=0 skipped=19 failed=0 docs=19 sections=279
```

`changed=0 / skipped=19` 说明每个文件的 `sha256` 都命中缓存，没有重新分节。

### 英文查询

```
$ docmunch search docmunch-docs "byte offset"
score=594 level=3 docs/reference-comparison.md   3.3 存储与取回
score=589 level=2 docs/p5-index.md               3. 取回
score=550 level=3 docs/reference-comparison.md   3.2 分节算法
score=494 level=2 docs/p4-sectioning.md          1. 契约
```

BM25 把「字节偏移如何存储与取回」的章节排在最前，而不是按文件名匹配。

### 中文查询

```
$ docmunch search docmunch-docs 索引
score=353 level=2 docs/decisions.md        D31 — 索引版本不匹配即视为未索引
score=353 level=3 docs/p8-enhancements.md  索引版本
score=351 level=3 docs/devlog.md           P5 索引：元数据 + 偏移，正文不进索引
```

中文走 bigram 分词（`索引` 是一个 bigram），命中的是正文里讲索引设计的章节，
而不是"标题里恰好有'索引'"的页面。

## 一次典型的取回

```sh
# 1. 看目录
$ docmunch toc docs/p5-index.md
# 2. 检索拿到 id
$ docmunch search docmunch-docs "取回" --root .doc-index
# 3. 按 id 取回，并让工具重新哈希校验字节
$ docmunch section docmunch-docs "docmunch-docs::docs/p5-index.md::..." --verify --root .doc-index
verified=true bytes=1832
```

`verified=true` 表示取回的字节区间重新算 `sha256` 与索引里存的值一致——**取回的内容
和当初分节的完全是同一份**，不是"差不多"。

## 复跑

```sh
moon build --target native
python tools/selfindex.py
```

脚本断言六件事：目录索引成功、全部文档入库、分节数达到下限、英文查询有命中、
中文查询有命中、第二次运行全部走增量。任何一条不满足就非零退出。
