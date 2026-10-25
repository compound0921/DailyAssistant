import 'package:daily_assistant/xuexitong/xuexitong_course_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('course is stale after six months without activity', () {
    final now = DateTime(2026, 10, 25);

    expect(
      XuexitongCourseActivity(
        firstCheckedAt: now.subtract(const Duration(days: 181)),
      ).isStale(now),
      isTrue,
    );

    expect(
      XuexitongCourseActivity(
        firstCheckedAt: now.subtract(const Duration(days: 300)),
        lastActivityAt: now.subtract(const Duration(days: 10)),
      ).isStale(now),
      isFalse,
    );
  });

  test('cache round-trips through SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final cache = XuexitongCourseCache(preferences: preferences);
    final now = DateTime(2026, 10, 25);

    await cache.save({
      'course:class': XuexitongCourseActivity(
        firstCheckedAt: now,
        lastActivityAt: now,
      ),
    });

    final loaded = await cache.load();
    expect(loaded['course:class']?.lastActivityAt, now);
  });
}
