# 交付状态（收官）

> 2026-11-21 实测。这一页是**两个项目当前状态的唯一汇总**，其余文档都是细节。
> 每条都带命令，数字过期了自己重算。

## 一、能交的东西

| 项目 | 状态 | 硬截止 | 卡在哪 |
| --- | --- | --- | --- |
| **docmunch** | **可提交**：材料齐备、门禁全绿、已发布 0.3.1 | **11-30（剩 9 天）** | 你填飞书表单 |
| **chaossim** | **12 月线**：可提交，包已就绪未发布 | 12-01 报名 | `moon login` → publish |

## 二、实测数字

### docmunch

| 项 | 值 | 命令 |
| --- | --- | --- |
| 测试 | **116 / 116** | `moon test --target native` |
| 验收自检 | **8 PASS / 0 WARN / 0 FAIL** | `python tools/acceptance.py` |
| 文档一致性 | **7 / 7** | `python tools/consistency.py` |
| MoonCakes | **0.3.1 已发布**（另有 0.3.0 / 0.2.1 / 0.2.0） | `python tools/selfcheck.py --with-registry` |
| 打包就绪 | ✅ 解压重检通过 | `python tools/selfcheck.py --with-publish` |
| 外部可消费 | ✅ 从 registry 解析并跑通全链路 | `python tools/consumer_check.py --version 0.3.1` |
| 代码量 | 9,296 行 / 65 个 `.mbt`（测试 18 文件 1,898 行） | 见申报书 §基本信息 |

### chaossim

| 项 | 值 | 命令 |
| --- | --- | --- |
| 测试 | **74 / 74** | `moon test --target native` |
| 验收自检 | **8 PASS / 0 WARN / 0 FAIL** | `python tools/acceptance.py` |
| 文档一致性 | **7 / 7** | `python tools/consistency.py` |
| 靶子 | **4 个，2 个域**（MQTT / AMQP 1.0 / AMQP 0-9-1 broker / MVCC 事务引擎） | `moon run adapters/*/bin` |
| 体检项 | 消息域 11 + 事务域 10 = **21** | `moon run adapters/*/checkup` |
| 交错扫描 | **320 次运行，0 违规** | `moon test` |
| 性能 | 493–570 ns / 调度步 | `moon run cmd/perf --release` |
| 发布状态 | 未发布；`dry-run` 通过、zip **0 泄漏** | `python tools/selfcheck.py --with-publish` |

## 三、收官巡检结果

**21 条证据命令全部通过，0 失败**（2026-11-21）：

- docmunch 11 条：acceptance / consistency / markdown_golden / toc_check / conformance /
  mcp_e2e / mcp_http_e2e / mcp_auth_e2e / selfindex / consumer_check / selfcheck(全档)
- chaossim 10 条：moon test / 四个 transcript / 两份体检报告 / cmd/main / quickstart /
  selfcheck(含外部消费) / consumer_check

两个仓库 CI 均绿，工作区均干净。

## 四、只有你能做的三件事

| # | 动作 | 具体 |
| --- | --- | --- |
| 1 | **docmunch 飞书表单** | 正文粘 `docs/registration.md`；数字取 `docs/status.md`；**剩 9 天** |
| 2 | **chaossim 发布** | `moon login` → `cd D:\chaossim` → `moon publish` → `python tools/selfcheck.py --with-registry` 确认 |
| 3 | 微信群昵称改 GitHub ID | 官方写明影响奖金发放 |

## 五、必须如实写进表里的限制

不要"顺手美化"，这几条评委可以当场核：

- **docmunch**：采用数 0（依赖 0 / star 1 / fork 0 / issue 0）；检索质量与 LangChain
  标题切分器同级且两项各落后 1 题；盲测准确率打平，差异只在成本。
- **chaossim**：未在任何靶子上发现 bug；体检报告的**观测层未验证**（判定层已证）；
  未发布；不主张"比 Jepsen 更强"。

## 六、如果还要继续投入，只有两个方向有真实收益

1. **docmunch 的采用故事**：把 `docs/reports/independent-verification.md` 整理成给
   `moon-mqtt` / `moonamqp1` 的 Discussion 或 PR——这是 9 天内唯一能产生"外部协作"
   证据的动作，且需要你的 GitHub 身份。
2. **chaossim 换更稚嫩的靶子**：四个靶子全部零缺陷，说明选的都是成熟库。
   想拿到"发现问题"的证据，只能换目标，不能靠加代码。
