# P3 Markdown 层：HTML → CommonMark

- 时间：2026-11-08
- 目标：把抽取层产出的 HTML 转成保留标题层级的 CommonMark，并为后续分节（P4）提供稳定输入
- 结论：**8 个转换器单测通过（含 cmark 回环校验），3 份黄金文件稳定可复现**

## 1. 做法

没有选 `hustcer/html2md`，也没有走"Markdown→HTML 再反向"的路线，而是**在抽取层剪好的 DOM 上直接渲染 Markdown**（ADR D24）。理由：

- 抽取层已经把树剪成正文容器，再让第二个 HTML 库重解析一次是重复劳动，还会丢掉我们刚做过的清洗结果；
- `moonbit-community/cmark` 的方向是 **Markdown → AST → HTML**，没有 HTML→Markdown 的反向渲染器；
- 自己渲染可以保证输出确定性（黄金文件要能逐字节对比）。

映射规则：

| HTML | Markdown |
| --- | --- |
| `h1`–`h6` | `#`…`######` |
| `p` / 行内串 | 段落（连续行内节点合并成一段） |
| `strong`/`b`、`em`/`i`、`del`/`s` | `**x**`、`*x*`、`~~x~~` |
| `code`（行内） | 反引号包裹，内容不转义 |
| `pre` | 三反引号代码块，`class="language-x"` → 语言标注 |
| `ul` / `ol` / `li` | `- ` / `1. `，续行缩进 2 空格 |
| `blockquote` | 每行 `> ` 前缀 |
| `table` | GFM 管道表（首行表头 + `---` 分隔） |
| `a` | `[text](href)`；`href` 为空或以 `#` 开头时只保留文字 |
| `img` | `![alt](src)` |
| `hr` | `---` |
| `br` | 行尾两个空格 + 换行 |

另外两处工程处理：

- **相对链接绝对化**：转换前把 `a[href]`、`img[src]` 按页面 URL 用 WHATWG 解析器补齐（`/docs/x` → `https://example.com/docs/x`），这样 Markdown 脱离原页面也能用；
- **空白规范化**：行内文本折叠空白但保留首尾单空格（否则 `Hello <b>world</b>` 会粘成 `Helloworld`）；块间统一两个换行。

## 2. 验证

1. **单测**（`moon test -p .../md`，8 个）：标题/段落/强调、有序无序列表、代码块语言、表格、链接与锚点、引用块、相对链接绝对化；
2. **cmark 回环**：把生成的 Markdown 交给 `moonbit-community/cmark` 渲染回 HTML，断言 `<h1>` / `<strong>` / `<ul>` / `href` 都在——这一步抓语法错误最有效；
3. **黄金文件**：`fixtures/markdown/*.md` 由真实二进制生成，`tools/markdown_golden.py` 逐字节比对。

```
$ python tools/markdown_golden.py
ok    fixtures/markdown/arxiv-hichunk.md (1930 chars)
ok    fixtures/markdown/moonbit-update-2026-11-05.md (9814 chars)
ok    fixtures/markdown/readability-readme.md (5140 chars)
```

## 3. 过程中抓到的确定性 bug

第一次生成黄金文件时，"更新后立刻校验"三份全部漂移。根因不在换行，而在**候选容器选择遍历的是 `Map`**：分数并列时谁先被遍历到谁赢，而哈希遍历顺序不保证跨进程稳定。改成按文档顺序遍历元素、严格大于才替换（ADR D25），同一输入现在逐字节稳定。

## 4. 已知差距

| 差距 | 影响 | 计划 |
| --- | --- | --- |
| arXiv 的 `Title:` / `Authors:` 描述性 `<span>` 会留在标题里 | 只影响该站点的标题外观 | 用站点指纹（P1 的 platform）做定向清理 |
| 表格单元格按 DOM 顺序拍平，合并单元格不展开 | 复杂表格结构可能失真 | P3.1 |
| 嵌套列表统一 2 空格缩进 | 深层嵌套观感一般 | P3.1 |
| 本地文件模式不做链接绝对化（没有 base） | 本地 fixtures 的链接保持相对 | 接受（无页面 URL 可依） |

## 5. 复现

```sh
moon build --target native
moon run cmd/main --target native -- markdown fixtures/html/readability-readme.html --out out.md
python tools/markdown_golden.py --update   # 重新生成黄金文件
python tools/markdown_golden.py            # 校验
```
