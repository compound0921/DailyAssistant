import 'package:flutter/material.dart';

/// 手机底部弹层、桌面居中弹层，共用中性表面和紧凑选项。
Future<T?> showSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) {
  final theme = Theme.of(context);
  final surface = theme.cardTheme.color ?? theme.colorScheme.surface;
  Widget content(BuildContext sheetContext) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(child: SingleChildScrollView(child: builder(sheetContext))),
        ],
      ),
    ),
  );
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(width: 400, child: content(context)),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: surface,
    elevation: 0,
    builder: content,
  );
}

Future<T?> showSingleSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<(T, String)> options,
}) => showSelectionSheet<T>(
  context: context,
  title: title,
  builder: (context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, label) in options)
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            selected: value == selected,
            selectedColor: theme.colorScheme.onSurface,
            selectedTileColor: theme.colorScheme.primaryContainer,
            title: Text(label, style: theme.textTheme.bodyLarge),
            trailing: value == selected
                ? Icon(Icons.check, color: theme.colorScheme.primary, size: 22)
                : null,
            onTap: () => Navigator.pop(context, value),
          ),
      ],
    );
  },
);

Future<void> showTagFilterSheet({
  required BuildContext context,
  required List<String> tags,
  required Set<String> selectedTags,
  required ValueChanged<Set<String>> onChanged,
}) async {
  var selected = {...selectedTags};
  await showSelectionSheet<void>(
    context: context,
    title: '筛选日程',
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('显示匹配任一所选标签的日程', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                FilterChip(
                  label: Text(tag),
                  selected: selected.contains(tag),
                  onSelected: (value) {
                    setSheetState(() {
                      selected = {...selected};
                      if (value) {
                        selected.add(tag);
                      } else {
                        selected.remove(tag);
                      }
                    });
                    onChanged({...selected});
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        setSheetState(() => selected = {});
                        onChanged({});
                      },
                child: const Text('清除筛选'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
