import 'package:flutter/material.dart';

/// 左滑后显示的一个操作按钮。
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
}

/// 支持左滑露出操作按钮的行。
///
/// 不依赖第三方库；水平拖动与页面纵向滚动由 Flutter 的手势竞技场区分。
class SwipeActionRow extends StatefulWidget {
  const SwipeActionRow({
    super.key,
    required this.child,
    required this.actions,
    this.backgroundColor,
    this.borderRadius = BorderRadius.zero,
    this.actionWidth = 72,
  }) : assert(actions.length > 0);

  final Widget child;
  final List<SwipeAction> actions;

  /// 行内容的背景色；内容透明时（例如卡片内的一行）需要设置。
  final Color? backgroundColor;
  final BorderRadius borderRadius;
  final double actionWidth;

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow> {
  static const Duration _snapDuration = Duration(milliseconds: 160);

  double _offset = 0;
  bool _dragging = false;

  double get _maxOffset => -widget.actions.length * widget.actionWidth;

  void _onDragStart(DragStartDetails details) {
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_maxOffset == 0) return;
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(_maxOffset, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    setState(() {
      _dragging = false;
      if (velocity < -300) {
        _offset = _maxOffset;
      } else if (velocity > 300) {
        _offset = 0;
      } else {
        _offset = _offset < _maxOffset * 0.35 ? _maxOffset : 0;
      }
    });
  }

  void _onDragCancel() {
    setState(() {
      _dragging = false;
      _offset = 0;
    });
  }

  void _trigger(SwipeAction action) {
    setState(() => _offset = 0);
    action.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _offset == 0,
              child: ExcludeSemantics(
                excluding: _offset == 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final action in widget.actions)
                      SizedBox(
                        width: widget.actionWidth,
                        child: Material(
                          color: action.backgroundColor,
                          child: InkWell(
                            onTap: () => _trigger(action),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  action.icon,
                                  size: 20,
                                  color: action.foregroundColor,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  action.label,
                                  style: TextStyle(
                                    color: action.foregroundColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: _onDragCancel,
            child: AnimatedContainer(
              duration: _dragging ? Duration.zero : _snapDuration,
              curve: Curves.easeOutCubic,
              color: widget.backgroundColor,
              transform: Matrix4.translationValues(_offset, 0, 0),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
