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

**ClaudeCage** 通过将 `claude-code` CLI 打包到一个完全隔离的、单一文件的容器中来解决这个问题。除了你当前工作的项目目录外，它无法访问你系统的任何其他部分。

## 功能特性

- **安全沙箱**: 基于 Linux 命名空间 (namespaces) 技术，`claude` 进程受到严格限制，无法访问你的主目录、网络信息或其他进程。
- **单文件便携性**: 整个环境——`claude` 二进制文件、`bun` 运行时以及所有依赖项——都被打包成一个单一的可执行文件。下载它，赋予执行权限，然后运行即可。
- **无主机依赖**: 你的系统上无需安装 `node`、`bun` 或任何其他东西，甚至不用装 Claude Code。
- **兼容大多数 Linux 发行版**: 几乎可以在任何现代 Linux 发行版上运行。
- **更佳的性能**: 以原生速度运行。得益于现代化的高性能 JavaScript 运行时：[**bun**](https://github.com/oven-sh/bun)，它的运行速度甚至比官方的 Claude Code 更快。
- **支持自定义 API**: 可以轻松配置它以使用自定义 API 端点，包括 OpenAI 代理。

## 工作原理

ClaudeCage 使用 [**RunImage**](https://github.com/VHSgunzo/runimage) 项目构建，该项目利用 [**Bubblewrap**](https://github.com/containers/bubblewrap) 来创建轻量级的、非特权的容器。本项目提供了一个简单的构建脚本，用于自动为 `claude-code` 创建一个定制的 RunImage 容器。

## 使用方法

### 1. 获取 ClaudeCage

#### 下载预构建的二进制文件

下载 `ClaudeCage` 二进制文件和 `ClaudeCage.rcfg` 配置文件，将这两个文件复制到你的 `$PATH` 路径下的某个位置，例如 `~/.local/bin/`。

#### 从源码构建

首先，克隆本仓库。构建脚本除了 `curl` 和标准的 coreutils 工具外，没有其他依赖。

```bash
git clone https://github.com/your-username/ClaudeCage.git
cd ClaudeCage
./build.sh
```

该脚本将下载必要的组件，并在当前目录下创建两个文件：

- `ClaudeCage`：可移植的可执行文件。
- `ClaudeCage.rcfg`：沙箱配置文件。

### 2. 运行 ClaudeCage

将 `ClaudeCage` 可执行文件和 `.rcfg` 文件都移动到你的 `$PATH` 路径下的某个位置，例如 `~/.local/bin/`。

```bash
mv ClaudeCage ClaudeCage.rcfg ~/.local/bin/
```

现在，你可以像使用常规 `claude` 命令一样使用它。进入任何项目目录并运行它。它将只能访问该目录。

```bash
cd /path/to/my/awesome-project
ClaudeCage "重构这个函数，使其更高效。" # 现在 Claude Code 只能访问这个目录
```

## 配置

### 自定义 API 端点和代理

你可以在运行 ClaudeCage _之前_ 通过设置环境变量，让 `claude-code` 使用自定义的 API 端点（包括像 [claude-code-proxy](https://github.com/fuergaosi233/claude-code-proxy) 这样的 OpenAI 代理）。claude-code-proxy 并 _没有_ 集成到本项目中。

```bash
# 使用 claude-code-proxy 将 API 调用转换为 OpenAI API 格式的示例。
export ANTHROPIC_BASE_URL="http://localhost:8082/"
export ANTHROPIC_AUTH_TOKEN="使用本地代理时无需此项"
export ANTHROPIC_MODEL="anthropic/claude-sonnet-4"
export ANTHROPIC_SMALL_FAST_MODEL="google/gemini-2.0-flash"

ClaudeCage "内布拉斯加州的首府是哪里？"
```

更多详情，请参阅官方的 [claude-code 设置文档](https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables)。

## 致谢

没有以下这些出色的开源工具，这个项目是不可能完成的：

- [**RunImage**](https://github.com/VHSgunzo/runimage)：让单文件、可移植的 Linux 容器成为现实。
- [**Bubblewrap**](https://github.com/containers/bubblewrap)：提供了底层的沙箱技术。
- [**Bun**](https://github.com/oven-sh/bun)：一个现代化、高性能、兼容 Node.js 的 JavaScript 运行时。
- [**claude-code-proxy**](https://github.com/fuergaosi233/claude-code-proxy)：推荐的 OpenAI 格式 API 代理。

