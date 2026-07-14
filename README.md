# Claude Code Status Line 配置指南（Windows PowerShell）

本指南介绍如何在 Windows 上为 Claude Code 配置自定义状态栏，显示：

```text
📁 当前目录  ·  Git 分支  ·  ⚡ 当前模型  ·  🧠 上下文占用率
```

示例：

```text
<img width="1718" height="300" alt="image" src="https://github.com/user-attachments/assets/55d4e6e9-6933-4ac5-8493-f423d32dd366" />
```

> 本配置适用于 Claude Code CLI。状态栏脚本只负责展示 Claude Code 通过标准输入传入的 JSON，不会调用模型 API。

## 文件位置

配置涉及两个文件：

| 文件 | 用途 |
|---|---|
| `%USERPROFILE%\.claude\settings.json` | 注册 status line 命令 |
| `%USERPROFILE%\.claude\statusline-command.ps1` | 读取状态数据并格式化输出 |

通常对应：

```text
C:\Users\<用户名>\.claude\settings.json
C:\Users\<用户名>\.claude\statusline-command.ps1
```

## 一、创建 PowerShell 脚本

创建文件：

```text
%USERPROFILE%\.claude\statusline-command.ps1
```

写入以下内容：

```powershell
# Claude Code statusLine command
# Format: folder | branch | model | context%
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Claude Code 通过 stdin 传入 UTF-8 JSON。
# 直接读取原始字节可避免中文在 GBK/936 控制台中乱码。
$raw = ""
try {
    $stdin = [Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader(
        $stdin,
        [System.Text.Encoding]::UTF8
    )
    $raw = $reader.ReadToEnd()
    $reader.Dispose()
} catch {}

$inputData = $null
try {
    $inputData = $raw | ConvertFrom-Json
} catch {}

$cwdFull = if ($inputData.workspace.current_dir) {
    $inputData.workspace.current_dir
} elseif ($inputData.cwd) {
    $inputData.cwd
} else {
    ""
}

$basename = if ($cwdFull) {
    Split-Path -Leaf $cwdFull
} else {
    "unknown"
}

# 当前目录是 Git 仓库时显示分支。
$branchPart = ""
if ($cwdFull) {
    try {
        $null = & git -C $cwdFull rev-parse --git-dir 2>$null
        if ($LASTEXITCODE -eq 0) {
            $branch = & git -C $cwdFull --no-optional-locks `
                symbolic-ref --short HEAD 2>$null
            if ($branch) {
                $branchPart = "$([char]0xE0A0) $branch"
            }
        }
    } catch {}
}

$displayName = if ($inputData.model.display_name) {
    $inputData.model.display_name
} else {
    ""
}
$shortModel = $displayName -replace '^[Cc]laude[- ]', ''

# 该百分比由 Claude Code 根据当前模型的上下文窗口预先计算。
$used = $inputData.context_window.used_percentage

$bolt   = [System.Char]::ConvertFromUtf32(0x26A1)
$brain  = [System.Char]::ConvertFromUtf32(0x1F9E0)
$folder = [System.Char]::ConvertFromUtf32(0x1F4C1)

$parts = @("$folder $basename")
if ($branchPart) {
    $parts += $branchPart
}
if ($shortModel) {
    $parts += "$bolt $shortModel"
}
if ($null -ne $used) {
    $parts += "$brain $([math]::Round($used))%"
}

$output = $parts -join "  $([char]0x00B7)  "
[Console]::Out.Write($output)
```

### 为什么显式使用 UTF-8？

Windows PowerShell 5.1 的控制台代码页可能是 GBK（936）。如果直接读取标准输入，包含中文目录名的 JSON 可能乱码。脚本使用 `StreamReader` 按 UTF-8 解码，并将输出编码设置为 UTF-8。

## 二、配置 `settings.json`（可以直接写在cc switch里）

打开：

```text
%USERPROFILE%\.claude\settings.json
```

将以下 `statusLine` 节点合并到现有 JSON 中：

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell.exe -NoProfile -File C:/Users/<用户名>/.claude/statusline-command.ps1"
  }
}
```

把 `<用户名>` 替换成实际的 Windows 用户目录名。路径建议使用 `/`，可以减少 JSON 中反斜杠转义带来的问题。

如果 `settings.json` 已有其他配置，不要覆盖整个文件。例如：

```json
{
  "includeCoAuthoredBy": false,
  "statusLine": {
    "type": "command",
    "command": "powershell.exe -NoProfile -File C:/Users/<用户名>/.claude/statusline-command.ps1"
  }
}
```

> **安全提醒：** 不要把 API Key、OAuth Token、`ANTHROPIC_AUTH_TOKEN` 或其他密钥提交到 GitHub。本文示例只包含 status line 配置。

## 三、重新加载

保存两个文件后，重新启动 Claude Code：

```powershell
claude
```

状态栏会在 Claude Code 刷新状态时自动执行脚本。无需手动常驻运行 PowerShell。

## Status line 输入字段

Claude Code 调用脚本时，会通过标准输入传入 JSON。本文使用以下字段：

| 字段 | 含义 |
|---|---|
| `workspace.current_dir` | 当前工作目录（优先使用） |
| `cwd` | 当前目录的兼容字段 |
| `model.id` | 当前模型 ID |
| `model.display_name` | 适合展示的模型名称 |
| `context_window.total_input_tokens` | 当前上下文累计输入 token |
| `context_window.context_window_size` | Claude Code 识别的模型上下文窗口 |
| `context_window.used_percentage` | Claude Code 预先计算的上下文占用百分比 |

