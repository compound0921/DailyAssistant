import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../import/period_times.dart';
import '../jiaowu/jiaowu_models.dart';
import '../jiaowu/schedule_adjustments.dart';
import '../models/timetable.dart';
import '../models/timetable_appearance.dart';
import 'timetable_colors.dart';
import 'timetable_format.dart';

const double _timeColumnWidth = 56;
const double _narrowTimeColumnWidth = 36;
const double _headerHeight = 52;

/// 周课表：按第 1-12 节固定行高排布，切换周次后只显示该周的课。
class WeekTimetableView extends StatefulWidget {
  const WeekTimetableView({
    super.key,
    required this.timetable,
    required this.periodSchedule,
    required this.appearance,
    required this.onPeriodTimeChanged,
    required this.onEditCourse,
    this.jiaowuMessages = const [],
    this.onImport,
    this.onDeleteTimetable,
  });

  final Timetable timetable;
  final PeriodSchedule periodSchedule;
  final TimetableAppearance appearance;
  final ValueChanged<PeriodTime> onPeriodTimeChanged;
  final ValueChanged<Course> onEditCourse;
  final List<JiaowuMessage> jiaowuMessages;
  final VoidCallback? onImport;
  final VoidCallback? onDeleteTimetable;

  @override
  State<WeekTimetableView> createState() => _WeekTimetableViewState();
}

class _WeekTimetableViewState extends State<WeekTimetableView> {
  late int _selectedWeek;
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();
  double _weekDragDistance = 0;

  int get _weekCount => widget.timetable.semester.weekCount;

  /// 今天所在周；不在学期范围内时为 null。
  int? get _todayWeek {
    final week = widget.timetable.semester.weekOf(DateTime.now());
    return week >= 1 && week <= _weekCount ? week : null;
  }

  @override
  void initState() {
    super.initState();
    _selectedWeek = _todayWeek ?? 1;
    _bodyScrollController.addListener(_syncHeaderScroll);
  }

