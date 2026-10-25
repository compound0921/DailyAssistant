# Surface brief — 校园助手主界面

## Scope

Android + Windows adaptive product shell. Home overview, timetable, Deadline, 学习通, settings, import. Mode: Operate.

## Audience and job

在校学生，打开应用确认“今天上什么、最近要交什么”，然后进入课表或 Deadline 处理。手机快速扫；Windows 上整理和编辑。

## Chosen direction

Canon「温和卡片式应用」— warm neutral ground, white cards, one blue action color, orange/red only for urgency, 16–20px radii, hairline borders, strong type hierarchy. Craft bar: Apple Calendar/Reminders, TickTick, Google Calendar/Tasks.
Memorable moment: “今天” hero card with the next class and a live day timeline; pull-to-refresh updates a quiet sync line.

## Constraints

Keep all current features: multi-timetable import (ICS/Zhengfang HTML/Excel), week view, period times, course edit, Deadline CRUD/clear/toggle, 学习通 login/sync/diagnostics, theme, auto-sync. Local-only, read-only 学习通, no notifications/background sync. Chinese UI, light/dark, 48dp touch targets, urgency not color-only.

## Unresolved

- Exact desktop breakpoint and rail width (decide in implementation; 900px rail).
- Whether to keep the settings page's 学习通 card after bottom nav has a 学习通 tab (decide: remove duplicate entry, keep settings for semester/appearance/theme).
- Whether to add a compact “quick add Deadline” FAB on all sections (decide: keep FAB only on Deadline).

## Direction contract

THESIS: A calm, fast campus assistant that feels like a well-made native utility: one clear next action per screen, the day's schedule and nearest deadlines visible before any navigation, and no decorative world-building.

OWN-WORLD: Warm neutral ground (#F7F5F0 light / #141512 dark), white/charcoal cards, ink text, one blue action (#2F6FED), orange (#D97706) / red (#DC2626) only for urgency, 16–20px radii, 1px hairline borders, SF/PingFang UI with tabular numerals, generous 4/8/12/16/24 spacing; no gradients, no glass, no skeuomorphism.

STORY: The student opens the app, instantly sees the next class and the nearest deadline, and can go to the timetable, Deadline, or 学习通 in one tap; the sync line stays quiet unless something changed.

FIRST VIEWPORT: Mobile: a date/week header with a compact theme/settings overflow; a “今天” hero card with the next class (time, name, room, teacher) and a thin day timeline of remaining classes; below it a “即将到期” list of 2–3 deadline rows with urgency rail and remaining time; a quiet 学习通 sync line; a 5-destination bottom bar. Desktop: a left rail with the same destinations, a two-column content area — today schedule/next class on the left, deadlines + sync on the right — max width ~1120.

FORM: canon (category standard, user-selected standing exit); seed:9ed524f982b0e1f8.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
