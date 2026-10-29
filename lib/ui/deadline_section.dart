import 'package:flutter/material.dart';

import '../models/deadline.dart';
import 'deadline_colors.dart';
import 'deadline_tag.dart';
import 'swipe_action_row.dart';
import 'timetable_format.dart';

class DeadlineSection extends StatefulWidget {
  const DeadlineSection({
    super.key,
    required this.deadlines,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onClearExpired,
    required this.onClearCompleted,
    required this.onReorder,
    required this.onTogglePin,
    required this.onResetOrder,
    required this.onDeleteSelected,
  });

  final List<Deadline> deadlines;
  final VoidCallback onCreate;
  final ValueChanged<Deadline> onEdit;
  final ValueChanged<Deadline> onDelete;
  final ValueChanged<Deadline> onToggle;
  final ValueChanged<List<Deadline>> onClearExpired;
  final ValueChanged<List<Deadline>> onClearCompleted;

  /// 拖动结束后按新的视觉顺序回传待完成列表。
  final ValueChanged<List<Deadline>> onReorder;
  final ValueChanged<Deadline> onTogglePin;

  /// 清除所有手动顺序与置顶，恢复默认排序。
  final VoidCallback onResetOrder;

  /// 删除批量选中的日程。
  final ValueChanged<List<Deadline>> onDeleteSelected;

  @override
  State<DeadlineSection> createState() => _DeadlineSectionState();
}

class _DeadlineSectionState extends State<DeadlineSection> {
  bool _editing = false;
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  /// 拖动后先用的本地顺序，避免数据还没回传时列表先回弹再跳位。
  List<Deadline>? _pendingOverride;