  @override
  void dispose() {
    _bodyScrollController.removeListener(_syncHeaderScroll);
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  void _syncHeaderScroll() {
    if (!_headerScrollController.hasClients ||
        !_bodyScrollController.hasClients) {
      return;
    }
    final target = _bodyScrollController.offset.clamp(
      _headerScrollController.position.minScrollExtent,
      _headerScrollController.position.maxScrollExtent,
    );
    if (_headerScrollController.offset != target) {
      _headerScrollController.jumpTo(target);
    }
  }

  @override
  void didUpdateWidget(covariant WeekTimetableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.timetable, widget.timetable)) {
      _selectedWeek = _todayWeek ?? 1;
    } else if (_selectedWeek > _weekCount) {
      _selectedWeek = _weekCount;
    }
  }

  void _selectWeek(int week) {
    if (week < 1 || week > _weekCount || week == _selectedWeek) return;
    setState(() => _selectedWeek = week);
  }

  void _handleWeekSwipe(DragEndDetails details) {
    final distance = _weekDragDistance;
    _weekDragDistance = 0;
    final velocity = details.primaryVelocity ?? 0;
    if (distance.abs() < 48 && velocity.abs() < 250) return;
    final toNext = distance.abs() >= 48 ? distance < 0 : velocity < 0;
    _selectWeek(toNext ? _selectedWeek + 1 : _selectedWeek - 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 手机上一屏放下一周七天，不允许横向滑动。
        final narrow = constraints.maxWidth < 600;
        final rowHeight = widget.appearance.rowHeight;
        final timeColumnWidth = narrow
            ? _narrowTimeColumnWidth
            : _timeColumnWidth;
        final availableWidth = math.max(0.0, constraints.maxWidth - 16);
        final baseDayWidth = math.max(
          1.0,
          (availableWidth - timeColumnWidth) / 7,
        );
        final dayWidth =
            baseDayWidth * (narrow ? 1.0 : widget.appearance.columnScale);
        final dayContentWidth = dayWidth * 7;
        final gridHeight = rowHeight * widget.periodSchedule.times.length;

        if (!narrow) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _syncHeaderScroll(),
          );
        }

        final adjustments = parseScheduleAdjustments(
          messages: widget.jiaowuMessages,
          timetable: widget.timetable,
          periodSchedule: widget.periodSchedule,
        );
        final effectiveMeetings = effectiveMeetingsForWeek(
          timetable: widget.timetable,
          periodSchedule: widget.periodSchedule,
          adjustments: adjustments,
          week: _selectedWeek,
        );
        final headers = _buildDayHeaders(
          context,
          dayWidth: dayWidth,
          fill: narrow,
        );
        final columns = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var weekday = 1; weekday <= 7; weekday++)
              _daySlot(
                fill: narrow,
                width: dayWidth,
                child: _DayColumn(
                  timetable: widget.timetable,
                  periodSchedule: widget.periodSchedule,
                  appearance: widget.appearance,
                  weekday: weekday,
                  effectiveMeetings: effectiveMeetings,
                  rowHeight: rowHeight,
                  narrow: narrow,
                  onEditCourse: widget.onEditCourse,
                ),
              ),
          ],
        );

        return Column(
          children: [
            _buildWeekBar(context),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: narrow
                    ? (_) => _weekDragDistance = 0
                    : null,
                onHorizontalDragUpdate: narrow
                    ? (details) => _weekDragDistance += details.delta.dx
                    : null,
                onHorizontalDragCancel: narrow
                    ? () => _weekDragDistance = 0
                    : null,
                onHorizontalDragEnd: narrow ? _handleWeekSwipe : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Column(
                    children: [
                      SizedBox(
                        height: _headerHeight,
                        child: Row(
                          children: [
                            SizedBox(
                              width: timeColumnWidth,
                              child: _buildTimeHeader(context),
                            ),
                            Expanded(
                              child: narrow
                                  ? headers
                                  : SingleChildScrollView(
                                      controller: _headerScrollController,
                                      scrollDirection: Axis.horizontal,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      child: SizedBox(
                                        width: dayContentWidth,
                                        child: headers,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: timeColumnWidth,
                                height: gridHeight,
                                child: _TimeColumn(
                                  schedule: widget.periodSchedule,
                                  rowHeight: rowHeight,
                                  width: timeColumnWidth,
                                  compact: narrow,
                                  onTimeTap: (time) => showPeriodTimeEditor(
                                    context,
                                    time,
                                    widget.onPeriodTimeChanged,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: narrow
                                    ? SizedBox(
                                        height: gridHeight,
                                        child: columns,
                                      )
                                    : SingleChildScrollView(
                                        controller: _bodyScrollController,
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: dayContentWidth,
                                          height: gridHeight,
                                          child: columns,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 手机端用 Expanded 均分列宽，保证七天正好铺满且不留缝。
  Widget _daySlot({
    required bool fill,
    required double width,
    required Widget child,
  }) {
    return fill ? Expanded(child: child) : SizedBox(width: width, child: child);
  }

  Widget _buildWeekBar(BuildContext context) {
    final theme = Theme.of(context);
    final todayWeek = _todayWeek;
    final hasWarnings =
        (widget.timetable.lastImport?.warnings ?? const []).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed: _selectedWeek > 1
                ? () => _selectWeek(_selectedWeek - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedWeek,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (var week = 1; week <= _weekCount; week++)
                      DropdownMenuItem(value: week, child: Text('第 $week 周')),
                  ],
                  onChanged: (week) {
                    if (week != null) _selectWeek(week);
                  },
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: _selectedWeek < _weekCount
                ? () => _selectWeek(_selectedWeek + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: '本周',
            onPressed: todayWeek != null && todayWeek != _selectedWeek
                ? () => _selectWeek(todayWeek)
                : null,
            icon: const Icon(Icons.today_outlined),
          ),
          IconButton(
            tooltip: '课表信息',
            onPressed: () => showTimetableInfo(context, widget.timetable),
            icon: Badge(
              isLabelVisible: hasWarnings,
              smallSize: 8,
              child: Icon(
                Icons.info_outline,
                color: hasWarnings ? theme.colorScheme.error : null,
              ),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 900)
            PopupMenuButton<String>(
              tooltip: '课表操作',
              onSelected: (value) {
                if (value == 'import') widget.onImport?.call();
                if (value == 'delete') widget.onDeleteTimetable?.call();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'import', child: Text('导入课表')),
                if (widget.onDeleteTimetable != null)
                  const PopupMenuItem(value: 'delete', child: Text('删除当前课表')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTimeHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '点击时间调整作息',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '节次',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Icon(
            Icons.edit_outlined,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeaders(
    BuildContext context, {
    required double dayWidth,
    required bool fill,
  }) {
    final theme = Theme.of(context);
    final gridColor = theme.colorScheme.outlineVariant.withValues(
      alpha: widget.appearance.gridLineOpacity,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          _daySlot(
            fill: fill,
            width: dayWidth,
            child: _DayHeader(
              weekday: weekday,
              date: _dateFor(weekday),
              isToday: _isToday(_dateFor(weekday)),
              gridColor: gridColor,
            ),
          ),
      ],
    );
  }

  DateTime _dateFor(int weekday) {
    return widget.timetable.semester.startDate.add(
      Duration(days: (_selectedWeek - 1) * 7 + weekday - 1),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.weekday,
    required this.date,
    required this.isToday,
    required this.gridColor,
  });

  final int weekday;
  final DateTime date;
  final bool isToday;
  final Color gridColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isToday
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          weekdayLabel(weekday),
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatMonthDay(date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: isToday
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: gridColor)),
      ),
      child: isToday
          ? Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: content,
            )
          : content,
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.schedule,
    required this.rowHeight,
    required this.width,
    required this.compact,
    required this.onTimeTap,
  });

  final PeriodSchedule schedule;
  final double rowHeight;
  final double width;

  /// 手机端列宽紧张，时间用更小的字号。
  final bool compact;
  final ValueChanged<PeriodTime> onTimeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        children: [
          for (final time in schedule.times)
            SizedBox(
              height: rowHeight,
              child: Tooltip(
                message:
                    '第 ${time.period} 节 '
                    '${formatMinutes(time.startMinute)}–'
                    '${formatMinutes(time.endMinute)}，点击调整',
                child: InkWell(
                  onTap: () => onTimeTap(time),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: compact ? 10 : 16,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${time.period}',
                                maxLines: 1,
                                style: compact
                                    ? theme.textTheme.labelSmall
                                    : theme.textTheme.labelMedium,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _AxisTimeLabel(minutes: time.startMinute),
                              const SizedBox(height: 1),
                              _AxisTimeLabel(minutes: time.endMinute),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 时间轴上的单个时刻：每节顶部是上课时间，底部是下课时间。
class _AxisTimeLabel extends StatelessWidget {
  const _AxisTimeLabel({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        formatMinutes(minutes),
        maxLines: 1,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.timetable,
    required this.periodSchedule,
    required this.appearance,
    required this.weekday,
    required this.effectiveMeetings,
    required this.rowHeight,
    required this.narrow,
    required this.onEditCourse,
  });

  final Timetable timetable;
  final PeriodSchedule periodSchedule;
  final TimetableAppearance appearance;
  final int weekday;
  final List<EffectiveMeeting> effectiveMeetings;
  final double rowHeight;
  final bool narrow;
  final ValueChanged<Course> onEditCourse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gridColor = theme.colorScheme.outlineVariant.withValues(
      alpha: appearance.gridLineOpacity,
    );
    final meetings = effectiveMeetings
        .where((item) => item.meeting.weekday == weekday)
        .toList();

    final groups = <String, List<_PlacedMeeting>>{};
    for (final meeting in meetings) {
      final range =
          periodRangeFromLabel(meeting.meeting.periodLabel) ??
          periodSchedule.rangeForMinutes(
            meeting.meeting.startMinute,
            meeting.meeting.endMinute,
          );
      groups
          .putIfAbsent('${range.start}-${range.end}', () => [])
          .add(_PlacedMeeting(meeting, range));
    }

    final blocks = <Widget>[];
    final inset = narrow ? 1.0 : 3.0;
    for (final group in groups.values) {
      final range = group.first.range;
      // 同一格只保留一门课；调课/补课优先于原课和停课标记。
      final placed = group.reduce(
        (current, next) =>
            _slotPriority(next) > _slotPriority(current) ? next : current,
      );
      blocks.add(
        Positioned(
          top: (range.start - 1) * rowHeight + 2,
          left: inset,
          right: inset,
          height: range.length * rowHeight - 4,
          child: _CourseBlock(
            timetable: timetable,
            periodSchedule: periodSchedule,
            appearance: appearance,
            effective: placed.effective,
            narrow: narrow,
            onEditCourse: onEditCourse,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: gridColor)),
      ),
      child: Stack(
        children: [
          for (var index = 0; index < periodSchedule.times.length; index++)
            Positioned(
              top: index * rowHeight,
              left: 0,
              right: 0,
              height: rowHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: gridColor)),
                ),
              ),
            ),
          ...blocks,
        ],
      ),
    );
  }
}

class _PlacedMeeting {
  const _PlacedMeeting(this.effective, this.range);

  final EffectiveMeeting effective;
  final PeriodRange range;
}

/// 同一格内多门课冲突时的显示优先级：调课/补课优先，其次正常课，
/// 最后才是停课/调走标记。
int _slotPriority(_PlacedMeeting placed) {
  final effective = placed.effective;
  if (effective.added) return 2;
  if (!effective.cancelled) return 1;
  return 0;
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    required this.timetable,
    required this.periodSchedule,
    required this.appearance,
    required this.effective,
    required this.narrow,
    required this.onEditCourse,
  });

  final Timetable timetable;
  final PeriodSchedule periodSchedule;
  final TimetableAppearance appearance;
  final EffectiveMeeting effective;
  final bool narrow;
  final ValueChanged<Course> onEditCourse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = effective.course;
    final meeting = effective.meeting;
    final colors = courseBlockColors(course.name, theme.brightness, appearance);
    final adjusted =
        effective.cancelled || effective.added || effective.isSynthetic;
    final location = effective.location;
    final teacher = effective.teacher;
    // 手机端列宽只有 40px 左右，标题字号跟随收窄，避免一个字一行。
    final fontSize = narrow
        ? math.min(appearance.fontSize, 11.5)
        : appearance.fontSize;
    final secondaryFontSize = math.max(8.0, fontSize - 2);
    final horizontalPadding = narrow ? 2.0 : 6.0;
    final verticalPadding = narrow ? 3.0 : 4.0;
    final bottomPadding = effective.label == null
        ? verticalPadding
        : verticalPadding + 12;

    return LayoutBuilder(
      builder: (context, constraints) {
        final innerHeight = math.max(
          0.0,
          constraints.maxHeight - verticalPadding - bottomPadding - 2,
        );
        final titleLineHeight = fontSize * 1.2;
        final maxTitleLines = math.max(
          1,
          (innerHeight / titleLineHeight).floor(),
        );
        // 有地点时最多两行标题，把剩余高度留给地点，避免地点被第三行标题挤掉。
        final titleLines = math.max(
          1,
          math.min(location == null ? 3 : 2, maxTitleLines),
        );
        var usedHeight = titleLines * titleLineHeight;
        final locationLines = location == null
            ? 0
            : math.min(
                2,
                math.max(
                  0,
                  ((innerHeight - usedHeight - 2) / (secondaryFontSize * 1.2))
                      .floor(),
                ),
              );
        if (locationLines > 0) {
          usedHeight += locationLines * secondaryFontSize * 1.2 + 2;
        }
        final showTeacher =
            teacher != null &&
            innerHeight - usedHeight >= secondaryFontSize * 1.2 + 2;
        final textColor = effective.cancelled
            ? colors.foreground.withValues(alpha: 0.58)
            : colors.foreground;
        final secondaryColor = effective.cancelled
            ? colors.foreground.withValues(alpha: 0.42)
            : colors.foreground.withValues(alpha: 0.72);
        final borderColor = effective.added
            ? theme.colorScheme.primary
            : colors.border;
        final borderWidth = effective.added
            ? 2.0
            : (appearance.borderOpacity > 0 ? 1.0 : 0.0);

        return Material(
          color: colors.background,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: borderColor, width: borderWidth),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (adjusted) {
                showAdjustedMeetingDetail(context, effective, periodSchedule);
              } else {
                showMeetingDetail(
                  context,
                  timetable,
                  meeting,
                  periodSchedule,
                  onEditCourse,
                );
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    verticalPadding,
                    horizontalPadding,
                    bottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        maxLines: titleLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          decoration: effective.cancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (locationLines > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            location!,
                            maxLines: locationLines,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: secondaryFontSize,
                              height: 1.2,
                            ),
                          ),
                        ),
                      if (showTeacher)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            teacher,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: secondaryFontSize,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (effective.cancelled)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _HatchPainter(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.16,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (effective.label != null)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: _AdjustmentBadge(
                      label: effective.label!,
                      added: effective.added && !effective.cancelled,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AdjustmentBadge extends StatelessWidget {
  const _AdjustmentBadge({required this.label, required this.added});

  final String label;
  final bool added;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = added
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = added
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 8.5,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const gap = 7.0;
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => oldDelegate.color != color;
}

/// 点击课程后弹出的详情。
Future<void> showMeetingDetail(
  BuildContext context,
  Timetable timetable,
  ClassMeeting meeting,
  PeriodSchedule periodSchedule,
  ValueChanged<Course> onEditCourse,
) {
  final course = timetable.courseById(meeting.courseId);
  if (course == null) return Future<void>.value();

  final labelRange = periodRangeFromLabel(meeting.periodLabel);
  final displaySpan = resolveMeetingSpan(
    schedule: periodSchedule,
    startMinute: meeting.startMinute,
    endMinute: meeting.endMinute,
    periodLabel: meeting.periodLabel,
  );
  final range =
      labelRange ??
      periodSchedule.rangeForMinutes(meeting.startMinute, meeting.endMinute);
  final startMinute = displaySpan.startMinute;
  final endMinute = displaySpan.endMinute;
  final periodText = range.start == range.end
      ? '第 ${range.start} 节'
      : '第 ${range.start}-${range.end} 节';

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(course.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              if (course.teacher != null)
                _DetailRow(icon: Icons.person_outline, text: course.teacher!),
              if (course.location != null)
                _DetailRow(icon: Icons.place_outlined, text: course.location!),
              _DetailRow(
                icon: Icons.schedule,
                text:
                    '${weekdayLabel(meeting.weekday)} '
                    '${formatMinutes(startMinute)}-'
                    '${formatMinutes(endMinute)} · $periodText',
              ),
              _DetailRow(
                icon: Icons.date_range_outlined,
                text: formatWeeks(meeting.weeks),
              ),
              _DetailRow(
                icon: Icons.source_outlined,
                text: course.source.label,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onEditCourse(course);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑课程'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 点击带调课/补课/停课标记的课程后弹出的详情。
Future<void> showAdjustedMeetingDetail(
  BuildContext context,
  EffectiveMeeting effective,
  PeriodSchedule periodSchedule,
) {
  final meeting = effective.meeting;
  final course = effective.course;
  final labelRange = periodRangeFromLabel(meeting.periodLabel);
  final displaySpan = resolveMeetingSpan(
    schedule: periodSchedule,
    startMinute: meeting.startMinute,
    endMinute: meeting.endMinute,
    periodLabel: meeting.periodLabel,
  );
  final range =
      labelRange ??
      periodSchedule.rangeForMinutes(meeting.startMinute, meeting.endMinute);
  final startMinute = displaySpan.startMinute;
  final endMinute = displaySpan.endMinute;
  final periodText = range.start == range.end
      ? '第 ${range.start} 节'
      : '第 ${range.start}-${range.end} 节';
  final label = effective.label;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final background = effective.cancelled
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.primaryContainer;
      final foreground = effective.cancelled
          ? theme.colorScheme.onSurfaceVariant
          : theme.colorScheme.onPrimaryContainer;
      final message = effective.message?.trim();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      course.name,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  if (label != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (effective.teacher != null)
                _DetailRow(
                  icon: Icons.person_outline,
                  text: effective.teacher!,
                ),
              if (effective.location != null)
                _DetailRow(
                  icon: Icons.place_outlined,
                  text: effective.location!,
                ),
              _DetailRow(
                icon: Icons.schedule,
                text:
                    '${weekdayLabel(meeting.weekday)} '
                    '${formatMinutes(startMinute)}-'
                    '${formatMinutes(endMinute)} · $periodText',
              ),
              _DetailRow(
                icon: Icons.date_range_outlined,
                text: formatWeeks(effective.weeksOverride ?? meeting.weeks),
              ),
              _DetailRow(
                icon: Icons.campaign_outlined,
                text: effective.added
                    ? '来自教务消息 · 新增/调整后的课程'
                    : '来自教务消息 · 原课停课/调走',
              ),
              if (message != null && message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('消息内容', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 点击时间列后弹出的作息编辑器：小时、分钟、上课时长。
Future<void> showPeriodTimeEditor(
  BuildContext context,
  PeriodTime current,
  ValueChanged<PeriodTime> onChanged,
) {
  var hour = (current.startMinute ~/ 60).clamp(0, 23).toInt();
  var minute = (((current.startMinute % 60) / 5).round() * 5)
      .clamp(0, 55)
      .toInt();
  var duration = ((current.durationMinutes / 5).round() * 5)
      .clamp(30, 180)
      .toInt();

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final startLabel = formatMinutes(hour * 60 + minute);
          final endLabel = formatMinutes(hour * 60 + minute + duration);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${current.period} 节时间',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '开始时间',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              startLabel,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '结束时间',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              endLabel,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '结束时间由开始时间和上课时长自动计算。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  _TimeSliderRow(
                    label: '小时',
                    value: hour.toDouble(),
                    min: 0,
                    max: 23,
                    divisions: 23,
                    display: '$hour',
                    onChanged: (value) =>
                        setSheetState(() => hour = value.round()),
                  ),
                  _TimeSliderRow(
                    label: '分钟',
                    value: minute.toDouble(),
                    min: 0,
                    max: 55,
                    divisions: 11,
                    display: '$minute',
                    onChanged: (value) =>
                        setSheetState(() => minute = value.round()),
                  ),
                  const Divider(height: 24),
                  Text('上课时长 $duration 分钟', style: theme.textTheme.titleMedium),
                  Slider(
                    value: duration.toDouble(),
                    min: 30,
                    max: 180,
                    divisions: 30,
                    label: '$duration 分钟',
                    onChanged: (value) =>
                        setSheetState(() => duration = value.round()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          onChanged(
                            PeriodTime(
                              current.period,
                              hour * 60 + minute,
                              duration,
                            ),
                          );
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _TimeSliderRow extends StatelessWidget {
  const _TimeSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// 学期、导入来源与警告。
Future<void> showTimetableInfo(BuildContext context, Timetable timetable) {
  final warnings = timetable.lastImport?.warnings ?? const <String>[];

  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final lastImport = timetable.lastImport;
      return AlertDialog(
        title: const Text('课表信息'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第 1 周周一 ${formatDate(timetable.semester.startDate)}'
                  ' · 共 ${timetable.semester.weekCount} 周',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${timetable.courses.length} 门课程 · '
                  '${timetable.meetings.length} 个上课时段',
                  style: theme.textTheme.bodyMedium,
                ),
                if (lastImport != null) ...[
                  const Divider(height: 24),
                  Text(
                    '来源：${lastImport.source.label}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '文件：${lastImport.fileName}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '导入时间：${formatDateTime(lastImport.importedAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (warnings.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    '导入提示（${warnings.length}）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '· $warning',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
