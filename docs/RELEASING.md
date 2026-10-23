# 发布与公证

FinderPlus 在 Mac App Store 之外分发（主程序需要运行用户选择的外部工具，无法沙盒化）。正式发布需要 Apple Developer Program 的 **Developer ID Application** 证书。

1. 在 `Config/Local.xcconfig` 中设置 `DEVELOPMENT_TEAM`。
2. 构建：`./scripts/package.sh`（arm64）或 `./scripts/package.sh universal`（阶段 2）。
   如需 Developer ID 签名，可改用 Xcode › Product › Archive › Distribute App › Developer ID。
3. 公证：

   ```sh
   xcrun notarytool submit dist/FinderPlus-<version>-arm64.zip \
       --apple-id you@example.com --team-id <TEAMID> --password <app-specific-password> --wait
   xcrun stapler staple build/Build/Products/Release/FinderPlus.app
   ```

4. 重新打包已 staple 的应用并发布。

检查清单：

- `codesign --verify --deep --strict --verbose=2 FinderPlus.app`
- `spctl -a -vvv FinderPlus.app`
- `lipo -archs FinderPlus.app/Contents/MacOS/FinderPlus`（阶段 1：`arm64`；阶段 2：`x86_64 arm64`）
- 扩展位于 `FinderPlus.app/Contents/PlugIns/FinderPlusFinderSync.appex`，`pluginkit -m -i <bundle-id>.FinderSync` 可见。
