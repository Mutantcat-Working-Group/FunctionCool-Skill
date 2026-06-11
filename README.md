<div align="center">
<img src="./logo.png" style="width:100px;" width="100"/>
<h2>FunctionCool Skill</h2>
<p><em> 为 Agent 提供"写代码"能力的轻量级 Skill</em></p>
</div>

###  一、功能简介

**FunctionCool Skill** 是一个面向 AI 编程助手（Claude Code / Cursor / Codex 等）的极简技能插件。它不携带任何模型权重、不依赖任何本地运行时，**仅由一份 Markdown 说明 + 三个跨平台脚本组成（Python 主实现 + bash 兼容 shim + PowerShell 兜底），整包 28KB**。

它能做的事情只有一件：**当你在写代码时，让模型在生成实现之前，先去 FunctionCool 函数库查一份"方法索引"，然后再由模型自己把函数写出来**。

#### 核心卖点

- 🚫 **无需下载** —— 不拉模型、不装依赖、不编译，clone 即用。
- 📦 **体积小** —— 整包 28KB，比一张截图还小。
- ⚡ **直接可用** —— 复制到 `~/.claude/skills/functioncool/`（Windows：`%USERPROFILE%\.claude\skills\functioncool\`）后，模型自动识别。
- 💰 **降低 Token 消耗** —— 用"查索引 + 写代码"代替"模型从零生成"，输出 token 砍掉一大半。
- 🖥️ **跨平台** —— Windows / macOS / Linux 行为一致；Windows 用户有 Python 和 PowerShell 两套入口可选。

###  二、基础用法

#### 1. 安装(以 Claude Code 为例)

**macOS / Linux:**
```bash
git clone https://github.com/Mutantcat-Working-Group/FunctionCool-Skill.git \
  ~/.claude/skills/functioncool
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/Mutantcat-Working-Group/FunctionCool-Skill.git `
  "$env:USERPROFILE\.claude\skills\functioncool"
```

安装后目录结构如下（**总共 28KB**）：

```
~/.claude/skills/functioncool/
├── SKILL.md              # 技能描述（自动加载）
├── scripts/
│   ├── query.py          # ★ 跨平台主实现（Windows / macOS / Linux）
│   ├── query.sh          # 兼容旧调用的 bash 转发脚本（自动调用 query.py）
│   └── query.ps1         # Windows 原生 PowerShell 兜底（无需 Python）
└── evals/
    └── evals.json        # 回归测试用例
```

重启 Claude / Cursor 即可。**无需配置 Token、无需登录、无需任何环境变量**——Token 硬编码在脚本里，直接调用。

> 💡 **跨平台调用方式**：
> - macOS / Linux：`python3 scripts/query.py "<关键词>" "<语言>"`
> - Windows（已装 Python）：`python "$env:USERPROFILE\.claude\skills\functioncool\scripts\query.py" "<关键词>" "<语言>"`
> - Windows（无 Python）：`powershell -ExecutionPolicy Bypass -File scripts\query.ps1 -Query "<关键词>" -Lang "<语言>"`
> - 旧版 `bash scripts/query.sh ...` 仍然兼容，会自动转发到 `query.py`。

#### 2. 使用

安装完成后，**直接用自然语言问模型写代码即可**，无需特殊指令。Skill 会在合适的场景下自动触发。

触发示例（中英文均可）：

```
用 Python 写个归并排序
give me a Go HTTP server that returns hello
How do I do binary search in Java?
写个 C 的 Modbus CRC16 校验函数
sort an array of numbers in Rust
```

模型返回的代码会带一个引用标签，例如：

```python
# [FunctionCool: PYTHON / Merge Sort / O(n log n) / timer 82]
def merge_sort(arr):
    ...
```

你可以一眼看出这段代码"参考了哪个函数的什么特性"，方便审计与追溯。

#### 3. 手动验证

想确认脚本工作正常？直接跑：

**macOS / Linux:**
```bash
python3 ~/.claude/skills/functioncool/scripts/query.py "merge sort" "PYTHON"
```

**Windows (PowerShell + Python):**
```powershell
python "$env:USERPROFILE\.claude\skills\functioncool\scripts\query.py" "merge sort" "PYTHON"
```

**Windows (PowerShell 原生,无 Python):**
```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\functioncool\scripts\query.ps1" -Query "merge sort" -Lang "PYTHON"
```

返回的是一份**精简版 JSON**（已经去掉了 `code` 字段）：

