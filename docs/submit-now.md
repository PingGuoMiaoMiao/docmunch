# 提交清单（照着做，不用再读别的文档）

> 取数一律看 [status.md](status.md)；每一条都写了怎么重算，别从记忆里抄数字。
> 本页只列"你要动手的事"和"动手前应该看到的结果"。

## 一、现在到 11-30 之间要做的（硬截止）

| # | 动作 | 说明 |
| --- | --- | --- |
| 1 | 填飞书报名表 | 正文直接粘 [registration.md](registration.md)；数字从 [status.md](status.md) 取 |
| 2 | 加入微信群，昵称改成 GitHub ID | 官方写明这影响奖金发放 |
| 3 | 提交后自留一份快照 | 报名表提交页截图或存档，用于万一需要证明"我按时交了" |

**不要做的事**：不要改版本号、不要为了"更新"而重新 publish（registry 上 0.3.1 已存在，
重复发布会 409）。提交期间代码保持现状最安全。

## 二、动手前应该看到的结果（任何一项不符就先停下）

```sh
python tools/selfcheck.py --with-registry --with-publish
```

期望最后一行：

```
17 checks: 17 pass, 0 warn, 0 skip, 0 fail
```

其中两条关键：

```
PASS  Registry    registry: latest=0.3.1, versions=4, downloads=50; claims agree
PASS  dry-run     current version 0.3.1 is already published on the registry ... package itself validated
```

如果 `Registry` 报 FAIL，说明文档里的下载数或版本号已经过期——按提示改成实际值再提交。

## 三、评审会跑的命令（你应该自己先跑一遍）

| 命令 | 期望 |
| --- | --- |
| `moon build --target native` | 成功 |
| `moon test` | **116/116** |
| 30 秒演示（README 顶部四条命令） | 见 README 里那段输出，逐行一致 |
| `python tools/acceptance.py` | 8 pass / 0 fail |
| `python tools/consistency.py` | 7 ok / 0 fail |

全新 clone 也能跑通（空目录 clone 后 `moon test` 116/116，约 18 秒，含依赖下载）。

## 四、提交时如实写清楚的三条限制

这三条已经写在 `docs/status.md` 和 `registration.md` 里，别在填表时"顺手美化掉"：

1. **采用数很低**：依赖者 0、star 1、fork 0、issue 0。`docs/adoption.md` 列了"什么才算
   真采用"，当前四项全为 0——所以不主张"已被采用"。
2. **检索质量与 LangChain 标题切分器同级**，两个指标各落后 1 题（hit@5 14/18 vs 15/18、
   完整性 13/18 vs 14/18）。不主张"切得更好"，主张的是**可验证性**。
3. **盲测中三种策略准确率打平**，差异只在成本（docmunch 13,064 token vs 定长切分
   17,117 vs 整篇 20,275）。不主张"回答更准"。

## 五、12 月那条线（chaossim，不急）

| 动作 | 说明 |
| --- | --- |
| 12-01 报名 | 参赛材料见 `D:\chaossim\docs\registration-dec.md` |
| `moon login` → `moon publish` | 包已 `202 Accepted`，发布后"生态增量"从"未发布"变成"可安装" |
| 可选 | 把 `docs/reports/independent-verification.md` 整理成给上游的 Discussion |

chaossim 交付前自检：

```sh
cd D:\chaossim
python tools/selfcheck.py --with-consumer
moon run adapters/moonmq/checkup --target native
moon run adapters/moontxnkit/checkup --target native
```

## 六、我这边已经验证过的（2026-11-20 收尾巡检）

20 条证据命令全部通过，0 失败：

- docmunch：acceptance / consistency / markdown_golden / toc_check / conformance /
  mcp_e2e / mcp_http_e2e / mcp_auth_e2e / selfindex / consumer_check
- chaossim：moon test / 四个 transcript / 两份体检报告 / cmd/main / quickstart /
  selfcheck / consumer_check
- 两个仓库 CI 均绿，工作区均干净
