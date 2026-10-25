import 'package:flutter/material.dart';

import '../models/timetable.dart';

class CourseEditPage extends StatefulWidget {
  const CourseEditPage({super.key, required this.course});

  final Course course;

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _teacherController;
  late final TextEditingController _locationController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.course.name);
    _teacherController = TextEditingController(
      text: widget.course.teacher ?? '',
    );
    _locationController = TextEditingController(
      text: widget.course.location ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _restoreOriginal() {
    setState(() {
      _nameController.text = widget.course.originalName;
      _teacherController.text = widget.course.originalTeacher ?? '';
      _locationController.text = widget.course.originalLocation ?? '';
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已恢复导入时的信息，点击保存后应用')));
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请填写课程名称')));
      return;
    }

    final teacher = _teacherController.text.trim();
    final location = _locationController.text.trim();
    Navigator.of(context).pop(
      Course(
        id: widget.course.id,
        name: name,
        teacher: teacher.isEmpty ? null : teacher,
        location: location.isEmpty ? null : location,
        source: widget.course.source,
        originalName: widget.course.originalName,
        originalTeacher: widget.course.originalTeacher,
        originalLocation: widget.course.originalLocation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑课程'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  autofocus: false,
                  textInputAction: TextInputAction.next,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: '课程名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _teacherController,
                  textInputAction: TextInputAction.next,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: '教师（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _locationController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: '地点（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '修改会同步到这门课的所有上课时段。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _restoreOriginal,
                    icon: const Icon(Icons.restore),
                    label: const Text('恢复导入时的信息'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