```json
{
  "query": "merge sort",
  "lang": "PYTHON",
  "count": 1,
  "results": [
    {
      "name": "Merge Sort",
      "lang": "PYTHON",
      "desc": "Stable divide-and-conquer sort",
      "input": ["arr"],
      "input_type": ["int[]"],
      "return": ["sorted"],
      "return_type": ["int[]"],
      "tags": ["sort", "algorithm"],
      "timer_score": 82,
      "memory_score": 90
    }
  ]
}
```

### 三、原理

#### 朴素做法的痛点

当你让模型"写个归并排序"，朴素流程是：

```
用户提问 ──► 模型直接吐完整源码（几十~几百行）──► 用户
                 │
                 ▼
        大量的"输出 token"
```

**输出 token 是贵的**——主流模型定价上，输出 token 普遍是输入 token 的 **5 倍**。一段 50 行的函数实现，输出成本可能比上下文还高。

#### FunctionCool 的解法：把"成本轴"翻转

FunctionCool Skill 把整个过程拆成两步，**把贵的输出变成便宜的输入**：

```
┌──────────────────────────────────────────────────────────────┐
│  Step 1: 查索引（输入 token，便宜）                            │
│                                                              │
│  模型 ──HTTP GET──► https://www.functioncool.xyz/skillapi    │
│       ◄── 精简 JSON ──     {name, signature, desc,           │
│                              complexity, tags, ...}          │
│                              （code 字段被脚本主动剥离）      │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│  Step 2: 写代码（输出 token，但有据可依、更短、更准）           │
│                                                              │
│  模型拿这份"方法索引"作为"目标清单"，自行写实现                 │
│  （不是抄代码，因为 code 字段根本没传过来）                     │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
                         用户拿到代码
```

#### 关键设计

1. **剥离 `code` 字段**
   脚本 `query.py`（以及转发它的 `query.sh` / 原生的 `query.ps1`）在拿到 API 返回后会**主动删掉 `code` 字段**。模型只看到"方法长什么样"，看不到"方法怎么写"——这强制模型自己写实现，避免照抄，也避免把大段源码塞进上下文。

2. **Prompt Cache 命中**
   FunctionCool 函数库的内容是稳定的。同一份索引会被反复查询，主流 API 都会对相同前缀做 prompt cache，**重复查询的边际成本接近零**。

3. **Token 流向倒转**

   | 阶段 | 朴素做法 | FunctionCool |
   ||||
   | 输入 token | 上下文 | 上下文 + **方法索引**（小） |
   | 输出 token | 完整源码（大） | 模型写的源码（更小、更准） |
   | 成本大头 | 输出 | 输入（且可缓存） |

4. **零本地状态**
   没有数据库、没有索引文件、没有 vector store。**28KB 全是元数据**——SKILL.md 告诉模型"什么时候用、怎么用"，`query.py`（+`query.sh`/`query.ps1` 入口）帮它调一次 HTTP。这就是为什么能"无需下载、体积小、直接可用"。

5. **跨平台脚本架构**
   `query.py` 是跨平台主实现（纯 Python stdlib，零外部依赖），`query.sh` 是 Unix 兼容 shim（自动转发到 `query.py`，旧调用习惯不破），`query.ps1` 是 Windows 原生 PowerShell 兜底（无 Python 也能跑）。三个脚本的 CLI 契约、JSON 输出、退出码完全一致。

#### 一句话总结原理

> **让模型先查一份"方法卡片"，再据卡片写代码——把贵的输出 token 换成便宜的、可缓存的输入 token。**

### 四、其他说明

#### API 契约

```
GET https://www.functioncool.xyz/skillapi
    ?token=mutantcat            （永久 Token，公开低权限）
    &q={url-encoded 查询词}
    &lang={C|CPP|GO|PYTHON|JAVA|JAVASCRIPT|RUST|MATLAB|PHP|RUBY|VERILOG|all}
```

#### 适用与不适用

✅ **适合**：写标准库函数、写常见算法、写教学/示例代码、模板生成。

❌ **不适合**：业务代码调试、跟用户特定项目强相关的逻辑、纯概念性问题。脚本在查不到结果时会优雅降级，模型直接靠自身知识回答，不加引用标签。

### 进阶：迭代 Skill 本身

- 想改触发条件？编辑 `SKILL.md` 顶部的 `description`。
- 想加语言？在 `query.py` 的 URL 构造或 `SKILL.md` 的 `LANG` 参数说明里加。
- 想加测试用例？往 `evals/evals.json` 追加。
