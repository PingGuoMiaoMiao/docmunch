# 采用记录（Adoption record）

- 时间：2026-11-19
- 原则：**只记录可核对的数字，不把"发布"当"采用"**。下面每条都能自己查。

## 1. 分发与访问（原始数据）

| 指标 | 数值 | 来源 |
| --- | --- | --- |
| MoonCakes 下载 | **35** | `mooncakes.io/api/v0/manifest/PingGuoMiaoMiao/docmunch` → `downloads` |
| MoonCakes 已发布版本 | 0.3.0 / 0.2.1 / 0.2.0 | 同上 → `versions` |
| MoonCakes 依赖者 | **0** | 同上 → `dependents` |
| GitHub Star / Fork / Issue | 0 / 0 / 0 | `gh api repos/PingGuoMiaoMiao/docmunch` |
| 仓库克隆（近 14 天） | **180 次 / 67 个独立来源** | `gh api …/traffic/clones` |
| 提交数 | 68 | `git log --oneline | wc -l` |

**怎么读**：35 次下载和 67 个独立克隆说明**有人在看**；0 依赖者、0 star、0 fork 说明**还没有人把用起来的外部证据留下来**。这两件事不能混为一谈——所以本文件不把"下载量"写成"被采用"。

## 2. 可消费性证明（比下载量更硬）

下载量可以是误点。能证明这个包**真的能被外部模块用起来**的是下面这条可复跑检查——
它不只验证"能编译"，而是在**已发布版本**上跑完整链路：建索引 → BM25 检索 →
按 id 取回该节并校验 sha256。

实测输出（`--version 0.3.0`）：

```
sections=3          # 3 个标题 → 3 节
hits=2              # 查询 widget 命中 Install / Usage，各 score=44
fetched_bytes=39
hash_verified=true  # 按字节区间取回并重算哈希
contains_widget=true
```

```sh
python tools/consumer_check.py --version 0.3.0
```

它做的是：

1. 在临时目录新建一个**独立的 MoonBit 模块**（不引用本仓库、不用本地路径）；
2. 在 `moon.mod` 里写下 `"PingGuoMiaoMiao/docmunch@0.3.0"`（registry 版本）；
3. 在 `moon.pkg` 里 import `…/core` 与 `…/core/text`；
4. `moon build --target native` 并**运行**产物。

实测输出：

```
consuming PingGuoMiaoMiao/docmunch@0.3.0 from the registry
build: ok
run output:
  section=demo::docs/a.md::intro#1
  slug=hello-world
  index_version=4
  cjk_bigrams=3
  lines=2
consumer check passed
```

含义：**发布出去的那个版本、走 registry 解析、在一个外部模块里能编译能运行。** 这是"可分发性"的证据，不是"采用"的证据——但它是采用的前提。

## 3. 契约可被外部实现满足（生态增量的可验证形式）

主张"我提供了一套可被采纳的分节契约"，必须证明它不是只对自家实现成立。`conformance/reference_impl.py` 是一个**约 70 行、与 docmunch 无任何代码共享的 Python 实现**，按同一份 `SPEC.md` 产出索引；`conformance/check.py` 用它来判：

```
$ python conformance/reference_impl.py --src docs/p5-index.md --out /tmp/ref
wrote 8 sections -> /tmp/ref/index.json

$ python conformance/check.py --index /tmp/ref/index.json --raw /tmp/ref/raw
checked 8 sections against C1-C5
all rules passed
```

两个不同语言、不同代码库的实现，跑同一套检查都通过——这才叫"契约"，而不是"我的实现恰好符合我自己的描述"。反过来，`conformance/selftest.py` 会故意破坏索引的五种方式，确认检查器真的会报错，避免"什么都通过"的假检查器。

## 4. 什么才算真正的采用（判据，写在这里方便以后核对）

按强度从弱到强，只有后三条能写进"采用记录"：

| 强度 | 事件 | 现状 |
| --- | --- | --- |
| 弱 | 下载 / 克隆 / star | 35 / 180 / 0 |
| 中 | 外部项目在 `moon.mod` 里依赖 `PingGuoMiaoMiao/docmunch` | **0** |
| 中 | 外部实现通过 `conformance/check.py` 且把自己的通过结果贴出来 | **0** |
| 强 | 有 commit 的 fork、issue、PR | **0** |
| 强 | 被别的 MoonBit 工具当作库调用（MCP 工具面或分节契约） | **0** |

现在的记录是：**分发已建立、可消费性已证明、契约可移植性已证明；外部采用为 0。**

这不是修辞上的谦虚——它决定了申报书里不能写"已被采用"，只能写"已发布且可被采用，并给出了可核对的接入方式"。

## 5. 别人怎么接入（3 步）

```sh
# 1. 作为库使用（MoonBit）
moon add PingGuoMiaoMiao/docmunch
# 2. 只想要"按节检索"的接口
moon run cmd/main --target native -- index-dir docs --repo local
moon run cmd/main --target native -- mcp          # 13 个 MCP 工具
# 3. 有自己的实现？用契约自检，不需要装 docmunch
python conformance/check.py --index <你的 index.json> --raw <你的原文缓存>
```

## 6. 更新方式

```sh
gh api repos/PingGuoMiaoMiao/docmunch --jq '{stars:.stargazers_count,forks:.forks_count}'
gh api repos/PingGuoMiaoMiao/docmunch/traffic/clones --jq '{count,uniques}'
curl -s https://mooncakes.io/api/v0/manifest/PingGuoMiaoMiao/docmunch | jq '{downloads,dependents}'
python tools/consumer_check.py
```

建议每两周把这张表更新一次；数字变差也要照写。
