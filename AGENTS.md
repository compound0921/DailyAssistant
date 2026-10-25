# AGENTS.md

本地优先的 Flutter 校园助手。Android 与 Windows 是验收平台，iOS 仅保留工程。

## 先读

- `PRODUCT.md`：用户、范围、产品边界。
- `DESIGN.md`：视觉规范与交互约定。
- `docs/教务接入.md`：WebVPN、正方教务、调课解析。
- `docs/待实现功能.md`：完成项与已知限制。

## 常用命令

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build windows --debug
```

Android 模拟器用 `start_android.bat`。Windows 直接运行 `start_windows.bat`。

## 工作流

1. 新需求先用 `AskUserQuestion` 确认关键分歧；能从代码或文档查到的事实自己查。
2. 修改或新建文件前，列出完整路径清单征得同意；用户明确点名文件或说“直接做”时除外。
3. 只做确认过的范围；出现清单外的新文件，暂停并重新确认。
4. 完成后至少运行 `flutter analyze` 和 `flutter test`；涉及界面时再构建或运行 Windows 版验证。
5. 不要主动 `git commit` 或 `git push`，除非用户要求。

## 目录

- `lib/ui/`：页面与 Material 组件。
- `lib/models/`：课表、日程、外观等模型。
- `lib/data/`：`SharedPreferences` 持久化。
- `lib/import/`：ICS、正方 HTML/Excel 导入。
- `lib/jiaowu/`：正方 WebVPN 登录、查询、快照、考试与调课解析。
- `lib/xuexitong/`：学习通登录与截止时间同步。
- `lib/share/`：课表口令编解码。
- `third_party/`：本地依赖，不随意改。
- `docs/samples/`：真实样例，含个人信息，默认不提交。

## 硬性规则

- 界面中文；用户可见文案统一叫“日程”，不要再出现“Deadline”。
- 教务考试只进“考试安排”，不写入日程。旧 `DeadlineSource.jiaowu` 只用于启动清理。
- 学习通与正方教务均只读同步，不替用户提交、签到或答题。
- 本地优先：无后端、无账号体系、无推送、无后台定时同步。
- 账号、密码、Cookie 只进 `flutter_secure_storage`，不得写日志或提交。
- `docs/samples/*.html`、`*.xlsx` 含个人信息，已被 `.gitignore` 忽略，不要复制到其他文件。
- 用户导入的课表/日程文件和导出文件放 `local_data/`；根目录 `*.ics`、`*.xlsx`、`*.xls`、`*.csv`、`*.html` 也已忽略。Windows 运行数据在 `%APPDATA%\com.dailyassistant\daily_assistant\`，不在仓库内。
- 诊断转储在 `%TEMP%\jiaowu_debug_*`，只在本机排查，不提交。
- 课程块同一格只显示一门课：调课/补课优先于正常课，正常课优先于停课标记。
- 时间轴每节左侧是节次，右侧上下排列上课/下课时间；课程块内不重复显示“至 HH:MM”。
- 日程与考试行左滑显示“编辑 / 删除”；日程保留右上角更多菜单。
- 课表口令导出在课表页顶部；口令导入与文件导入都在“导入课表”页，不使用步骤标题。
- 日程“待完成”只保留“已过期”小标题，今天和未来平铺；已完成单独一组。
- 教务消息总览默认收起；展开显示全部消息，收起后一条都不显示。
- 同步页考试行可星标；星标表示考试结束后仍显示在首页。
- 首页考试安排可手动添加考试；手动考试只存本机，清除教务登录数据时保留。

## 数据与同步

- 课表、日程、外观存 `SharedPreferences`；多份课表各有自己的作息。
- 教务快照键为 `jiaowu_snapshot_v1`；消息最多留 100 条，考试最多 200 条。
- 登录态优先复用 Cookie；失效后用保存的密码静默重登一次，失败进 30 秒冷却。
- 学习通同步按 `externalId` 去重；教务同步按考试 `externalId` 合并本地编辑。
- 教务快照保留本学期全部考试，包括已过期考试。
- 已编辑考试：同步保留编辑字段，只刷新 `original` 默认值；教务未返回但已编辑的考试保留。
- 未编辑且未返回的考试移除；手动考试不依赖教务返回，始终保留。
- 首页未过期考试自动显示；过期考试只有星标后才显示。
- 手动删除考试只移除本机条目；下次同步若教务仍返回，会重新加入。
- 单场“恢复默认”只恢复最近一次同步值，不做全局恢复。
- 课表口令是 `DA-TT1:` + gzip + base64url 长文本，不加密；不要公开分享。

## 视觉约定

- canon“温和卡片式应用”：暖中性底、白/炭黑卡片、一个蓝色主操作。
- 卡片 18px 圆角、1px 发丝边框；平面优先，不给卡片加阴影或渐变。
- 紧迫度用文字 + 颜色共同表达；7 天内橙/深橙使用高饱和色，过期/进行中用红色。
- 弹层用 `showModalBottomSheet` 或 `AlertDialog`；动效 160–200ms，`easeOutCubic`。
- 中文正文行高 1.5；时间、倒计时使用等宽数字。

## 测试

- 纯解析/合并逻辑放可单测函数，界面流程用 widget test。
- 不追覆盖率；关键路径验证一次即可。
- 测试样例放 `test/fixtures/`，不得加入真实姓名、学号或 Cookie。
