# flutter_chaoxing（裁剪内嵌版）

本目录是 pub.dev 包 `flutter_chaoxing` 0.4.2 的裁剪副本，Apache-2.0，出处：
<https://pub.dev/packages/flutter_chaoxing>。上游 GitHub 仓库地址已不可访问。

## 保留

- `chaoxing_auth_service.dart`：passport2 账号密码登录、SSO Cookie 获取。
- `chaoxing_api_service.dart`：通知、作业、考试、成绩、课表等只读接口。
- `chaoxing_user_agent.dart`：官方客户端 UA；`mobilelearn.chaoxing.com`
  的活动列表和活动详情只接受该 UA，浏览器 UA 会返回 `status=0`。
- 登录与接口依赖的模型、签名工具。

## 移除

- `chaoxing_sign_service.dart`：课堂签到、人脸签到等写操作。
- `chaoxing_captcha.dart`：滑块验证码求解。
- `chaoxing_sign_crypto.dart` 中的设备 RSA、`webRequestSign` 和内嵌私钥：只保留 `inf_enc` 查询签名。
- `image` 依赖：随之移除，避免与项目现有 `excel`/`archive` 版本冲突。

本项目只使用登录和只读数据接口，不调用任何签到、答题或人脸相关能力。

## 本地修改

- `parseWorkList` / `parseExamList` 保留整行文本，不再只取第一个 `<p>` 或第二个 `<td>`，避免丢失截止时间列。

## 注意

- 代码来自第三方协议还原，端点与常量可能随学习通客户端更新失效。
- 修改本目录代码时请保留本说明和 LICENSE。
