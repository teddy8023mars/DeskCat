# DeskCat 🐱

一只常驻 macOS 桌面的 3D 伴侣小猫，头部（视线）会平滑跟随你的鼠标指针。

## 运行

```sh
swift run            # 开发运行
./scripts/make_app.sh  # 打包成双击即用的 DeskCat.app
```

## 功能

- **头部跟随**：小猫的头在 3D 空间中平滑转向鼠标，身体轻微跟随，带惯性
- **鼠标靠近**：靠近时小猫会兴奋——开心小跳、疯狂摇尾巴、转头更敏捷
- **空闲动作**：随机摇尾巴、好奇歪头、小跳，外加持续的呼吸起伏
- **点击互动**：点一下小猫，它会开心地跳一下
- **拖动摆放**：按住拖到屏幕任意位置，位置自动记住
- **菜单栏 🐱**：显示/隐藏小猫、重置位置、退出

## 调试

```sh
.build/debug/DeskCat --snapshot out.png            # 离屏渲染当前场景
DC_YAW=40 DC_PITCH=20 .build/debug/DeskCat --snapshot out.png  # 摆出指定头部姿势
```

## 技术

Swift + AppKit（透明无边框置顶窗口）+ SceneKit（3D 渲染）+ [GLTFKit2](https://github.com/warrenm/GLTFKit2)（glTF 加载）。
鼠标位置通过 `CGEvent` 轮询获取，无需任何系统权限。

## 模型授权

猫模型 ["Cat" by Quaternius](https://poly.pizza/m/qKICY6xla2)，CC0 公有领域，致谢 Quaternius ❤️
