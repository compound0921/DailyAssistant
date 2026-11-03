import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.onFullSwipe,
    this.fullSwipeExtraWidth = 72,
    this.fullSwipeLabel = '完成',
    this.fullSwipeDoneLabel = '已完成',
  }) : assert(actions.length > 0);

  final Widget child;
  final List<SwipeAction> actions;

  /// 行内容的背景色；内容透明时（例如卡片内的一行）需要设置。
  final Color? backgroundColor;
  final BorderRadius borderRadius;
  final double actionWidth;

  /// 继续向左拖动超过操作区后触发；null 时不启用完整左滑。
  final FutureOr<void> Function()? onFullSwipe;
  final String fullSwipeLabel;
  final String fullSwipeDoneLabel;

  /// 完整左滑需要超出操作区的最小距离。
  final double fullSwipeExtraWidth;

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow>
    with SingleTickerProviderStateMixin {
  static const Duration _snapDuration = Duration(milliseconds: 160);

  double _offset = 0;
  double _dragOverflow = 0;
  double _rawOffset = 0;
  bool _dragging = false;
  bool _completing = false;
  late final AnimationController _completion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  FutureOr<void> Function()? _pendingCommit;

  bool get _armed =>
      widget.onFullSwipe != null && _dragOverflow >= widget.fullSwipeExtraWidth;

  @override
  void dispose() {
    // 松手已经确认的操作即使页面提前关闭也只提交一次。
    final pending = _pendingCommit;
    _pendingCommit = null;
    if (pending != null) {
      scheduleMicrotask(() => Future<void>.sync(pending).ignore());
    }
    _completion.dispose();
    super.dispose();
  }

  double get _maxOffset => -widget.actions.length * widget.actionWidth;

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _dragOverflow = 0;
      _rawOffset = _offset;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_maxOffset == 0) return;
    final next = _rawOffset + details.delta.dx;
    final wasArmed = _armed;
    setState(() {
      _rawOffset = next;
      _offset = next.clamp(_maxOffset, 0.0);
      _dragOverflow = next < _maxOffset ? _maxOffset - next : 0;
    });
    if (!wasArmed && _armed) unawaited(HapticFeedback.selectionClick());
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final fullSwipe = _armed;
    if (fullSwipe) {
      unawaited(_completeFullSwipe());
      return;
    }
    setState(() {
      _dragging = false;
      _dragOverflow = 0;
      if (velocity < -300) {
        _offset = _maxOffset;
      } else if (velocity > 300) {
        _offset = 0;
      } else {
        _offset = _offset < _maxOffset * 0.35 ? _maxOffset : 0;
      }
    });
  }

  Future<void> _completeFullSwipe() async {
    if (_completing || widget.onFullSwipe == null) return;
    _pendingCommit = widget.onFullSwipe;
    final reduce = MediaQuery.disableAnimationsOf(context);
    _completion.duration = Duration(milliseconds: reduce ? 100 : 280);
    setState(() {
      _dragging = false;
      _completing = true;
    });
    try {
      await _completion.forward().orCancel;
      final commit = _pendingCommit;
      _pendingCommit = null;
      if (commit != null) await Future<void>.sync(commit);
    } on TickerCanceled {
      // dispose 已安排提交，避免因用户离开页面而丢失已确认操作。
    } finally {
      if (mounted) {
        setState(() {
          _completing = false;
          _offset = 0;
          _rawOffset = 0;
          _dragOverflow = 0;
          _completion.reset();
        });
      }
    }
  }

  void _onDragCancel() {
    setState(() {
      _dragging = false;
      _dragOverflow = 0;
      _offset = 0;
    });
  }

  void _trigger(SwipeAction action) {
    setState(() => _offset = 0);
    action.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _completion,
      builder: (context, _) {
        final value = _completion.value;
        final collapse = const Interval(
          .36,
          1,
          curve: Curves.easeOutCubic,
        ).transform(value);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _completing && !reduce ? 1 - collapse : 1,
            child: Opacity(
              opacity: _completing ? 1 - (reduce ? value : collapse) : 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final confirm = Curves.easeOutCubic.transform(
                    (value / .36).clamp(0, 1),
                  );
                  final offset = _completing && !reduce
                      ? _offset + (-constraints.maxWidth - _offset) * confirm
                      : _offset;
                  final showFeedback =
                      _completing ||
                      (widget.onFullSwipe != null && _dragOverflow > 0);
                  return ClipRRect(
                    borderRadius: widget.borderRadius,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Stack(
                        children: [
                          if (showFeedback)
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: AnimatedContainer(
                                  duration: _dragging || _completing || reduce
                                      ? Duration.zero
                                      : _snapDuration,
                                  height: double.infinity,
                                  width: _completing
                                      ? reduce
                                            ? constraints.maxWidth
                                            : -_maxOffset +
                                                  (constraints.maxWidth +
                                                          _maxOffset) *
                                                      confirm
                                      : -_maxOffset,
                                  color: _armed || _completing
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.primaryContainer,
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            AnimatedScale(
                                              scale: _armed || _completing
                                                  ? 1
                                                  : .9,
                                              duration: reduce
                                                  ? Duration.zero
                                                  : _snapDuration,
                                              curve: Curves.easeOutCubic,
                                              child: Icon(
                                                _armed || _completing
                                                    ? Icons.check_circle
                                                    : Icons.arrow_back,
                                                size: 24,
                                                color: _armed || _completing
                                                    ? theme
                                                          .colorScheme
                                                          .onPrimary
                                                    : theme
                                                          .colorScheme
                                                          .onPrimaryContainer,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _completing
                                                  ? widget.fullSwipeDoneLabel
                                                  : _armed
                                                  ? '松开即可${widget.fullSwipeLabel}'
                                                  : '继续左滑${widget.fullSwipeLabel}',
                                              maxLines: 1,
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                    color: _armed || _completing
                                                        ? theme
                                                              .colorScheme
                                                              .onPrimary
                                                        : theme
                                                              .colorScheme
                                                              .onPrimaryContainer,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        if (!_completing)
                                          Positioned(
                                            left: 12,
                                            right: 12,
                                            bottom: 5,
                                            child: LinearProgressIndicator(
                                              value:
                                                  (_dragOverflow /
                                                          widget
                                                              .fullSwipeExtraWidth)
                                                      .clamp(0, 1),
                                              minHeight: 3,
                                              color: _armed
                                                  ? theme.colorScheme.onPrimary
                                                  : theme.colorScheme.primary,
                                              backgroundColor:
                                                  Colors.transparent,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: _offset == 0,
                                child: ExcludeSemantics(
                                  excluding: _offset == 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final action in widget.actions)
                                        SizedBox(
                                          width: widget.actionWidth,
                                          child: Material(
                                            color: action.backgroundColor,
                                            child: InkWell(
                                              onTap: () => _trigger(action),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    action.icon,
                                                    size: 20,
                                                    color:
                                                        action.foregroundColor,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    action.label,
                                                    style: TextStyle(
                                                      color: action
                                                          .foregroundColor,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
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
                          IgnorePointer(
                            ignoring: _completing,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onHorizontalDragStart: _onDragStart,
                              onHorizontalDragUpdate: _onDragUpdate,
                              onHorizontalDragEnd: _onDragEnd,
                              onHorizontalDragCancel: _onDragCancel,
                              child: AnimatedContainer(
                                width: constraints.maxWidth,
                                duration: _dragging || _completing || reduce
                                    ? Duration.zero
                                    : _snapDuration,
                                curve: Curves.easeOutCubic,
                                color: widget.backgroundColor,
                                transform: Matrix4.translationValues(
                                  offset,
                                  0,
                                  0,
                                ),
                                child: Opacity(
                                  opacity: _completing && reduce ? 0 : 1,
                                  child: widget.child,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
