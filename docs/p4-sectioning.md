# P4 分节：标题层级、字节偏移与内容哈希

- 时间：2026-11-08
- 目标：把 Markdown 切成「标题树 + 字节区间 + 内容哈希」，为 P5 索引与 O(1) 取回打底
- 结论：**9 个分节单测通过；3 份黄金文件通过字节级契约校验（连续覆盖、UTF-8、sha256 全等）**

## 1. 契约

```moonbit
pub(all) struct Section {
  id, repo, doc_path, title, level,
  byte_start, byte_end,      // UTF-8 字节偏移，不是字符偏移
  parent_id, content_hash,   // sha256(slice)，用于取回校验
}
```

- `id = {repo}::{doc_path}::{hierarchical_slug}#{level}`（与 jdocmunch 同构，D7）
- 同级重复标题自动加 `-2`、`-3` 后缀
- 第一个标题之前的内容成为 `level=0` 的 `preamble` 节
- 子节 ID 前缀父级 slug 链（`readability-js/installation#2`），兄弟插入不引起其他分支改号

## 2. v1 相对 v0 的变化

| 能力 | v0 | v1 |
| --- | --- | --- |
| 标题识别 | 只有 ATX `#` | ATX + setext（`===` / `---` 下划线） |
| 代码块 | 会把 ``` 里的 `#` 当标题 | 跟踪 ``` / ~~~ 围栏，围栏内不切 |
| 内容哈希 | 无 | 每节 sha256（UTF-8 字节） |
| 中文标题 slug | `sec0`、`sec1`（位置号） | `h` + sha256 前 8 位（稳定） |
| 标题噪声 | 零宽空格残留 | 剥离 U+200B / FEFF / NBSP / `¶` |

## 3. 验证

### 单测（9 个）

覆盖：基础两节、preamble、重复兄弟后缀、非标题 `#nope`、围栏内标题忽略、setext 两级、CJK 字节偏移、哈希稳定性、无围栏的空输入。

CJK 偏移断言举例：`# 中文\n\n内容\n\n## 下一节\n` 中第二节必须从**第 18 字节**开始（字符数是 14）。

### 字节级契约校验（`tools/toc_check.py`）

不看进程内字符串，直接读磁盘字节：

1. 各节首尾相接、从 0 覆盖到 EOF；
2. 每个切片是合法 UTF-8；
3. `sha256(切片)` 与 `toc` 打印的哈希全等；
4. ID 唯一、层级在 0–6、非根节有标题。

```
$ python tools/toc_check.py
ok   fixtures/markdown/arxiv-hichunk.md
ok   fixtures/markdown/moonbit-update-2026-11-05.md
ok   fixtures/markdown/readability-readme.md
```

### 端到端

```
$ docmunch markdown https://docs.python.org/3/library/asyncio.html --out tmp.md
wrote=tmp.md bytes=5289
$ python tools/toc_check.py tmp.md
ok   tmp.md
```

## 4. 两个在真实语料上暴露的问题

| 问题 | 现象 | 修法 |
| --- | --- | --- |
| 中文标题 slug 不稳 | 全站中文标题都退化成 `sec0`/`sec1`，前面插一节全乱 | 内容哈希 slug（D27）：`h45937b7f`，插入不影响 |
| 标题后缀噪声 | Sphinx 的 `¶`、Docusaurus 的零宽空格让 slug 变空或标题变脏 | 标题清洗（D28） |

## 5. 已知差距

- 围栏只识别行首的 ``` / ~~~，不支持缩进围栏与自定义围栏长度；
- setext 只接受纯 `===`/`---` 行，不处理行尾空格以外的变体；
- 输入假定已是 Markdown（HTML 需先走 P3 转换）；
- docs.python.org 这类 Sphinx 站点抽取出来的正文偏窄（P2 的容器选择问题），分节本身正确。

## 6. 复现

```sh
moon build --target native
moon run cmd/main --target native -- toc fixtures/markdown/readability-readme.md --verify
python tools/toc_check.py
```
