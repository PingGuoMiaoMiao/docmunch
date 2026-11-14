# P7 交付：指标、验收自检与已知差距

- 时间：2026-11-08
- 目标：把 P0–P6 的成果做成可复现、可评审、可继续演进的开源项目
- 结论：**79 个单测 + 7 套外部校验全部通过；6 条赛事验收标准逐条有证据**

## 1. 总指标

| 指标 | 结果 | 验证方式 |
| --- | --- | --- |
| 单元/集成测试 | **79/79 通过** | `moon test` |
| 抽取：标题匹配 | **4/4** | `python tools/compare.py` |
| 抽取：平均长度比 / Jaccard | **1.03 / 0.91** | 同上 |
| Markdown 黄金文件 | **4/4 无漂移** | `python tools/markdown_golden.py` |
| 分节字节契约 | **4/4 通过** | `python tools/toc_check.py` |
| MCP 端到端（stdio / HTTP） | **10/10、7/7** | `python tools/mcp_e2e.py` / `tools/mcp_http_e2e.py` |
| 验收自检 | **7 PASS / 0 FAIL** | `python tools/acceptance.py` |
| MCP 端到端（stdio） | **10/10 断言** | `python tools/mcp_e2e.py` |
| MCP 端到端（HTTP） | **6/6 断言** | `python tools/mcp_http_e2e.py` |
| 索引耗时（单文档） | 42–148 ms | `python tools/bench.py` |
| 检索 / 取回（含进程启动） | 18.9 / 19.1 ms（基线 19.6 ms） | 同上 |

> 检索与取回的"实际计算"在毫秒以下——中位数与 `repos` 空命令的基线持平，CLI 成本主要是进程启动。MCP 常驻进程下这两条路径是纯内存 + 一次 `read_at`。

## 2. 赛事验收六条 → 证据

> 同一套规则已有脚本实现 `tools/acceptance.py`（也是 `moonbit-hackathon-acceptance` skill 的副本），一条命令产出 PASS/WARN/FAIL 表；下表是人工可读的证据版本。

| 验收项 | 本项目对应证据 |
| --- | --- |
| MoonBit 为主实现语言 | 全部源码为 `.mbt`（8 个包）；仅有 Python/Node 的**测试与校验脚本**，不参与运行时 |
| 仓库公开、提交可追踪 | 12 次语义化提交，每个阶段一份设计文档 + ADR |
| 能够运行（README/示例/测试） | `moon build` + `moon test` 一条命令；README 列出全部 CLI 子命令 |
| 工作有效（本期实质新增） | 从空目录到可用的 fetch→extract→markdown→section→index→MCP 全链路 |
| 开源合规 | Apache-2.0（`LICENSE`）；第三方依赖逐个记录在 `moon.mod`，fixtures 来源在 `fixtures/README.md` 标注 |
| AI 可解释 | `docs/` 下 8 份阶段文档 + 41 条 ADR（D1–D41，含被否方案），记录每次取舍与踩坑 |

## 3. 交付物清单