当前脚本直接展示：

```powershell
$inputData.context_window.used_percentage
```

因此，脚本中不会出现 `1000000` 等模型窗口常量。上下文窗口大小由 Claude Code 根据当前模型提供；脚本只是显示计算结果。

## 上下文百分比如何计算

概念上等价于：

```text
上下文占用率 = 已使用 token / 模型上下文窗口 × 100%
```

但默认脚本不重复计算，而是采用 Claude Code 已提供的 `used_percentage`。这样切换不同上下文规格的原生模型时，不需要维护模型映射表。

例如，模型选择器显示：

```text
gpt-5.6-sol[1m]
```

其中 `[1m]` 表示 Claude Code 当前将该路由识别为 1M token 上下文窗口。status line 会沿用这一口径。

## 自定义模型和第三方网关

使用 `ANTHROPIC_BASE_URL` 接入第三方网关或自定义模型别名时，需要注意：

1. Claude Code 识别的 `context_window_size` 可能来自模型路由声明；
2. 网关实际允许的最大输入可能与声明值不同；
3. 某些网关会把“上下文超限”错误错误包装为 HTTP 502；
4. HTTP 502 通常会触发自动重试，而不会被识别为不可重试的上下文错误；
5. `.jsonl` 会话文件大小不等于发送给模型的 token 数。

如果 `/model` 已显示正确的窗口后缀（例如 `[1m]`），通常应继续使用 Claude Code 提供的 `used_percentage`，不要在脚本中重复写死相同上限。

### 只有在模型声明确实错误时才覆盖

如果服务商明确确认某个自定义模型的真实上限与 Claude Code 显示不一致，可以在脚本中增加覆盖表：

```powershell
$contextWindowOverrides = @{
    # 必须填写服务商确认的真实 token 上限。
    "custom-model-id" = 128000
}

$modelId = $inputData.model.id
$totalInputTokens = [double]$inputData.context_window.total_input_tokens
$used = $inputData.context_window.used_percentage

if (
    $modelId -and
    $contextWindowOverrides.ContainsKey($modelId) -and
    $totalInputTokens -ge 0
) {
    $contextWindowSize = [double]$contextWindowOverrides[$modelId]
    if ($contextWindowSize -gt 0) {
        $used = ($totalInputTokens / $contextWindowSize) * 100
    }
}
```

不要根据模型名称猜测上下文上限。应以模型选择器、服务商文档或明确包含最大 token 数的错误信息为准。

如果模型 ID 带有路由后缀，可以按前缀匹配：

```powershell
if ($modelId -like "custom-model-id*") {
    # 使用已确认的自定义上限进行计算
}
```

## 可选：调试 status line 输入

排查字段时，可以临时在解析 JSON 前加入：

```powershell
try {
    $raw | Out-File -Append -Encoding utf8 `
        "$env:TEMP\claude-statusline-debug.log"
} catch {}
```

调试日志位置：

```text
%TEMP%\claude-statusline-debug.log
```

> 调试完成后应删除这段日志代码和日志文件。原始 status line JSON 可能包含工作目录、会话信息或其他不适合长期保存的元数据，也不要把调试日志提交到 GitHub。

## 常见问题

### 1. 状态栏没有显示

检查：

- `settings.json` 是否为有效 JSON；
- `command` 中的脚本路径是否存在；
- 是否安装了 Windows PowerShell；
- 重启 Claude Code 后是否生效。

可以手动检查脚本语法：

```powershell
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    "$env:USERPROFILE\.claude\statusline-command.ps1",
    [ref]$null,
    [ref]$errors
)
$errors
```

没有输出通常表示未发现语法错误。

### 2. 中文目录显示乱码

确认脚本包含：

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

并且使用 UTF-8 `StreamReader` 读取标准输入。

### 3. Git 分支不显示

只有当前目录属于 Git 仓库且处于正常分支时才显示。处于 detached HEAD 状态时，`symbolic-ref --short HEAD` 不会返回分支名。

确认 Git 可用：

```powershell
git --version
```

### 4. 上下文一直显示 100%

依次检查：

1. 使用 `/model` 查看模型及窗口后缀；
2. 确认所选模型是否显示 `[1m]`、`[200k]` 等规格；
3. 如果使用第三方网关，确认其实际窗口是否与声明一致；
4. 检查会话是否真的接近上限；
5. 不要用 `.jsonl` 文件大小推算 token 数。

若模型已经明确显示 `[1m]`，状态栏仍为 100%，更可能是当前会话确实接近窗口上限，而不是 PS1 中缺少 `1M` 配置。

### 5. 自动压缩为什么没有触发？

自动压缩取决于 Claude Code 对当前模型窗口的判断，以及服务端是否返回可识别的错误。第三方网关若把上下文超限包装为可重试的 HTTP 502，Claude Code 可能持续重试，而不是进入上下文恢复流程。

遇到明确的上下文超限错误时，应停止无效重试，保留旧会话，并通过新会话加精简交接信息继续工作。

## 安全建议

- 不要把 `settings.json` 原文件直接提交到公开仓库，因为其中可能包含 Token 或自定义网关信息；
- GitHub 中只放脱敏后的配置片段；
- 不要记录或提交完整 status line 原始 JSON；
- 不要把 `%USERPROFILE%\.claude\projects\` 下的会话 JSONL 提交到仓库；
- 如果密钥曾被提交到 Git，应立即轮换，不能只删除最新提交中的字符串。

## License

本示例可按项目需要自由修改和使用。
