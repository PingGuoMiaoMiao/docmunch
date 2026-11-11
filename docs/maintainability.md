# 可维护性评估（2026-11-11）

## 结论

**不需要重构（重写），需要 3 处定向改造。**

判断依据：分层依赖是干净的 DAG、测试能兜住改动、算法集中在少数文件；问题集中在**一个包职责过宽**和**一个函数过长**，都属于可以局部修的范畴。重写会丢掉已经验证过的确定性保证（黄金文件、字节契约），收益远小于风险。

---

## 1. 量化指标（实测）

| 指标 | 数值 | 评价 |
| --- | --- | --- |
| 生产代码 | 31 个文件 / **4,849 行** | 规模适中 |
| 测试代码 | 9 个文件 / 1,108 行（79 个用例） | 测试/生产 ≈ **23%**（行数），用例密度尚可 |
| 最长文件 | `extract/readability.mbt` 640 行 | 偏大，可拆 |
| 次长文件 | `md/convert.mbt` 505 行、`cmd/main/main.mbt` 486 行 | 偏大 |
| 最长函数 | **`mcp/server.mbt::build_server` 264 行** | ⚠️ 主要问题 |
| 次长函数 | `section/split.mbt::split_document` 149 行、`http/fetch.mbt::fetch_hop` 101 行 | 算法本体，可接受 |
| 编译告警 | 3 条（2×`result_error_return` + 1×`unused_package`） | 可接受 |
| 公开 API 面 | `http` 包 125 行 `.mbti`，其余 7–40 行 | ⚠️ `http` 过宽 |

## 2. 做得好的地方

### 2.1 依赖是干净的分层 DAG，无环

```
core        (无依赖)
extract     (无依赖)
http        (无依赖)
md        → extract
section   → core
index     → core, section
mcp       → core, extract, http, index, md
cmd/main  → 全部
```

越靠下越基础，`mcp` / `cmd` 是仅有的"宽消费者"——符合适配器层的定位。

### 2.2 每个包有明确的单一职责（除 `http`）

`core` 模型 / `extract` 抽取 / `md` 转换 / `section` 切分 / `index` 存储检索 / `mcp` 协议适配 / `cmd` 交互。改某个算法时，改动范围基本落在一个包内。

### 2.3 确定性 + 回归网

- 4 份 Markdown 黄金文件逐字节比对；
- 分节字节契约脚本（连续覆盖 / UTF-8 / sha256 / id 唯一）；
- 抽取对 Mozilla Readability 做差分（4/4 标题、平均 Jaccard 0.91）；
- 两套 MCP 端到端（stdio 10 断言、HTTP 7 断言）。

这套网让"改坏了"能被立刻发现，是敢做局部改造的前提。

### 2.4 决策可追溯

47 条 ADR，每条含背景 / 决策 / 后果 / **被否方案**。新人接手时能知道"为什么没选另一条路"，这比注释有用。

## 3. 问题清单（按影响排序）

### P0-1：`build_server` 一个函数 264 行

`mcp/server.mbt` 里 8 个工具全部在同一个函数里顺序注册，每个工具内联 schema 拼装 + 参数解析 + 业务调用 + 错误包装。后果：

- 加第 9 个工具时，这个函数只会更长；
- 任何一个工具改错，整个文件都要重新读；
- 无法单独测某个工具的契约。

**改法**：拆成 8 个 `fn tool_xxx() -> @mcpsdk.ToolWrapper`（或 provider 闭包），`build_server` 只做 `server = server.tool(...)` 的组装，长度降到 ~40 行。

### P0-2：`http` 包职责过宽

这个包同时装了：抓取（fetch）、安全策略（policy）、缓存（cache）、字符集（encoding）、命名（naming）、平台指纹（platform）、限流（ratelimit）、文本工具（util/json）、错误（error）——**9 类关注点**，公开 API 125 行，是第二宽的包（`core` 40 行）的 3 倍。

直接后果是**重复实现**：

| 重复函数 | 位置 1 | 位置 2 | 原因 |
| --- | --- | --- | --- |
| `find_sub` 字符串查找 | `extract/dom.mbt` | `md/convert.mbt` | `md` 只想要一个纯函数，但 `http` 依赖 `async`/`url`/`sha256`/`moon_encoding`，为它引入整套传输栈不划算 |
| `raw_dir` | `http/cache.mbt` | `index/store.mbt` | 抓取缓存与索引缓存各自实现路径规则 |
| 分行 | `http/util.mbt::split_lines` | `md/convert.mbt::split_lines_local` | 同上 |

**改法**：把纯文本工具抽成独立包 `core/text`（`find_sub`、`split_lines`、`json_escape`、`truncate_utf8`、`chars_of`/`substring_chars`），零依赖，谁都能用；`http` 只留传输与策略。这样 `md` / `index` 不需要为了一个字符串函数去依赖整个 `http`。

### P1-1：两个 500+ 行文件

- `extract/readability.mbt` 640 行：清洗 + 打分 + 容器选择 + 标题清洗 + 元数据，5 件事。
- `md/convert.mbt` 505 行：行内 / 块级 / 列表 / 表格 / 链接绝对化，5 件事。

**改法**：按关注点拆文件（同一包内拆文件是纯机械操作，零风险）。例如 `readability.mbt` → `clean.mbt` + `score.mbt` + `container.mbt` + `title.mbt` + `extract.mbt`。

### P1-2：`mcp` 包没有单元测试

392 行的协议适配层，只被外部 Python e2e 覆盖。e2e 需要起进程、耗时，且失败时定位难。

**改法**：补 6–8 个纯函数级测试（参数解析、schema 形状、`max_bytes` 截断、未知工具名、缺参数错误），不需要网络。

### P2：工作区里躺着一个外来仓库

`D:\moonbit-compition\_lunarrender` 是一个**独立的 git 仓库**（901 个文件，CMake + OpenGL，与本项目无关），目前未被跟踪、也未推送。风险：任何一次 `git add -A` 都会把它卷进提交。

**改法**：加进 `.gitignore`（已在本轮加入），或把它移出工作区。

## 4. 是否需要"重构"

| 方案 | 工作量 | 风险 | 建议 |
| --- | --- | --- | --- |
| 整体重写 | 数周 | **极高**：黄金文件、字节契约、MCP 协议细节都要重新验证 | ❌ 不要 |
| 定向改造（上文 4 项） | 1.5–2 天 | 低：每步都有回归网兜住 | ✅ 建议 |
| 只修 P0 两项 | 0.5–1 天 | 很低 | ✅ 最低成本方案 |

## 5. 改造顺序与验收

1. **`core/text` 抽包** → 让 `md` / `index` 复用，删掉 3 处重复；验收：全量测试 + 5 套外部校验不变。
2. **拆 `build_server`** → 8 个 `tool_xxx` + 40 行的组装函数；验收：两套 MCP e2e 仍全绿，工具清单不变。
3. **拆两个大文件** → 同包内纯移动；验收：`moon test` + 黄金文件逐字节一致。
4. **补 `mcp` 单测** → 6–8 个用例；验收：`moon test` 增加且全绿。

每步一个 commit，任一步失败可单独回滚（互不依赖）。
