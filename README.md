# 🥔 PotatoCardApp

一个面向 **土豆片 · 电子拍立得（6 色墨水屏设备）** 的信息卡片展示 App，支持高质量图片传输与墨水屏显示优化。

---

## ✨ 项目简介

PotatoCardApp 是一款 iOS 应用，致力于为 **墨水屏设备（E-Ink）** 提供高质量的信息展示解决方案。

通过对图片与内容进行专门优化，使其在低刷新率、有限色彩的墨水屏上依然能够呈现清晰、优雅的视觉效果。

---

## 📸 Screenshots

| 首页 | 待办 | 技能 |
|------|------|------|
| <img src="image/home.png" width="200"/> | <img src="image/todos.png" width="200"/> | <img src="image/skills.png" width="200"/> |

---

## 🎯 使用场景

- 📺 土豆片设备（尚未发布，详情可关注微博 @Sunbelife）
- 🗂 桌面信息卡片（天气 / 日程 / 提醒）
- 🎨 个性化展示终端（照片 / UI 卡片 / 信息面板）

---

## 🚀 核心功能

### 📡 设备连接
- 自动发现附近设备
- 快速连接与稳定传输

### 🖼️ 图片处理
- 适配墨水屏分辨率（如 400×600）
- 针对 E-Ink 特性优化显示效果
- 支持多种图片输入来源

### 🎨 卡片展示
- 信息卡片 UI 展示
- 可扩展天气 / 日历 / 提醒等模块

### ⚡ 传输优化
- 实时进度反馈
- 后台传输支持（持续优化中）

---

## 🧱 技术架构

- Swift
- SwiftUI
- iOS SDK
- E-Ink 设备通信 SDK

---

## 🛠️ 快速开始

### 1️⃣ 克隆项目

```bash
git clone https://github.com/jiqimaooo/PotatoCardApp.git
```

---

### 2️⃣ 打开项目

使用 Xcode 打开：

```
PotatoCardApp.xcodeproj
```

---

### 3️⃣ 配置签名

在 Xcode 中：

```
Signing & Capabilities → Team
```

选择你自己的 Apple Developer 账号

---

### 4️⃣ 运行

连接真机设备后运行项目

---

## ⚠️ 注意事项

- 本项目处于早期阶段，功能仍在持续完善中
- 部分功能依赖真实设备进行测试
- 墨水屏显示效果与硬件特性相关

---

## 📁 项目结构

```
PotatoCardApp
├── Views          # UI 视图
├── Models         # 数据模型
├── Services       # 业务逻辑 / 通信
├── Resources      # 资源文件
└── Utils          # 工具类
```

---

## 🔒 隐私与安全

本项目遵循良好的安全实践：

- 不包含任何 API Key / Token
- 不包含证书或敏感配置
- 不包含本地环境文件
- 不采集、不上传任何用户隐私数据

---

## 🤖 AI 协助开发说明

本项目在开发过程中，部分代码与设计由 AI 工具辅助生成与优化（包括但不限于代码实现、UI 设计与文档编写）。


---

## � Roadmap

- [ ] 增加更多卡片模板（天气 / 日程）
- [ ] 优化后台传输稳定性
- [ ] 提升图片抖动算法效果
- [ ] 支持更多分辨率设备
- [ ] UI 设计进一步优化

---

## 🤝 贡献

欢迎提交 Issue 或 Pull Request，一起完善这个项目。

---

## 📄 License

本项目基于 MIT License 开源。  
在使用、修改或分发本项目时，请遵守相关开源协议。

---


## 🔗 社交链接

### 👨‍💻 项目作者 @王野 sp
[![Weibo](https://img.shields.io/badge/Weibo-王野sp-red?logo=sina-weibo)](https://weibo.com/u/1774818625)

### 🔧 原创硬件（土豆片） @Sunbelife
[![Weibo](https://img.shields.io/badge/Weibo-Sunbelife-red?logo=sina-weibo)](https://weibo.com/u/1675423275)