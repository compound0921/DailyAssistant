import 'package:flutter/material.dart';

/// 标签的固定配色。同一个标签名始终得到同一组颜色，不需要用户自己挑。
class DeadlineTagPalette {
  const DeadlineTagPalette({
    required this.lightBackground,
    required this.lightForeground,
    required this.darkBackground,
    required this.darkForeground,
  });

  final Color lightBackground;
  final Color lightForeground;
  final Color darkBackground;
  final Color darkForeground;
}

const List<DeadlineTagPalette> deadlineTagPalettes = [
  DeadlineTagPalette(
    lightBackground: Color(0xFFE7EEFF),
    lightForeground: Color(0xFF1D4ED8),
    darkBackground: Color(0xFF1B2A44),
    darkForeground: Color(0xFFB6CCFF),
  ),
  DeadlineTagPalette(
    lightBackground: Color(0xFFDDF4EE),
    lightForeground: Color(0xFF0F766E),
    darkBackground: Color(0xFF11332E),
    darkForeground: Color(0xFF6EE7D3),
  ),
  DeadlineTagPalette(
    lightBackground: Color(0xFFE4F3DE),
    lightForeground: Color(0xFF3F6212),
    darkBackground: Color(0xFF1E3315),
    darkForeground: Color(0xFFA3E635),
  ),
  DeadlineTagPalette(
    lightBackground: Color(0xFFFDF0D2),
    lightForeground: Color(0xFF92400E),
    darkBackground: Color(0xFF3A2A10),
    darkForeground: Color(0xFFFCD34D),
  ),
  DeadlineTagPalette(
    lightBackground: Color(0xFFFDE2E7),
    lightForeground: Color(0xFF9F1239),
    darkBackground: Color(0xFF3A1721),
    darkForeground: Color(0xFFFDA4AF),
  ),
  DeadlineTagPalette(
    lightBackground: Color(0xFFEDE4FB),
    lightForeground: Color(0xFF6D28D9),
    darkBackground: Color(0xFF2A1F3D),
    darkForeground: Color(0xFFC4B5FD),
  ),
];

/// 编辑页默认提供的标签，顺序固定。
const List<String> defaultDeadlineTags = ['项目', '学校', '作业', '生活'];

/// 默认标签固定用不同颜色，避免哈希撞色。
const Map<String, int> _defaultTagPaletteIndex = {
  '项目': 0,
  '学校': 1,
  '作业': 3,
  '生活': 4,
};

/// FNV-1a：保证同一标签在重启后仍是同一种颜色。
int stableTagHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

DeadlineTagPalette deadlineTagPaletteFor(String tag) {
  final fixedIndex = _defaultTagPaletteIndex[tag];
  if (fixedIndex != null) return deadlineTagPalettes[fixedIndex];
  return deadlineTagPalettes[stableTagHash(tag) % deadlineTagPalettes.length];
}

Color deadlineTagBackgroundColor(String tag, ThemeData theme) {
  final palette = deadlineTagPaletteFor(tag);
  return theme.brightness == Brightness.dark
      ? palette.darkBackground
      : palette.lightBackground;
}

Color deadlineTagForegroundColor(String tag, ThemeData theme) {
  final palette = deadlineTagPaletteFor(tag);
  return theme.brightness == Brightness.dark
      ? palette.darkForeground
      : palette.lightForeground;
}

/// 日程卡片上的标签胶囊。
class DeadlineTagChip extends StatelessWidget {
  const DeadlineTagChip({super.key, required this.tag, this.onDeleted});

  final String tag;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = deadlineTagForegroundColor(tag, theme);
    return Container(
      padding: EdgeInsets.fromLTRB(8, 2, onDeleted == null ? 8 : 4, 2),
      decoration: BoxDecoration(
        color: deadlineTagBackgroundColor(tag, theme),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onDeleted,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 13, color: foreground),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
