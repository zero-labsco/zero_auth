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

`zero_auth` is a pure-Dart package: the Dart SDK is the **only** declared
constraint, and the runtime dependency is `meta` alone. There is deliberately
**no** `flutter:` constraint — declaring one would mis-tag the package as
"Flutter" on pub.dev and force pure-Dart (CLI/server) consumers to install the
Flutter SDK for no reason. A Dart package is usable from Flutter projects
automatically.

`zero_auth` 是纯 Dart 包：Dart SDK 是**唯一**声明的约束，运行时依赖只有
`meta`。刻意**不**声明 `flutter:` 约束 —— 那样会让包在 pub.dev 上被误标为
"Flutter"，并迫使纯 Dart（CLI/服务端）消费者无缘无故安装 Flutter SDK。
Dart 包本就自动可用于 Flutter 项目。

## Next Steps / 下一步

- [Getting Started](Getting-Started) — Quick start guide / 快速开始
- [Usage](Usage) — Full usage guide / 完整使用指南
