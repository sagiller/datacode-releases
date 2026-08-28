# DataCode Runtime Releases

此仓库用于发布 DataCode Runtime 的多平台二进制制品。

## 一键安装

macOS 和 Linux 安装最新稳定版：

```bash
curl -fsSL https://raw.githubusercontent.com/sagiller/datacode-releases/main/install.sh | bash
```

安装指定版本：

```bash
curl -fsSL https://raw.githubusercontent.com/sagiller/datacode-releases/main/install.sh | bash -s -- --version 1.0.5
```

默认安装到 `~/.datacode/bin/datacode`。安装器会选择对应平台制品，并在替换程序前校验发布 manifest 和 SHA-256。

## 手工下载

也可以从 [Releases](https://github.com/sagiller/datacode-releases/releases) 下载对应平台的压缩包，并使用同一版本中的 `datacode-checksums.txt` 校验 SHA-256。

当前制品未进行 Apple 公证或 macOS/Windows 代码签名；SHA-256 仅用于验证下载内容与发布清单一致。
