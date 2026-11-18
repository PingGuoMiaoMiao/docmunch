# 分节契约一致性套件（conformance kit）

这个套件检验的不是"docmunch 实现得对不对"，而是**任何一个分节实现是否满足下面这份契约**。
docmunch 只是第一个通过它的实现。

如果你在 MoonBit（或任何语言）里实现了文档分节，跑一遍这个检查就能知道自己的产出能不能被下游信任：

```sh
python conformance/check.py --index <你的 index.json> --raw <你的原文缓存目录>
```

## 契约（v1）

一份可验证的分节产出必须满足六条。前五条是结构性约束，第六条是确定性约束。

### C1 每个小节都有唯一 id

`section.id` 在同一个索引内唯一，且稳定：同样的输入、同样的版本，重复生成得到同样的 id。

### C2 字节区间连续且覆盖全文

对每份文档，按 `byte_start` 排序后：

- 第一个小节的 `byte_start == 0`；
- 相邻小节满足 `prev.byte_end == next.byte_start`（无空洞、无重叠）；
- 最后一个小节的 `byte_end == len(原始字节)`。

注意是**字节**，不是字符。UTF-8 下一个汉字是 3 字节。

### C3 区间落在字符边界上

`raw[byte_start]` 与 `raw[byte_end]` 不能是 UTF-8 续字节（`0b10xxxxxx`），否则取回会得到半个字符。

### C4 每节带内容哈希，且可重算

`section.content_hash == sha256(raw[byte_start:byte_end])`（十六进制小写）。

这条是"取回可自证"的基础：下游拿到一节，重算哈希就能确认自己读到的字节和索引里记的是同一份。

### C5 没有空小节

`byte_end > byte_start`。空节会让"取回成功"和"取回为空"变得无法区分。

### C6 确定性

同一输入、同一版本、同一参数，重复生成的索引必须**逐字节相同**。
套件本身不能替你跑两次生成器，但提供了 `--rerun` 参数让你指定一条命令，它会跑两次并比较输出。

## 用法

```sh
# 只检查已有索引
python conformance/check.py --index .doc-index/local/index.json --raw .doc-index/local/raw

# 顺便验证确定性：给出重新生成索引的命令（用 {out} 占位输出目录）
python conformance/check.py --index .doc-index/local/index.json --raw .doc-index/local/raw \
    --rerun "moon run cmd/main --target native -- index-dir docs --repo local --root {out}"
```

退出码：`0` = 全部通过；`1` = 有违规项（会逐条打印文档/小节/字节位置）。

## 被检查的索引格式

只要求最小字段集，不绑定人家内部结构：

```json
{
  "doc_paths": ["docs/p5-index.md"],
  "sections": [
    {
      "id": "repo::docs/p5-index.md::p5/1#2",
      "doc_path": "docs/p5-index.md",
      "title": "1. 存储布局",
      "level": 2,
      "byte_start": 1234,
      "byte_end": 2345,
      "content_hash": "9f2c…"
    }
  ]
}
```

`raw/<sha256(doc_path)>.bin` 是原文缓存的默认命名；如果你的实现用了别的命名，用 `--raw-pattern` 指定（支持 `{sha256}` 与 `{doc_path}` 占位）。

## 为什么需要它

定长切块（`RecursiveCharacterTextSplitter` 等）拿不出 C2/C4：切块边界随参数变化，切块对象里也没有指回原文的字节区间，所以下游无法回答"我读到的这段，是不是原文的那一段"。

标题感知切分（`MarkdownHeaderTextSplitter` 等）能拿到结构，但产出的文本是**重新渲染**的，不是原文切片，因此同样过不了 C4。

这份契约的价值不在"切得更好"，而在**让下游能验证**。docmunch 的 `--verify` 走的就是 C4。
