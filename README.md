# QuickTrans

macOS 菜单栏翻译小工具，界面用 Liquid Glass 材质（macOS 26+）。

## 功能

- **桌面悬浮球**：点击后从球侧伸出输入条，回车翻译；可拖到屏幕任意位置。
- **划词翻译**：在任意应用选中文字，按 `⌥D` 在鼠标旁弹出结果。
- **单词卡片**：音节划分、美式 / 英式音标、发音（优先词典真人录音，没有时用系统 en-US / en-GB 语音）、释义、「怎么用」讲解、记法、常用搭配、例句。
- **整段翻译**：非中文译成中文，中文译成英文，流式显示。
- **设置**：服务商（DeepSeek / OpenAI / 自定义兼容接口）、模型、推理强度、快捷键、悬浮球、开机启动、默认口音。
- **历史记录**：保存最近 500 条，相同内容再查直接用历史结果，点「重新翻译」才重新请求。

快捷键默认 `⌥D` 翻译选中文本、`⌥Space` 打开输入框，可在设置里改。

## 安装

需要 macOS 26 以上、Apple 芯片（M 系列）的 Mac。

### 直接下载

1. 在 [Releases](https://github.com/shangjinyu012-gif/QuickTrans/releases/latest) 下载 `QuickTrans-x.y.z.zip`，解压后把 QuickTrans 拖进「应用程序」文件夹。
2. 双击打开。App 没有经过苹果公证，系统会提示无法验证开发者，有两种放行方式：
   - 打开「系统设置 → 隐私与安全性」，在页面底部点「仍要打开」；
   - 或者在终端执行：
     ```bash
     xattr -dr com.apple.quarantine /Applications/QuickTrans.app
     ```
3. 打开后点菜单栏的 QuickTrans 图标，进入「设置」，填入自己的 API Key（默认 DeepSeek，在 [platform.deepseek.com](https://platform.deepseek.com) 申请），点「测试连接」。
4. 第一次按 `⌥D` 翻译选中文字时，按提示在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 QuickTrans。

更新到新版本时，重复第 1、2 步。如果划词不起作用，在「辅助功能」里先删掉 QuickTrans，再重新添加。

### 从源码编译

需要 Swift 6 工具链（Xcode 或命令行工具均可）。

```bash
./scripts/make-cert.sh        # 只需一次：生成自签名证书「QuickTrans Dev」
./scripts/build.sh --install  # 编译、签名、安装到 /Applications 并启动
```

用固定证书签名后，重新编译不会让「辅助功能」授权失效。

## 发布新版本

1. 改 `Resources/Info.plist` 里的 `CFBundleShortVersionString`，提交并推送。
2. 执行 `./scripts/release.sh`：编译、打成 zip，并在 GitHub 上创建 `v<版本号>` 的 Release。

图标由 `swift scripts/make-icon.swift` 生成。

## 目录

```
Sources/QuickTransCore   请求、提示词、输入分类、词典录音（不依赖 UI）
Sources/QuickTrans       App：悬浮球、翻译面板、设置、历史、快捷键、划词读取
Sources/qtcli            命令行调试工具
docs/prototype.html      交互原型
```

## 数据存放

- 设置：`UserDefaults`（`com.shangjinyu.QuickTrans`）
- API Key：`~/Library/Application Support/QuickTrans/credentials.json`，权限 600
- 历史：同目录下 `history.json`

## 调试

```bash
# 不开界面验证请求
QT_API_KEY=sk-xxx swift run qtcli serendipity
QT_API_KEY=sk-xxx swift run qtcli --models

# 启动后直接打开某个界面：input | settings | text:<内容>
QT_DEMO="text:serendipity" /Applications/QuickTrans.app/Contents/MacOS/QuickTrans
```

macOS 27 SDK 把 `@State` 改成了宏，宏插件只随 Xcode 提供；为了只装命令行工具也能编译，代码里用 `@ViewState`（`SwiftUI.State` 的别名）代替。
