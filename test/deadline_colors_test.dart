import 'package:daily_assistant/models/deadline.dart';
import 'package:daily_assistant/ui/deadline_colors.dart';
import 'package:flutter_test/flutter_test.dart';

Deadline deadlineAt(DateTime due, {bool completed = false}) {
  return Deadline(
    id: 'deadline',
    title: '测试',
    dueAt: due,
    createdAt: due,
    updatedAt: due,
    completed: completed,
  );
}

void main() {
  final now = DateTime(2026, 10, 25, 12);

  test('classifies deadlines by remaining time', () {
    expect(
      deadlineUrgency(deadlineAt(DateTime(2026, 10, 25, 11)), now: now),
      DeadlineUrgency.overdue,
    );
    expect(
      deadlineUrgency(deadlineAt(DateTime(2026, 10, 25, 18)), now: now),
      DeadlineUrgency.today,
    );
    expect(
      deadlineUrgency(deadlineAt(DateTime(2026, 10, 27, 9)), now: now),
      DeadlineUrgency.soon,
    );
    expect(
      deadlineUrgency(deadlineAt(DateTime(2026, 10, 30, 9)), now: now),
      DeadlineUrgency.week,
    );
    expect(
      deadlineUrgency(deadlineAt(DateTime(2026, 11, 10, 9)), now: now),
      DeadlineUrgency.later,
    );
  });

  test('completed takes precedence over the due time', () {
    expect(
      deadlineUrgency(
        deadlineAt(DateTime(2026, 10, 20), completed: true),
        now: now,
      ),
      DeadlineUrgency.completed,
    );
  });
}
