# P7 交付：指标、验收自检与已知差距

- 时间：2026-11-08
- 目标：把 P0–P6 的成果做成可复现、可评审、可继续演进的开源项目
- 结论：**49 个单测 + 4 套外部校验全部通过；6 条赛事验收标准逐条有证据**

## 1. 总指标

| 指标 | 结果 | 验证方式 |
| --- | --- | --- |
| 单元/集成测试 | **49/49 通过** | `moon test` |
| 抽取：标题匹配 | **4/4** | `python tools/compare.py` |
| 抽取：平均长度比 / Jaccard | **1.03 / 0.91** | 同上 |
| Markdown 黄金文件 | **4/4 无漂移** | `python tools/markdown_golden.py` |
| 分节字节契约 | **4/4 通过** | `python tools/toc_check.py` |
| MCP 端到端 | **10/10 断言** | `python tools/mcp_e2e.py` |
| 索引耗时（单文档） | 54–182 ms | `python tools/bench.py` |
| 检索 / 取回（含进程启动） | 19.7 / 19.5 ms（基线 20.1 ms） | 同上 |

> 检索与取回的"实际计算"在毫秒以下——中位数与 `repos` 空命令的基线持平，CLI 成本主要是进程启动。MCP 常驻进程下这两条路径是纯内存 + 一次 `read_at`。

## 2. 赛事验收六条 → 证据

| 验收项 | 本项目对应证据 |
| --- | --- |
| MoonBit 为主实现语言 | 全部源码为 `.mbt`（8 个包）；仅有 Python/Node 的**测试与校验脚本**，不参与运行时 |
| 仓库公开、提交可追踪 | 7 次语义化提交，每个阶段一份设计文档 + ADR |
| 能够运行（README/示例/测试） | `moon build` + `moon test` 一条命令；README 列出全部 CLI 子命令 |
| 工作有效（本期实质新增） | 从空目录到可用的 fetch→extract→markdown→section→index→MCP 全链路 |
| 开源合规 | Apache-2.0（`LICENSE`）；第三方依赖逐个记录在 `moon.mod`，fixtures 来源在 `fixtures/README.md` 标注 |
| AI 可解释 | `docs/` 下 6 份阶段文档 + 34 条 ADR（含被否方案），记录每次取舍与踩坑 |

## 3. 交付物清单

```
core/  section/  index/  mcp/  http/  extract/  md/  cmd/main/   # 8 个 MoonBit 包
docs/pre-research.md  decisions.md  p1-smoke.md  p2-extraction.md
docs/p3-markdown.md   p4-sectioning.md  p5-index.md  p6-mcp.md  p7-delivery.md
fixtures/html/*.html（4 个真实页面快照）
fixtures/markdown/*.md（4 份黄金文件）
tools/compare.py  markdown_golden.py  toc_check.py  mcp_e2e.py  bench.py
tools/oracle/（Node 版 Readability 期望值，仅测试期使用）
.github/workflows/ci.yml
```

## 4. 端到端演示（一条命令链）

```sh
moon build --target native

# 1. URL -> 正文 -> Markdown -> 分节 -> 索引
moon run cmd/main --target native -- index https://docs.moonbitlang.cn/language/ffi.html

# 2. 检索
moon run cmd/main --target native -- search docs.moonbitlang.cn "ffi"

# 3. 按 id 取回（哈希校验）
moon run cmd/main --target native -- section docs.moonbitlang.cn "<id>" --verify

# 4. 挂到 MCP 客户端
moon run cmd/main --target native -- mcp
```

## 5. 已知差距（诚实的部分）

| 差距 | 现状 | 影响 |
| --- | --- | --- |
| arXiv 类页面抽取偏窄 | 长度比 0.87、Jaccard 0.77 | 元数据头（提交时间/作者）被算进正文；不影响分节正确性 |
| Sphinx 页面抽取偏宽 | 长度比 1.27 | 已加链接密度裁剪（1.33 → 1.27），仍有目录型区块残留 |
| 无 JS 渲染 | 纯 CSR 页面只能拿到空壳 | 文档站多为 SSR/SSG，影响面小 |
| MCP 只有 stdio、无认证 | 本机单用户可用 | 远程接入前必须补 |
| 检索不覆盖正文 | 只在标题/路径打分 | 词只出现在正文时会漏（有 `get_section` 兜底） |
| 并发索引无锁 | 单进程场景 | MCP 服务端内串行执行，可接受 |

## 6. 复现全部证据

```sh
moon test
moon build --target native
python tools/compare.py          # 需要 tools/oracle/out 的期望值（已入库）
python tools/markdown_golden.py
python tools/toc_check.py
python tools/mcp_e2e.py
python tools/bench.py
```
