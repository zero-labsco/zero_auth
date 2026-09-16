# Installation / 安装

## From pub.dev (Recommended) / 从 pub.dev 安装（推荐）

Add the following to your `pubspec.yaml`:

在 `pubspec.yaml` 中添加以下依赖：

```yaml
dependencies:
  zero_auth: ^__ZERO_AUTH_VERSION__
```

Then run:

然后运行：

```bash
dart pub get
```

## From GitHub / 从 GitHub 安装

Alternatively, install from GitHub:

或者从 GitHub 安装：

```yaml
dependencies:
  zero_auth:
    git:
      url: https://github.com/zero-labsco/zero_auth.git
      ref: release/v__ZERO_AUTH_VERSION__
```

## Import / 导入

```dart
import 'package:zero_auth/zero_auth.dart';
```

## Requirements / 环境要求

| Requirement | Version |
|-------------|---------|
| Dart SDK | >= 3.4.0 |
| Flutter | >= 3.0.0 (only a constraint; no Flutter runtime dependency) |

`zero_auth` is a pure-Dart package. Flutter is only listed because the example app uses it; the core has no Flutter dependency.

`zero_auth` 是纯 Dart 包，仅因示例 App 用到 Flutter 才列出；内核本身不依赖 Flutter。

## Next Steps / 下一步

- [Getting Started](Getting-Started) — Quick start guide / 快速开始
- [Usage](Usage) — Full usage guide / 完整使用指南
