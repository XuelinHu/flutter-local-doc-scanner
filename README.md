# 文档扫描器

<p align="center">
  <img height="20" alt="Flutter" src="https://img.shields.io/badge/flutter-used-02569B" />
  <img height="20" alt="Dart SDK 3.11.4+" src="https://img.shields.io/badge/dart-3.11.4%2B-0175C2" />
</p>

本地拍照、导入、四角检测、裁剪、增强、整理多页扫描并导出 PDF。默认图像与 PDF 只存放在本机，不需要业务数据库或缓存服务器。

## AI 文档识别

“AI识别”页可配置 OpenAI Chat Completions 兼容的视觉模型（例如局域网 Ollama 中已部署的多模态模型）。默认服务地址为 `http://192.168.1.9:11434/v1/chat/completions`，模型名需填写实际可用的视觉模型。“检查视觉能力”只对私网 Ollama 的 `/api/show` 查询模型元数据，不发送 API Key 或扫描图片，也不会启动模型。只有点击“上传此页并识别”后，当前选中的扫描图片才会发送到配置的模型；每页限制 8 MiB。识别文本只显示在当前页面，不自动保存到 PDF 或远端数据库。API Key 使用 Android 安全存储；任何非本机回环 HTTP 接口都不能发送 API Key，配置密钥时必须使用 HTTPS。无密钥的内网 Ollama 仍可使用 HTTP。

## 构建

```powershell
flutter test
flutter analyze
flutter build apk --release
```

release APK 输出到 `dist/document-scanner-release.apk`，供内网安装验收；正式发布需配置自己的签名。
