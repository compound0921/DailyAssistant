---
name: 校园助手
description: 本地优先的课表、日程与学习通同步助手
colors:
  surface: "#F7F5F0"
  surface-dark: "#141512"
  card: "#FFFFFF"
  card-dark: "#1E1F1C"
  ink: "#1B1B18"
  ink-dark: "#F2EFE8"
  muted: "#6B6B63"
  muted-dark: "#A6A69C"
  outline: "#E6E0D6"
  outline-dark: "#343630"
  primary: "#2F6FED"
  primary-dark: "#8FB3FF"
  primary-text: "#1D4ED8"
  primary-text-dark: "#B6CCFF"
  primary-container: "#E7EEFF"
  primary-container-dark: "#1B2A44"
  urgent: "#D97706"
  urgent-dark: "#FBBF24"
  urgent-text: "#B45309"
  urgent-text-dark: "#FBBF24"
  danger: "#DC2626"
  danger-dark: "#F87171"
typography:
  headline:
    fontFamily: "system-ui, -apple-system, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: "24px"
    fontWeight: 800
    lineHeight: 1.15
    letterSpacing: "-0.5px"
  title:
    fontFamily: "system-ui, -apple-system, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.2px"
  body:
    fontFamily: "system-ui, -apple-system, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "system-ui, -apple-system, PingFang SC, Microsoft YaHei, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.4
rounded:
  card: "18px"
  control: "14px"
  pill: "999px"
  rail: "2px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "16px"
  card-dark:
    backgroundColor: "{colors.card-dark}"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.card}"
    padding: "16px"
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.control}"
    height: "48px"
    padding: "0 20px"
  button-outline:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    height: "48px"
    padding: "0 16px"
  hero:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.ink}"
    rounded: "20px"
    padding: "20px"
---

## Overview

Canon「温和卡片式应用」：一个本地优先的校园助手，先回答“今天上什么、最近要交什么”，其余功能保持安静。质量参照 Apple 日历/提醒事项、滴答清单、Google Calendar/Tasks。

视觉世界只做四件事：字、色、密度、一个签名动作。签名动作是“今天”焦点卡与手机端按天议程；不做装饰性世界构建。

## Colors

- 蓝 `primary` 只用于可执行动作和选中态；文字链接用更深的 `primary-text`。
- 橙 `urgent` 只用色块；小字号文字用更深的 `urgent-text`；红 `danger` 表示已过期。颜色必须配合文字或剩余时间，不能只靠色块。
- `outline` / `outlineVariant` 只做边框，绝不用作文字颜色；正文次要信息用 `onSurfaceVariant`。
- 暖中性底 + 白/炭黑卡片构成层级。不要用渐变、玻璃、发光或多色装饰。
- 课程块颜色由课程名生成，属于用户可调的外观设置，不纳入全局色板。

## Typography

- 系统 UI 字体；中文优先 PingFang SC / Microsoft YaHei，不引入展示型字体。
- 字号层级：24/20/16/14/12。卡片内最多三种字号。
- 时间、日期、倒计时启用等宽数字 `tabularFigures`，避免跳动。
- 正文行高 1.5；标题行高 1.15–1.2。

## Layout

- 手机：底部 5 项导航（首页/课表/日程/同步/设置）。
- 手机课表：固定时间轴的周网格，七天在一屏内等分，不横向滑动；时间列 36px。
- 600–899px：完整周网格，时间轴固定，列宽可调并可横向滑动。
- 900px 以上：左侧导航栏 + 内容区；首页为左右双栏，最大宽 1120px。
- 设置页最大宽 560px，学习通页 760px；页面统一 16px 外边距。
- 触控目标不小于 48dp；桌面支持鼠标与键盘焦点。

## Elevation & Depth

- 平面优先：卡片无阴影，用 1px 发丝边框和表面色差分层。
- FAB 与 SnackBar 允许轻微 elevation（2），其余组件保持平面。
- 焦点卡用 `primaryContainer` 的浅色底，而不是阴影或渐变。

