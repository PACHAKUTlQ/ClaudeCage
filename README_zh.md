<div id="header" align="center">
    <img src="icon.svg" width="250px" />
    <h1>ClaudeCage</h1>
    <p>
      <a href="README.md">English</a> | <strong>简体中文</strong>
    </p>
</div>

[![构建与发布](https://github.com/PACHAKUTlQ/ClaudeCage/actions/workflows/build_and_release.yml/badge.svg)](https://github.com/PACHAKUTlQ/ClaudeCage/actions/workflows/build_and_release.yml)

**在便携、安全的沙箱中运行最强 AI 编程 agent。**

[Claude Code](https://github.com/anthropics/claude-code) 是一个当前最先进的 AI 编程助手。不幸的是，它的命令行工具（CLI）是以闭源且经过混淆的 JavaScript 形式分发的。你不知道它在做什么。它是否在读取你的 SSH 密钥？是否在索引你的照片？是否正利用你的 `~/Downloads` 文件夹策划“天网”式的世界统治计划？

也许不会……**但何必冒险呢？**

**ClaudeCage** 通过将 Claude Code CLI 打包到一个完全隔离的、单一文件的容器中来解决这个问题。除了你当前工作的项目目录外，它无法访问你系统的任何其他部分。

> **破坏性变更：** 构建产物现在命名为 **`claude`**（以及 **`claude.rcfg`**），可以作为原版 `claude` 的**无缝替换**（但运行在沙箱中）。

## 功能特性

- **安全沙箱**: 基于 Linux 命名空间 (namespaces) 技术，`claude` 进程受到严格限制，无法访问你的主目录、网络信息或其他进程。
- **单文件便携性**: 整个环境——`claude` 二进制文件、`bun` 运行时以及所有依赖项——都被打包成一个单一的可执行文件。下载它，赋予执行权限，然后运行即可。
- **无主机依赖**: 你的系统上无需安装 `node`、`bun` 或任何其他东西，甚至不用装 Claude Code。
- **兼容大多数 Linux 发行版**: 几乎可以在任何现代 Linux 发行版上运行。
- **更佳的性能**: 以原生速度运行。得益于现代化的高性能 JavaScript 运行时：[**bun**](https://github.com/oven-sh/bun)，它的运行速度甚至比官方的 Claude Code 更快。
- **支持自定义 API**: 可以轻松配置它以使用自定义 API 端点，包括 OpenAI 代理。
- **可使用宿主机工具链（只读）**: 默认会把常见系统目录（如 `/usr`、`/etc`、`/opt`）以只读方式挂载进沙箱，Claude 可以直接调用你已有的编译器/工具，但不能修改这些目录。

## 工作原理

ClaudeCage 使用 [**RunImage**](https://github.com/VHSgunzo/runimage) 项目构建，该项目利用 [**Bubblewrap**](https://github.com/containers/bubblewrap) 来创建轻量级的、非特权的容器。本项目提供了一个简单的构建脚本，用于自动为 Claude Code 创建一个定制的 RunImage 容器。

## 使用方法

### 1. 获取 ClaudeCage

#### 下载预构建的二进制文件

下载 `claude` 二进制文件和 `claude.rcfg` 配置文件，将这两个文件复制到你的 `${PATH}` 路径下的某个位置，例如 `~/.local/bin/`。

#### 从源码构建

首先，克隆本仓库。构建脚本除了 `curl` 和标准的 coreutils 工具外，没有其他依赖。

```bash
git clone https://github.com/your-username/ClaudeCage.git
cd ClaudeCage
./build.sh
```

该脚本将下载必要的组件，并在当前目录下创建两个文件：

- `claude`：可移植的可执行文件。
- `claude.rcfg`：沙箱配置文件。

### 2. 运行 ClaudeCage

将 `claude` 可执行文件和 `.rcfg` 文件都移动到你的 `${PATH}` 路径下的某个位置，例如 `~/.local/bin/`。

```bash
mv claude claude.rcfg ~/.local/bin/
```

现在，你可以像使用常规 `claude` 命令一样使用它。进入任何项目目录并运行它。它将只能访问该目录。

```bash
cd /path/to/my/awesome-project
claude "重构这个函数，使其更高效。" # 现在 Claude 只能访问这个目录
```

### 避免与原版 `claude` 冲突

由于产物名就是 `claude`，把它放进 `${PATH}` 后通常会**劫持**你原本安装的 `claude`。（不是覆盖文件，因为推荐将 `claude` 和 `claude.rcfg` 放到 `~/.local/bin` 而不是 `/usr/bin`。）

如果你希望两者共存，请把这两个文件**一起改名为同一个前缀**（`.rcfg` 必须与可执行文件同名）：

```bash
mv claude claude-cage
mv claude.rcfg claude-cage.rcfg
./claude-cage "Hello from sandbox"
```

## 配置

### 默认挂载与隔离策略

你可以直接编辑 `claude.rcfg` 来自定义沙箱能看到什么。默认配置的目标是：开箱即用，同时尽量避免泄露宿主机敏感数据。

**Claude 状态持久化（宿主机侧）：**

- 启动时会在宿主机上确保以下路径存在（不存在会自动创建）：
  - `${HOME}/.claude/`（权限 `700`）
  - `${HOME}/.claude.json`（权限 `600`）
- 并将它们以读写方式绑定进沙箱，使登录/配置/历史等可以跨运行持久化：
  - `${HOME}/.claude.json`（读写）
  - `${HOME}/.claude/`（读写）

**项目目录：**

- 当前工作目录会绑定进沙箱（Claude 可读写你的项目）。
- 并在相同的工作目录启动命令。

**宿主机系统/工具（只读）：**

- 常见路径会以只读方式挂载，让 Claude 可以调用宿主机工具：
  - `/usr`、`/opt`、`/etc`
  - 以及（如果存在）：`/lib`、`/lib64`、`/bin`、`/sbin`

**SSH（默认更安全）：**

- 如果检测到 `SSH_AUTH_SOCK`，只转发 **agent socket** 进入沙箱（默认不会给 `${HOME}/.ssh`）。
- 如果你确实需要把宿主机 SSH 密钥/配置暴露给沙箱（更不安全），可以手动开启：

```bash
CLAUDECAGE_ALLOW_SSH_KEYS=1 claude "Clone and inspect this repo."
```

**默认开启的额外隔离项：**

- 默认还会额外隔离 DBus、XDG runtime、X11 tmp socket 等资源，并同时隔离 PIDs/users/hostname/tmp。

### 轻松使用其他模型供应商（通过 Claude Code Router）

如果你希望把 Claude Code 的请求转发/路由到其他供应商与模型（OpenRouter、DeepSeek、Ollama、Gemini 等），推荐使用外部项目 **Claude Code Router**：

- <https://github.com/musistudio/claude-code-router>

它**不属于 ClaudeCage**，详细配置请直接参考该项目的 README。

最简用法：

```bash
npm install -g @musistudio/claude-code-router
ccr code
```

由于 ClaudeCage 在 `${PATH}` 中提供了同名的 `claude`（可无缝替换），Claude Code Router 在调用 `claude` 时会自动使用 **沙箱版** 的 ClaudeCage `claude`。

### 自定义 API 端点和代理

claude-code-router `ccr code` 自动设置环境变量并调用 Claude Code。如果你希望手动设置或者不想使用claude-code-router，你可以在运行 ClaudeCage _之前_ 通过设置环境变量，让 Claude Code 使用自定义的 API 端点：

```bash
export ANTHROPIC_BASE_URL="http://localhost:3456/"
export ANTHROPIC_AUTH_TOKEN="使用本地代理时无需此项"
export ANTHROPIC_MODEL="anthropic/claude-sonnet-4"
export ANTHROPIC_SMALL_FAST_MODEL="google/gemini-2.0-flash"

claude "内布拉斯加州的首府是哪里？"
```

更多详情，请参阅官方的 [claude-code 设置文档](https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables)。

## 致谢

没有以下这些出色的开源工具，这个项目是不可能完成的：

- [**RunImage**](https://github.com/VHSgunzo/runimage)：让单文件、可移植的 Linux 容器成为现实。
- [**Bubblewrap**](https://github.com/containers/bubblewrap)：提供了底层的沙箱技术。
- [**Bun**](https://github.com/oven-sh/bun)：一个现代化、高性能、兼容 Node.js 的 JavaScript 运行时。
- [**claude-code-router**](https://github.com/musistudio/claude-code-router)（外部项目）：用于将 Claude Code 的请求路由到多种模型供应商。
