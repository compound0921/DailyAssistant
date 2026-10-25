import 'package:flutter/material.dart';

import '../jiaowu/jiaowu_service.dart';
import '../models/deadline.dart';
import '../xuexitong/xuexitong_deadline_mapper.dart';
import '../xuexitong/xuexitong_service.dart';
import 'app_theme.dart';
import 'jiaowu_page.dart';
import 'xuexitong_page.dart';

enum SyncTarget { xuexitong, jiaowu }

/// “同步”页：学习通与教务共用底部导航的一个入口。
class SyncPage extends StatefulWidget {
  const SyncPage({
    super.key,
    required this.xuexitongService,
    required this.jiaowuService,
    required this.existingDeadlines,
    required this.onCommitXuexitong,
    this.initialTarget = SyncTarget.xuexitong,
  });

  final XuexitongService xuexitongService;
  final JiaowuService jiaowuService;
  final List<Deadline> existingDeadlines;
  final Future<bool> Function(XuexitongMergeResult result) onCommitXuexitong;
  final SyncTarget initialTarget;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late SyncTarget _target = widget.initialTarget;

  @override
  void didUpdateWidget(covariant SyncPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTarget != widget.initialTarget) {
      _target = widget.initialTarget;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<SyncTarget>(
                  segments: const [
                    ButtonSegment(
                      value: SyncTarget.xuexitong,
                      icon: Icon(Icons.school_outlined),
                      label: Text('学习通'),
                    ),
                    ButtonSegment(
                      value: SyncTarget.jiaowu,
                      icon: Icon(Icons.event_note_outlined),
                      label: Text('教务'),
                    ),
                  ],
                  selected: {_target},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _target = selection.first),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _target.index,
            children: [
              XuexitongPage(
                existingDeadlines: widget.existingDeadlines,
                service: widget.xuexitongService,
                onCommit: widget.onCommitXuexitong,
                embedded: true,
              ),
              JiaowuPage(
                service: widget.jiaowuService,
                embedded: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
