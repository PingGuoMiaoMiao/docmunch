# P1 冒烟结果：fetch + platform detect

- 时间：2026-11-08
- 命令：`main.exe smoke fixtures/smoke-urls.txt`（10 个真实文档站，5 MB 上限 / 20 s 超时）
- 环境：Windows native，`moon 0.1.20261028`，`moonbitlang/async@0.22.7`
- 结论：**10/10 成功**，全部写入 `.doc-index/raw/` 缓存（键为 URL 的 sha256）

| # | URL | 状态 | 字节 | 平台 | 耗时 ms |
| --- | --- | --- | --- | --- | --- |
| 1 | https://www.moonbitlang.cn/updates/2026/11/05/index | 200 | 107,517 | moonbit | 794 |
| 2 | https://docs.moonbitlang.cn/language/ffi.html | 200 | 118,102 | moonbit | 1,436 |
| 3 | https://github.com/mozilla/readability | 200 | 309,349 | github | 1,208 |
| 4 | https://arxiv.org/abs/2509.11552 | 200 | 41,759 | generic | 1,242 |
| 5 | https://developer.mozilla.org/en-US/docs/Web/HTTP | 200 | 222,375 | generic | 1,077 |
| 6 | https://kubernetes.io/docs/home/ | 200 | 500,889 | generic | 742 |
| 7 | https://docs.python.org/3/library/asyncio.html | 200 | 25,411 | sphinx | 723 |
| 8 | https://doc.rust-lang.org/book/ch01-00-getting-started.html | 200 | 22,877 | generic | 366 |
| 9 | https://docs.rs/regex/latest/regex/ | 200 | 113,034 | generic | 1,292 |
| 10 | https://www.sphinx-doc.org/en/master/usage/quickstart.html | 200 | 32,900 | sphinx | 1,752 |

## 首轮的两个瞬时失败（重试即恢复）

| URL | 首轮错误 | 重试 | 判断 |
| --- | --- | --- | --- |
| https://arxiv.org/abs/2509.11552 | `network_error: OSError("@socket.Tcp::read(): The network connection was aborted by the local system.")` | 200 / 41,759 B | 服务端或链路瞬时重置，非实现缺陷 |
| https://developer.mozilla.org/... | `dns_error: cannot resolve host` | 200 / 222,375 B | 本机 DNS 瞬时失败（耗时 12 s），非实现缺陷 |

> 这两条说明 `DnsError` / `NetworkError` 的错误码拆分是对的：能区分"解析失败"和"连接被重置"，重试策略可以据此分级。

## 平台识别观察

- `docs.python.org` 与 `sphinx-doc.org` 首轮被误判为 `readthedocs`，原因是 HTML 里同时含 `readthedocs` 与 `sphinx` 标记；已把 marker 顺序改为 **sphinx 优先**，`*.readthedocs.io` 仍由域名规则命中 `ReadTheDocs`。
- `kubernetes.io` / `docs.rs` / MDN / Rust Book 判为 `generic`：这几个站点没有稳定的框架标记，符合预期（P2 的抽取不能依赖平台标签）。
- `moonbitlang.cn` / `moonbitlang.com` 由域名规则命中，不依赖页面标记。

## 复现

```sh
moon build --target native
moon run cmd/main --target native -- smoke fixtures/smoke-urls.txt
```

缓存落在 `.doc-index/raw/`（已被 `.gitignore` 忽略），可直接用 `xxd` 对比原站内容校验字节一致性。
