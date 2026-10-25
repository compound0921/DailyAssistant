# DailyAssistant 校园助手

本地优先的 Flutter 校园助手，把课表、日程、学习通任务和正方教务考试集中在一个应用里。

- Android 与 Windows 为当前验收平台，iOS 保留工程但未验证。
- 中文界面，支持浅色/深色和窗口自适应。
- 无后端、无账号体系、无推送，数据保存在本机。

## 功能

### 课表

- 导入 ICS、正方 HTML 和正方 Excel 课表。
- 多份课表切换、重命名、删除；每份课表独立作息。
- 周视图、节次时间调整、课程信息编辑。
- 根据教务消息叠加调课、补课、停课标记，不改原始课表。
- 今天列头高亮；时间轴显示每节上课/下课时间。
- 课表口令：导出当前课表为文本，另一台设备在导入页粘贴导入。

### 日程

- 增删改查、关联课程、完成状态。
- 按截止时间排序，显示紧迫度颜色和剩余时间。
- 待完成只保留“已过期”小标题，今天和未来平铺；已完成单独分组。
- 日程卡和首页考试行支持左滑“编辑 / 删除”。

### 学习通

- 账号密码登录，安全存储。
- 同步作业、考试、随堂练习的截止时间，只读。
- 启动自动同步、下拉刷新，按外部 ID 去重。

### 正方教务

- WebVPN 账号密码登录，同步消息总览与考试信息。
- 考试只进“考试安排”，不写日程。
- 教务页保留本学期全部考试；首页自动显示未过期考试，过期考试星标后显示。
- 考试可编辑全部显示字段、左滑删除、单场恢复默认。
- 首页可手动添加考试；手动考试只存本机，清除教务登录数据时保留。
- 消息总览默认收起，展开显示全部。

## 快速开始

环境要求：

- Flutter SDK，Dart `^3.12.2`
- Windows：Visual Studio C++ 桌面开发工具链
- Android：Android SDK，模拟器或真机

安装依赖并运行 Windows 版：

```bash
flutter pub get
flutter run -d windows
```

也可以直接运行 `start_windows.bat`。

Android 模拟器：

```bash
flutter run -d emulator-5554
```

也可以运行 `start_android.bat`，脚本会启动 `daily_assistant_phone` 模拟器。

常用检查与构建：

```bash
flutter analyze
flutter test
flutter build windows --debug
flutter build apk --debug
```

## 数据与隐私

- 课表、日程和外观保存在 `SharedPreferences`。
- 账号、密码和 Cookie 只写入 `flutter_secure_storage`，不写日志。
- 没有云端上传；真实课表样例和导出文件不提交。
- 本地导入/导出文件放 `local_data/`；`docs/samples/` 中的 HTML/XLSX 已被忽略。
- 课表口令是 `DA-TT1:` 开头的长文本，未加密，请勿公开分享。
- 学习通与正方教务只读同步；不代提交作业、签到或答题。

## 项目结构

```text
lib/
  ui/         页面与组件
  models/     课表、日程、外观模型
  data/       SharedPreferences 持久化
  import/     ICS、正方 HTML/Excel 导入
  jiaowu/     正方 WebVPN、快照、考试与调课解析
  xuexitong/  学习通登录与截止时间同步
  share/      课表口令编解码
test/         单元测试、组件测试与脱敏样例
docs/         接入说明、测试环境与待实现清单
third_party/  本地依赖
```

技术栈：Flutter + Material 3、Dio、SharedPreferences、flutter_secure_storage、html/excel 解析。

## 文档

- [开发与协作约定](AGENTS.md)
- [产品范围](PRODUCT.md)
- [设计规范](DESIGN.md)
- [正方教务接入](docs/教务接入.md)
- [学习通接入](docs/学习通接入.md)
- [待实现功能](docs/待实现功能.md)
- [测试环境](docs/测试环境.md)

## 已知限制

- 学习通协议基于客户端行为还原，平台更新后可能失效。
- 正方 WebVPN 登录脚本和页面结构可能随学校更新失效。
- 验证码、新设备验证等需要人工处理。
- 消息和考试只取查询接口第一页，暂不翻页。
- 无后台定时同步。
- iOS 工程未在当前 Windows 环境验证。
- 仓库不包含真实账号、课表或考试数据。

## 说明

个人自用项目。请遵守学校和平台规则，仅用于同步自己的只读数据。