  @override
  void didUpdateWidget(covariant DeadlineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.deadlines, widget.deadlines)) {
      _pendingOverride = null;
    }
  }

  Widget _pendingActions(ThemeData theme) {
    if (_selecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '删除选中',
            onPressed: _selectedIds.isEmpty ? null : _confirmDeleteSelected,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: '取消选择',
            onPressed: () => setState(() {
              _selecting = false;
              _selectedIds.clear();
            }),
            icon: const Icon(Icons.close),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '排序',
          onPressed: () => setState(() {
            _selecting = false;
            _selectedIds.clear();
            _editing = true;
          }),
          icon: const Icon(Icons.build_outlined),
        ),
        IconButton(
          tooltip: '批量选择',
          onPressed: () => setState(() {
            _selecting = true;
            _selectedIds.clear();
          }),
          icon: const Icon(Icons.check_circle_outline),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final selected = [
      for (final deadline in widget.deadlines)
        if (_selectedIds.contains(deadline.id)) deadline,
    ];
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日程'),
        content: Text('将删除选中的 ${selected.length} 条日程，且无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.onDeleteSelected(selected);
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final groups = groupDeadlines(widget.deadlines, now: now);
    if (groups.isEmpty) {
      return _DeadlineEmpty(onCreate: widget.onCreate);
    }
    if (_editing) {
      return _buildEditor(context, groups, now);
    }

    final theme = Theme.of(context);
    final expired = [
      for (final item in widget.deadlines)
        if (!item.completed && item.dueAt != null && item.dueAt!.isBefore(now))
          item,
    ];
    final clearBar = _DeadlineClearBar(
      expiredCount: expired.length,
      completedCount: groups.completed.length,
      onClearExpired: () => widget.onClearExpired(expired),
      onClearCompleted: () => widget.onClearCompleted(groups.completed),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: SizedBox(
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: clearBar,
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildColumn(
                              context,
                              title: '待完成 (${groups.incompleteCount})',
                              emptyText: '没有待完成',
                              trailing: _pendingActions(theme),
                              children: _pendingWidgets(context, groups, now),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildColumn(
                              context,
                              title: '已完成 (${groups.completed.length})',
                              emptyText: '没有已完成',
                              children: _completedWidgets(groups.completed),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                clearBar,
                const SizedBox(height: 8),
                _sectionHeader(
                  theme,
                  '待完成 (${groups.incompleteCount})',
                  trailing: _pendingActions(theme),
                ),
                if (groups.incompleteCount == 0)
                  _emptyHint(theme, '没有待完成')
                else
                  ..._pendingWidgets(context, groups, now),
                const SizedBox(height: 24),
                _sectionHeader(
                  theme,
                  '已完成 (${groups.completed.length})',
                ),
                if (groups.completed.isEmpty)
                  _emptyHint(theme, '没有已完成')
                else
                  ..._completedWidgets(groups.completed),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(
    ThemeData theme,
    String title, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        ?trailing,
      ],
    );
  }

  Widget _buildColumn(
    BuildContext context, {
    required String title,
    required String emptyText,
    required List<Widget> children,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _sectionHeader(theme, title, trailing: trailing),
          ),
          Expanded(
            child: children.isEmpty
                ? Center(
                    child: Text(
                      emptyText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                    children: children,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(
    BuildContext context,
    DeadlineGroups groups,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final pending = _pendingOverride ?? groups.incomplete;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '拖动调整顺序，点图钉置顶',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onResetOrder,
                    child: const Text('恢复默认排序'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _editing = false;
                      _pendingOverride = null;
                    }),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: pending.isEmpty
                  ? Center(
                      child: Text(
                        '没有待完成',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: pending.length,
                      // 手柄由行内按钮提供，关闭默认长按拖拽避免双触发。
                      buildDefaultDragHandles: false,
                      // 默认的拖动代理会给卡片套一层白色材质，这里保持原样式。
                      proxyDecorator: (child, index, animation) =>
                          Material(type: MaterialType.transparency, child: child),
                      onReorderItem: (oldIndex, newIndex) {
                        final next = [...pending];
                        final item = next.removeAt(oldIndex);
                        next.insert(newIndex, item);
                        setState(() => _pendingOverride = next);
                        widget.onReorder(next);
                      },
                      itemBuilder: (context, index) {
                        final deadline = pending[index];
                        return _DeadlineTile(
                          key: ValueKey(deadline.id),
                          deadline: deadline,
                          overdue: deadline.dueAt != null &&
                              deadline.dueAt!.isBefore(now),
                          editing: true,
                          dragIndex: index,
                          onToggle: () => widget.onToggle(deadline),
                          onEdit: () {},
                          onDelete: () {},
                          onTogglePin: () => widget.onTogglePin(deadline),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _pendingWidgets(
    BuildContext context,
    DeadlineGroups groups,
    DateTime now,
  ) {
    return [
      for (final deadline in groups.incomplete)
        _DeadlineTile(
          deadline: deadline,
          overdue: deadline.dueAt != null && deadline.dueAt!.isBefore(now),
          selecting: _selecting,
          selected: _selectedIds.contains(deadline.id),
          onToggleSelect: _selecting
              ? () => setState(() {
                  if (!_selectedIds.remove(deadline.id)) {
                    _selectedIds.add(deadline.id);
                  }
                })
              : null,
          onToggle: () => widget.onToggle(deadline),
          onEdit: () => widget.onEdit(deadline),
          onDelete: () => widget.onDelete(deadline),
        ),
    ];
  }

  List<Widget> _completedWidgets(List<Deadline> items) {
    return [
      for (final deadline in items)
        _DeadlineTile(
          deadline: deadline,
          completed: true,
          onToggle: () => widget.onToggle(deadline),
          onEdit: () => widget.onEdit(deadline),
          onDelete: () => widget.onDelete(deadline),
        ),
    ];
  }

  Widget _emptyHint(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DeadlineClearBar extends StatelessWidget {
  const _DeadlineClearBar({
    required this.expiredCount,
    required this.completedCount,
    required this.onClearExpired,
    required this.onClearCompleted,
  });

  final int expiredCount;
  final int completedCount;
  final VoidCallback onClearExpired;
  final VoidCallback onClearCompleted;

  @override
  Widget build(BuildContext context) {
    if (expiredCount == 0 && completedCount == 0) {
      return const SizedBox.shrink();
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 2,
      runSpacing: 4,
      children: [
        if (expiredCount > 0)
          TextButton.icon(
            onPressed: onClearExpired,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text('清除已截止 ($expiredCount)'),
          ),
        if (completedCount > 0)
          TextButton.icon(
            onPressed: onClearCompleted,
            icon: const Icon(Icons.done_all, size: 18),
            label: Text('清除已完成 ($completedCount)'),
          ),
      ],
    );
  }
}

class _DeadlineTile extends StatelessWidget {
  const _DeadlineTile({
    super.key,
    required this.deadline,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.completed = false,
    this.overdue = false,
    this.editing = false,
    this.dragIndex,
    this.onTogglePin,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
  });

  final Deadline deadline;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool completed;
  final bool overdue;

  /// 排序编辑模式：保留原样式，并显示置顶与拖动手柄。
  final bool editing;
  final int? dragIndex;
  final VoidCallback? onTogglePin;

  /// 批量选择模式：点击整行切换选中。
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final remaining = formatRemaining(deadline.dueAt, now: now);
    final dueLabel = formatDueMoment(deadline.dueAt, now: now);
    final urgency = deadlineUrgency(deadline, now: now, completed: completed);
    final faded = completed || overdue;
    final urgencyColor = overdue
        ? theme.colorScheme.outline
        : deadlineUrgencyColor(urgency, theme);
    final urgencyTextColor = faded
        ? theme.colorScheme.onSurfaceVariant
        : deadlineUrgencyTextColor(urgency, theme);
    final note = deadline.note;

    final row = InkWell(
      onTap: selecting
          ? onToggleSelect
          : editing
          ? null
          : onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                color: urgencyColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Checkbox(
              value: selecting ? selected : completed,
              onChanged: (_) =>
                  selecting ? onToggleSelect?.call() : onToggle(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (deadline.source != DeadlineSource.manual)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, right: 4),
                          child: Icon(
                            _deadlineSourceIcon(deadline.source),
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            deadline.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: faded
                                ? theme.textTheme.titleSmall?.copyWith(
                                    decoration: TextDecoration.lineThrough,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  )
                                : theme.textTheme.titleMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            completed
                                ? dueLabel
                                : deadline.dueAt == null
                                ? '无截止时间'
                                : '$remaining · $dueLabel',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: urgencyTextColor,
                              fontWeight: faded ? null : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (deadline.tags.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 4,
                              runSpacing: 2,
                              children: [
                                for (final tag in deadline.tags)
                                  DeadlineTagChip(tag: tag),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (deadline.courseName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        deadline.courseName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Text(
                        note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (editing) ...[
              IconButton(
                tooltip: deadline.pinned ? '取消置顶' : '置顶',
                onPressed: onTogglePin,
                icon: Icon(
                  deadline.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: deadline.pinned ? theme.colorScheme.primary : null,
                ),
              ),
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          color: selecting && selected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          child: editing || selecting
              ? row
              : SwipeActionRow(
                backgroundColor:
                    theme.cardTheme.color ?? theme.colorScheme.surface,
                onFullSwipe: onToggle,
                actions: [
                  SwipeAction(
                    label: '编辑',
                    icon: Icons.edit_outlined,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    onPressed: onEdit,
                  ),
                  SwipeAction(
                    label: '删除',
                    icon: Icons.delete_outline,
                    backgroundColor: theme.colorScheme.errorContainer,
                    foregroundColor: theme.colorScheme.onErrorContainer,
                    onPressed: onDelete,
                  ),
                ],
                child: row,
              ),
        ),
      ),
    );
  }
}

class _DeadlineEmpty extends StatelessWidget {
  const _DeadlineEmpty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.checklist, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('还没有日程', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '记录作业、考试和其他截止事项。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('新增日程'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _deadlineSourceIcon(DeadlineSource source) {
  return switch (source) {
    DeadlineSource.xuexitong => Icons.school_outlined,
    DeadlineSource.jiaowu => Icons.event_note_outlined,
    DeadlineSource.manual => Icons.edit_outlined,
  };
}
