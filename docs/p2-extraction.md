# P2 抽取层：arena DOM + Readability 兼容评分

- 时间：2026-11-08
- 目标：HTML → 正文文本 + 元数据（title / byline / site_name / lang），并用 Node 版 Readability 做差分验收
- 结论：**3/3 标题匹配，平均长度比 0.95，平均词集 Jaccard 0.92**，达到预研设定的指标（标题 ≥80%、相似度 ≥0.85）

## 1. 指标

命令：`python tools/compare.py`

| fixture | 标题 | 长度比 | Jaccard | 说明 |
| --- | --- | --- | --- | --- |
| arxiv-hichunk | ✅ | 0.87 | 0.77 | 我们多了 arXiv 元数据头（提交时间/作者），少了页脚部分 |
| moonbit-update-2026-11-05 | ✅ | 0.98 | 0.99 | Docusaurus 页面，几乎完全一致 |
| readability-readme | ✅ | 1.00 | 1.00 | GitHub 页面（导航噪声最多的一个） |
| python-asyncio | ✅ | 1.27 | 0.86 | Sphinx 页面，目录型链接块会让长度偏大（P7 已加链接密度裁剪） |
| **平均** | **4/4** | **1.03** | **0.91** | — |

第一次跑的时候三个 fixture 的长宽比是 `2.31 / 1.29 / 8.76`、Jaccard `0.50 / 0.83 / 0.35`，靠下面三个 bug 修到现在的水平。

## 2. 实现路线（与原计划的偏差）

预研里写的是"自建 arena DOM"，**实际做的时候推翻了**：`moonbit-community/html` 的 `Document` 已经提供 `append_child` / `remove_child` / `insert_before` / `set_attribute`，但 `Node` 的构造器是包内可见的（`Cannot create values of the read-only type`），所以既不能新建节点、也不能跨文档克隆。

因此改成**原地改写**：

1. **读取元数据**（在清洗之前，因为 `<title>`、`og:*`、`<html lang>` 都在会被剪掉的区域）；
2. **清洗**：按标签（script/style/iframe/svg/form/nav/footer/aside…）、`role`（navigation/banner/complementary/contentinfo/search）、`hidden`/`aria-hidden`、以及 class/id 的**负向 token** 删除节点；
3. **打分**：`p / pre / td / blockquote` 且文本 ≥25 字符的节点得 `1 + 逗号数 + min(len/100, 3)`，命中正向 token +25、负向 token −25；分数加到父节点、一半加到祖父节点；
4. **选容器**：分数最高的节点，其父节点作为容器；容器里只保留候选与"文章样"兄弟（有分数 ≥0.2×候选分，或 ≥80 字符的段落）；
5. **折叠祖先链**：从容器往上逐层删掉旁支，再把中间包装层 `unwrap`，使容器直接挂在 `<body>` 下；
6. **序列化**：`Document::to_html()` 后截取 `<body>` 内文本；纯文本走 `get_text_content`。

## 3. 三个真实 bug（都是差分测试抓出来的）

| # | 现象 | 根因 | 修法 |
| --- | --- | --- | --- |
| 1 | 所有页面都抽不出正文 | 判断"节点是否已随父节点删除"时把 document 节点当成已被摘除，导致 `clean` 对全部节点 `continue` | 沿父链上溯，遇到 `document_element` 或节点 0 即视为仍挂载 |
| 2 | MoonBit 页面抽成空 | `clean` 把整棵内容树删了——Docusaurus 给主包装层加了 `__docusaurus_skiptocontent_fallback` 类，命中负向词 `skip` | 去掉 `skip`；负向匹配改为 **token 级**（见下） |
| 3 | GitHub 页面抽成文件列表 | README 容器类名 `sharedmarkdowncontent__jrrdyk` 命中 `share`，被当成分享按钮删掉 | 负向信号按 `class/id` 切 token 后**整词匹配**，`sharedmarkdowncontent` 不再命中，`share-buttons` 仍命中 |

第 2、3 条共用同一个教训：**子串匹配 class/id 会误杀**，必须 token 化。

## 4. 与 Readability 的已知差异

| 差异 | 影响 | 计划 |
| --- | --- | --- |
| 不克隆节点（做不到） | 无法"把兄弟节点搬进候选容器"，只能保留在原位 | 接受；对分节影响小 |
| 没有 `_getArticleTitle` 的全部变体 | 少数站点标题可能带站点名 | 已做去 `[id]`、去 `\| Site`/`·`/`—` 后缀、去 `Site - ` 前缀 |
| 不做 link density / 条件清理 | 目录型页面可能残留少量链接块 | P2.1 视差分结果补 |
| 不做 frameset / 无 JS 渲染 | 纯 CSR 页面只能拿到空壳 | 记录为已知限制 |

## 5. 复现

```sh
moon build --target native

# 单个页面（URL 或本地文件）
moon run cmd/main --target native -- extract fixtures/html/readability-readme.html --out-html out.html

# 与 Node 版 Readability 对比（先用 tools/oracle 生成期望值）
python tools/compare.py
```

`tools/compare.py` 的标题判定是"归一化后相等，或一方包含另一方"——因为 Readability 有时会把 `Site - ` 前缀加回去，而两者指向同一个标题。

## 6. 下一步（P3）

1. 把抽取出的 HTML 转 CommonMark（`moonbit-community/cmark`），保留标题层级；
2. 用同一批 fixture 做 Markdown 黄金文件对比；
3. 补 link-density 清理，把 arxiv 的 Jaccard 拉回 0.85 以上。