## Shapes

- 卡片 18px 圆角；按钮/输入框 14px；胶囊 999px；时间/紧迫度竖条 2–4px。
- 边框一律 1px；不使用粗描边或多层嵌套卡片。
- 图标 18–24px；不使用容器套容器。

## Components

- **应用外壳**：`NavigationBar`（手机）/ `NavigationRail`（Windows），选中态用蓝色容器 + 蓝色图标/文字。
- **AppBar**：标题左对齐、无阴影、底部 1px 分隔；右侧只保留当前页需要的动作和主题切换。
- **今天焦点卡**：浅蓝底、左侧时间列、课程名/地点/教师；整卡可点进课表。
- **今日时间轴**：单张卡片内按时间排课，进行中用蓝色竖条和“进行中”胶囊；过去的课降低不透明度。
- **日程**：单张卡片内 3 行以内，左侧紧迫度竖条 + 剩余时间；点击进入日程。
- **手机课表**：固定时间轴的周网格，七天同屏等分、不可横向滑动；时间列可点击调整作息，课程块可点击编辑课程。时间轴每节左侧放节次、右侧上下排列上课/下课时间；今天列头用 `primaryContainer` 圆角色块强调。
- **日程列表**：待完成只保留“已过期”小标题，今天和未来平铺；已完成单独一组。每条一张卡；左滑显示“编辑 / 删除”，保留右上角更多菜单；一键清除用文字按钮，不抢主操作。
- **课表调整标记**：调课/补课块用 2px 蓝色边框 + 右下角角标；停课/调走块叠加斜线阴影、删除线和角标。同一格只显示一门课，调课/补课优先于原课和停课标记。首页“今天”用同样角标 + 删除线，不额外加卡片。左侧时间轴每节左侧放节次、右侧上下排列上课和下课时间，课程块内不重复。
- **首页右栏**：“日程”预览 + “考试安排”（未过期考试自动显示，过期考试星标后显示，最近 3 场），不显示学习通/教务同步状态卡；底部“同步”入口保留。考试标题旁有“添加”；考试行点击进入编辑；考试行与日程行左滑都显示“编辑 / 删除”。
- **考试编辑**：白底表单，全部字段可改；保存只写本机。已编辑的考试在底部显示“恢复默认”，恢复前二次确认。
- **考试安排颜色**：剩余时间四档——7 天以上蓝色，4-7 天亮橙色，1-3 天深橙色，今天/进行中红色；7 天内的橙/深橙使用高饱和色。首页已过期考试整行用灰色，包括日期、竖条、课程名和剩余时间。
- **同步**：页内分“学习通 / 教务”。两边都是账号卡 + 立即同步（唯一蓝色主按钮）+ 清除数据（描边按钮）；诊断信息折叠。教务页另列消息总览与考试安排；消息总览默认收起，考试行用星标控制在首页的考后保留。
- **导入课表**：页面同时提供“从文件导入”和“粘贴课表口令”，不使用步骤标题；口令导入保留原课表名称与作息。
- **课表导出口令**：课表页顶部图标入口（设置页不再提供）；页面展示当前课表、生成/复制口令和上次口令。口令是一段等宽字体的长文本，不加密，页面需提示“请勿公开分享”。
- **动效**：160ms 日期选择，200ms 主题切换，`easeOutCubic`；不做循环或入场动画。

## Do's and Don'ts

- Do：让“今天/最近截止”在首屏可见；保持一个主蓝色动作。
- Do：用文字 + 颜色共同表达紧迫度。
- Do：手机端优先可读性，课程名不拆成两三个字一行。
- Don't：不要给卡片加阴影、渐变、玻璃或彩色边框。
- Don't：不要嵌套卡片，也不要在同一屏放两个主蓝色按钮。
- Don't：不要用动画掩盖状态变化；尊重减少动效设置。
- Don't：不要为“好看”牺牲 48dp 触控目标或中文字号。