```
core/  section/  index/  mcp/  http/  extract/  md/  cmd/main/   # 8 个 MoonBit 包
docs/pre-research.md  decisions.md  p1-smoke.md  p2-extraction.md
docs/p3-markdown.md   p4-sectioning.md  p5-index.md  p6-mcp.md  p7-delivery.md  p8-enhancements.md
fixtures/html/*.html（4 个真实页面快照）
fixtures/markdown/*.md（4 份黄金文件）
tools/compare.py  markdown_golden.py  toc_check.py  mcp_e2e.py  mcp_http_e2e.py  bench.py
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

## 5. 本轮修复（2026-11-08 审计 + 2026-11-10 迭代）

两轮审计发现的 P0/P1 问题都修在源码里，并补了回归测试；取舍与拒绝的方案见 **D37–D47**。

| 修复 | 之前 | 现在 |
| --- | --- | --- |
| repo 目录身份 / delete | 只把 `/` 换成 `_`，`"a b"` 与 `"a_b"` 共用目录；delete 由调用方拼路径 | `repo_key` 单射映射 + `repo.json` 保存原始 label；`delete_repo` 幂等（D37） |
| URL doc_path 覆盖 | 只取 URL 最后一段，同 host 的 `a/index.html` 与 `b/index.html` 互相覆盖 | 全 pathname + query/fragment 哈希，`a/index.html.md` 与 `b/index.html.md` 共存（D38） |
| toc 与 index 路径不一致 | `toc` 保留 `\`，与 `index`/`search` 的 section id 不同 | 两处共用 `normalize_local_path`，id 逐字节一致（D38） |
| MCP 响应无上限 | `get_section*` 直接返回整节 | `max_bytes`（默认 8000，0/-1 不截断）+ `truncated` / `total_bytes`（D39） |
| fetch 缓存不可读、无重试 | 只写缓存；网络错误直接失败 | `load_cached` 还原 status/type、epoch TTL、仅 `NetworkError` 重试（D40） |
| frontmatter 假标题 | closing `---` 被 setext 规则误判，frontmatter 内容成一节 | 识别并跳过 YAML frontmatter，字节归入 preamble（D41） |
| 代码块空行被压缩 | 全局压空行，代码块内连续空行丢失 | 围栏感知：围栏内逐行保留，围栏外最多 1 个空行（D41） |
| 极简 HTML 抽取死循环 | 候选容器直接挂 body 时，折叠/unwrap 循环对 document 节点空转 | 父节点为 body 时直接返回，两个循环都以 document 根为边界（D42） |
| HTTP MCP 并发写索引 | 并发 `index_*` 读改写互相覆盖（实测 3/3 丢文档） | 单把共享 Mutex 串行化三个写工具，e2e 增加并发断言（D44） |
| DNS rebinding | 单次解析后被客户端二次解析绕过 | 请求前二次解析拦截 + 文档标注为缓解，未声称修复（D43） |
| 非 UTF-8 页面乱码 | GBK/Big5 被当 UTF-8 lossy 解码 | 按 WHATWG label 真转码（`moon_encoding`），未知标签才回退并置 warning（D45） |
| 缓存命中丢 final_url | 重定向后的页面从缓存读时身份变成请求 URL | 缓存 meta 的 final_url 参与结果与平台指纹（D46） |
| JSON 派生弃用警告 | `derive(ToJson, FromJson)` 触发 4 条 `implicit_impl_as_method` | 追加显式 `extend`，警告清零；工具链升级后仍可编译（D47） |
| stderr / stdout 混用 | 错误与正常结果都走 stdout | 诊断走 `fail()` → stderr，stdout 只留数据 |
| 编译与测试卫生 | MCP SDK 与本地包同名告警；fetch 测试端口写死 | SDK 别名 `@mcpsdk`；fetch 测试改用动态端口 |

验证：`moon check --target native` 0 errors（3 条存量 warning：2×`result_error_return` + 1×`unused_package`）、`moon test` 79/79、`moon build` 成功；7 套外部校验全绿（compare 4/4、markdown_golden 4/4、toc_check 4/4、mcp_e2e 10/10、mcp_http_e2e 7/7、bench 正常出数、acceptance 7 PASS）。

## 6. 已知差距（诚实的部分）

| 差距 | 现状 | 影响 |
| --- | --- | --- |
| DNS rebinding | SSRF 校验后客户端会再解析一次域名 | 已加请求前二次解析拦截（窗口变窄但未消除）；根治需要 pinned-IP 客户端（D43） |
| HTTP 并发 | MCP 工具内已用共享 Mutex 串行化三个写工具（D44）；跨进程/多实例仍无锁 | 单进程单用户可用；多实例共享索引目录时需外部锁 |
| 无认证 | MCP HTTP 端点无鉴权，默认只监听 `127.0.0.1` | 暴露到公网前必须加认证或反向代理 |
| arXiv 类页面抽取偏窄 | 长度比 0.87、Jaccard 0.77 | 元数据头（提交时间/作者）被算进正文；不影响分节正确性 |
| Sphinx 页面抽取偏宽 | 长度比 1.27 | 仍有目录型区块残留 |
| 无 JS 渲染 | 纯 CSR 页面只能拿到空壳 | 文档站多为 SSR/SSG，影响面小 |
| 中文检索 | 无分词，`terms` 只收 ASCII 词；中文查询靠标题/路径命中 | 中文文档的正文召回弱于英文 |
| 增量范围 | 只跳过"字节完全相同"的文档；局部修改仍整篇重解析 | 大文档改一行也要重切，但比全量重建好 |
| 目录索引是单进程串行 | `index-dir` 逐个文件处理，没有并发抓取 | 抓远程站点的目录树时偏慢 |
| 无词干化 / 无倒排缓存 | `documents` 与 `document` 不合并；每次查询全量扫描小节 | 千级小节内仍是毫秒级，上万后需要倒排 |

## 7. 复现全部证据

```sh
# compare.py 的 MoonBit 侧快照默认不提交，先按 fixtures 生成
mkdir -p tools/oracle/out-moonbit
for f in fixtures/html/*.html; do
  name=$(basename "$f" .html)
  moon run cmd/main --target native -- extract "$f" > "tools/oracle/out-moonbit/$name.json"
done

moon check --target native
moon test
moon build --target native
python tools/compare.py          # 需要 tools/oracle/out 的期望值（已入库）
python tools/markdown_golden.py
python tools/toc_check.py
python tools/mcp_e2e.py
python tools/mcp_http_e2e.py
python tools/bench.py
```
