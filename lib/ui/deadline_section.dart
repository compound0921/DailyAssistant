import 'package:flutter/material.dart';

import '../models/deadline.dart';
import 'deadline_colors.dart';
import 'swipe_action_row.dart';
import 'timetable_format.dart';

class DeadlineSection extends StatelessWidget {
  const DeadlineSection({
    super.key,
    required this.deadlines,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onClearExpired,
    required this.onClearCompleted,
  });

  final List<Deadline> deadlines;
  final VoidCallback onCreate;
  final ValueChanged<Deadline> onEdit;
  final ValueChanged<Deadline> onDelete;
  final ValueChanged<Deadline> onToggle;
  final ValueChanged<List<Deadline>> onClearExpired;
  final ValueChanged<List<Deadline>> onClearCompleted;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final groups = groupDeadlines(deadlines, now: now);
    if (groups.isEmpty) {
      return _DeadlineEmpty(onCreate: onCreate);
    }

    final theme = Theme.of(context);
    final expired = [
      for (final item in deadlines)
        if (!item.completed && item.dueAt.isBefore(now)) item,
    ];
    final clearBar = _DeadlineClearBar(
      expiredCount: expired.length,
      completedCount: groups.completed.length,
      onClearExpired: () => onClearExpired(expired),
      onClearCompleted: () => onClearCompleted(groups.completed),
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
                              children: _pendingWidgets(context, groups),
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
                Text(
                  '待完成 (${groups.incompleteCount})',
                  style: theme.textTheme.titleMedium,
                ),
                if (groups.incompleteCount == 0)
                  _emptyHint(theme, '没有待完成')
                else
                  ..._pendingWidgets(context, groups),
                const SizedBox(height: 24),
                Text(
                  '已完成 (${groups.completed.length})',
                  style: theme.textTheme.titleMedium,
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

  Widget _buildColumn(
    BuildContext context, {
    required String title,
    required String emptyText,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(title, style: theme.textTheme.titleMedium),
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

  List<Widget> _pendingWidgets(BuildContext context, DeadlineGroups groups) {
    final theme = Theme.of(context);
    Widget tile(Deadline deadline) {
      return _DeadlineTile(
        deadline: deadline,
        onToggle: () => onToggle(deadline),
        onEdit: () => onEdit(deadline),
        onDelete: () => onDelete(deadline),
      );
    }

    return [
      if (groups.overdue.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Text(
            '已过期',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      for (final deadline in groups.overdue) tile(deadline),
      for (final deadline in [...groups.today, ...groups.future])
        tile(deadline),
    ];
  }

  List<Widget> _completedWidgets(List<Deadline> items) {
    return [
      for (final deadline in items)
        _DeadlineTile(
          deadline: deadline,
          completed: true,
          onToggle: () => onToggle(deadline),
          onEdit: () => onEdit(deadline),
          onDelete: () => onDelete(deadline),
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
    required this.deadline,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.completed = false,
  });

  final Deadline deadline;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final remaining = formatRemaining(deadline.dueAt, now: now);
    final dueLabel = formatDueMoment(deadline.dueAt, now: now);
    final urgency = deadlineUrgency(deadline, now: now, completed: completed);
    final urgencyColor = deadlineUrgencyColor(urgency, theme);
    final urgencyTextColor = deadlineUrgencyTextColor(urgency, theme);
    final note = deadline.note;

    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: urgencyColor, width: 5)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: completed, onChanged: (_) => onToggle()),
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
                                style: completed
                                    ? theme.textTheme.titleSmall?.copyWith(
                                        decoration: TextDecoration.lineThrough,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      )
                                    : theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '更多操作',
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.more_vert, size: 20),
                            onSelected: (value) {
                              if (value == 'edit') {
                                onEdit();
                              } else {
                                onDelete();
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          completed ? dueLabel : '$remaining · $dueLabel',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: completed
                                ? theme.colorScheme.onSurfaceVariant
                                : urgencyTextColor,
                            fontWeight: completed ? null : FontWeight.w600,
                          ),
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
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwipeActionRow(
        borderRadius: BorderRadius.circular(18),
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
        child: card,
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
