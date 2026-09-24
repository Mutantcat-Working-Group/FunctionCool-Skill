<div align="center">
<img src="https://raw.githubusercontent.com/Mutantcat-Working-Group/FunctionCool-Skill/main/logo.png" style="width:100px;" width="100"/>
<h2>FunctionCool Skill</h2>
<p><em>给 AI 编程助手装上「函数库检索」能力</em></p>
</div>

**发行方**：由异猫工作群（mutantcat.org）发行 · GitHub: <https://github.com/Mutantcat-Working-Group>

> 一个装在 Claude Code / Cursor / Codex 等 AI 编程助手里的轻量技能插件。
> 模型写实现之前，先去 FunctionCool 函数库查一份方法索引，再据此写代码。

### 一、产品概述

- FunctionCool Skill 面向 AI 编程助手（Claude Code / Cursor / Codex 等），是一个极简技能插件
- 整包只有一份 Markdown 说明 + 三个跨平台脚本（Python 主实现 + bash 兼容 shim + PowerShell 兜底），约 28KB
- 不携带模型权重、不依赖本地运行时、不拉依赖、不编译，clone 即用
- 它能做且只做一件事：让模型在生成实现之前，先查一份「方法卡片」，然后由模型自己把函数写出来
- 生成的代码带引用标签（如 `[FunctionCool: PYTHON / Merge Sort / O(n log n) / timer 82]`），出处可审计

核心价值：主流模型定价里输出 token 通常是输入的 5 倍。这个 Skill 把贵的「从零生成」换成便宜的「查索引 + 自行实现」，既省 token，又让代码有据可依。

### 二、工作方式

朴素流程是「用户提问 → 模型直接吐完整源码 → 用户」，几十到几百行全砸在输出 token 上。FunctionCool Skill 把它拆成两步：

第一步，查索引（输入 token，便宜）：模型向 `https://www.functioncool.xyz/skillapi` 发一次 HTTP GET，拿回一份精简 JSON——函数名、签名、描述、复杂度、标签、耗时与内存评分。脚本会主动删掉 `code` 字段，模型只看得到「方法长什么样」，看不到「方法怎么写」。

第二步，写代码（输出 token，更短更准）：模型拿这份方法索引当目标清单，自行写实现。不是抄代码，因为源码根本没传过来。

三个关键设计：

- 剥离 `code` 字段：强制模型理解后自己写，避免照抄，也避免把大段源码塞进上下文
- Prompt Cache 命中：函数库内容稳定，同一份索引被反复查询，重复查询的边际成本接近零
- 零本地状态：没有数据库、没有索引文件、没有 vector store，28KB 全是元数据

一句话：让模型先查一份方法卡片，再据卡片写代码——把贵的输出 token 换成便宜的、可缓存的输入 token。

### 三、功能说明

#### 查询能力

- 支持语言：`C`、`CPP`、`GO`、`PYTHON`、`JAVA`、`JAVASCRIPT`、`RUST`、`MATLAB`、`PHP`、`RUBY`、`VERILOG`、`all`
- 返回字段：`name`、`lang`、`desc`、`input` / `input_type`、`return` / `return_type`、`tags`、`timer_score`、`memory_score`
- 中文、英文查询词都能命中，查不到结果时脚本优雅降级，模型直接靠自身知识回答，不加引用标签

#### 触发场景

直接用自然语言提问即可，Skill 会在合适场景自动触发：

```text
用 Python 写个归并排序
give me a Go HTTP server that returns hello
写个 C 的 Modbus CRC16 校验函数
sort an array of numbers in Rust
```

#### 跨平台脚本

- `query.py`：跨平台主实现，纯 Python 标准库，零外部依赖
- `query.sh`：bash 兼容 shim，自动转发到 `query.py`，旧调用习惯不破
- `query.ps1`：Windows 原生 PowerShell 兜底，不装 Python 也能跑
- 三个脚本的 CLI 契约、JSON 输出、退出码完全一致

#### 适用与不适用

适合写标准库函数、常见算法、教学与示例代码、模板生成。不适合业务代码调试、与具体项目强耦合的逻辑、纯概念性问题。

### 四、安装与下载

本仓库当前以源码形式发布，无预编译产物，也不需要：clone 到技能目录即可用。

macOS / Linux：

```bash
git clone https://github.com/Mutantcat-Working-Group/FunctionCool-Skill.git \
  ~/.claude/skills/functioncool
```

Windows（PowerShell）：

```powershell
git clone https://github.com/Mutantcat-Working-Group/FunctionCool-Skill.git `
  "$env:USERPROFILE\.claude\skills\functioncool"
```

装完重启 Claude / Cursor 即生效。无需配置 Token、无需登录、无需任何环境变量——公开低权限 Token 已内置在脚本里。

安装后目录结构（约 28KB）：

```text
~/.claude/skills/functioncool/
├── SKILL.md              # 技能描述（自动加载）
├── scripts/
│   ├── query.py          # 跨平台主实现（Windows / macOS / Linux）
│   ├── query.sh          # 兼容旧调用的 bash 转发脚本
│   └── query.ps1         # Windows 原生 PowerShell 兜底（无需 Python）
└── evals/
    └── evals.json        # 回归测试用例
```

跨平台调用方式：

- macOS / Linux：`python3 scripts/query.py "<关键词>" "<语言>"`
- Windows（已装 Python）：`python "…\scripts\query.py" "<关键词>" "<语言>"`
- Windows（无 Python）：`powershell -ExecutionPolicy Bypass -File scripts\query.ps1 -Query "<关键词>" -Lang "<语言>"`
- 旧版 `bash scripts/query.sh "…"` 仍然兼容，会自动转发到 `query.py`

### 五、快速上手

1. 按上文把仓库 clone 进技能目录，重启助手。
2. 直接问「用 Python 写个归并排序」，模型会自动触发查询。
3. 拿到的代码头部带 `[FunctionCool: …]` 引用标签，一眼看出参考了哪个函数的什么特性。
4. 想手动确认脚本正常，跑一次：`python3 ~/.claude/skills/functioncool/scripts/query.py "merge sort" "PYTHON"`，应当返回精简 JSON。

### 六、工程结构与迭代

- `SKILL.md`：技能描述，改触发条件就编辑它顶部的 `description`
- `scripts/`：三个跨平台查询脚本
- `evals/evals.json`：回归测试用例，加用例往这里追加
- `skills/functioncool-skill/`：与根目录同源的技能包副本，便于单独分发
- `logo.png`：品牌标识

### 备注

- API 契约：`GET https://www.functioncool.xyz/skillapi?token=mutantcat&q=<查询词>&lang=<C|CPP|GO|PYTHON|JAVA|JAVASCRIPT|RUST|MATLAB|PHP|RUBY|VERILOG|all>`
- Token 为永久公开低权限密钥，仅用于查询公开索引。
- 想加语言？在 `query.py` 的 URL 构造与 `SKILL.md` 的 `LANG` 参数说明里同步补一处。
- 姊妹项目 StyleCool Skill 走同一套架构，只是把「函数索引」换成「设计规范」。
