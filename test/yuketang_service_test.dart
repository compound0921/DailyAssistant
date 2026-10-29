import 'package:daily_assistant/ui/app_theme.dart';
import 'package:daily_assistant/ui/yuketang_course_page.dart';
import 'package:daily_assistant/ui/yuketang_page.dart';
import 'package:daily_assistant/yuketang/yuketang_models.dart';
import 'package:daily_assistant/yuketang/yuketang_service.dart';
import 'package:daily_assistant/yuketang/yuketang_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseYuketangLoginTicket', () {
    test('reads qrContent and token', () {
      final now = DateTime(2026, 10, 26, 9);
      final ticket = parseYuketangLoginTicket({
        'code': 0,
        'data': {
          'qrContent': 'https://example.test/qr?u=abc',
          'token': 'header.payload.signature',
          'qrImage': '',
        },
      }, now: now);

      expect(ticket, isNotNull);
      expect(ticket!.qrContent, 'https://example.test/qr?u=abc');
      expect(ticket.token, 'header.payload.signature');
      expect(ticket.expiresAt, now.add(const Duration(minutes: 5)));
      expect(ticket.isExpired(now.add(const Duration(minutes: 4))), isFalse);
      expect(ticket.isExpired(now.add(const Duration(minutes: 5))), isTrue);
    });

    test('rejects failed or incomplete responses', () {
      expect(parseYuketangLoginTicket({'code': 50000, 'data': ''}), isNull);
      expect(
        parseYuketangLoginTicket({
          'code': 0,
          'data': {'qrContent': '', 'token': 'x'},
        }),
        isNull,
      );
      expect(parseYuketangLoginTicket('not json'), isNull);
    });
  });

  group('parseYuketangUser', () {
    test('reads user fields and snake_case fallback', () {
      final user = parseYuketangUser({
        'code': 0,
        'data': {
          'name': '同学甲',
          'school': '示例大学',
          'school_number': '20260001',
          'id': 42,
        },
      });

      expect(user, isNotNull);
      expect(user!.name, '同学甲');
      expect(user.school, '示例大学');
      expect(user.schoolNumber, '20260001');
      expect(user.userId, '42');
    });

    test('returns null when unauthenticated', () {
      expect(
        parseYuketangUser({'code': 50000, 'msg': 'UNAUTHENTICATED'}),
        isNull,
      );
    });
  });

  group('parseYuketangCourses', () {
    test('maps course list and skips items without classroom id', () {
      final courses = parseYuketangCourses({
        'errcode': 0,
        'data': {
          'list': [
            {
              'classroom_id': 1001,
              'name': '班级甲',
              'term': 202601,
              'role': 5,
              'course': {'id': 2001, 'name': '课程甲'},
              'teacher': {'name': '教师甲'},
            },
            {
              'classroom_id': 1002,
              'name': '班级乙',
              'role': 6,
              'course': {'id': 2002, 'name': '课程乙'},
            },
            {'name': '缺少课堂 ID'},
          ],
        },
      });

      expect(courses, hasLength(2));
      expect(courses.first.classroomId, '1001');
      expect(courses.first.courseId, '2001');
      expect(courses.first.name, '课程甲');
      expect(courses.first.className, '班级甲');
      expect(courses.first.teacher, '教师甲');
      expect(courses.first.term, 202601);
      expect(courses.first.isAudited, isFalse);
      expect(courses.last.isAudited, isTrue);
    });

    test('falls back to class name and classroom id', () {
      final courses = parseYuketangCourses({
        'data': {
          'list': [
            {'classroom_id': '1003', 'name': '班级丙'},
          ],
        },
      });

      expect(courses.single.name, '班级丙');
      expect(courses.single.courseId, '1003');
    });
  });

  group('isYuketangSessionExpired', () {
    test('detects the four session failure shapes', () {
      expect(isYuketangSessionExpired(statusCode: 401), isTrue);
      expect(isYuketangSessionExpired(statusCode: 403), isTrue);
      expect(isYuketangSessionExpired(body: {'errcode': 401000}), isTrue);
      expect(isYuketangSessionExpired(body: {'code': 50000}), isTrue);
      expect(
        isYuketangSessionExpired(body: {'msg': 'UNAUTHENTICATED', 'data': ''}),
        isTrue,
      );
    });

    test('does not treat ordinary errors as expired', () {
      expect(isYuketangSessionExpired(body: {'errcode': 80019}), isFalse);
      expect(isYuketangSessionExpired(body: {'code': 0}), isFalse);
      expect(isYuketangSessionExpired(statusCode: 500), isFalse);
    });

    test('detects status, error_code and login code variants', () {
      expect(isYuketangSessionExpired(body: {'status': 401000}), isTrue);
      expect(
        isYuketangSessionExpired(
          body: {'success': false, 'error_code': 401000},
        ),
        isTrue,
      );
      expect(isYuketangSessionExpired(body: {'errcode': 401002}), isTrue);
      expect(isYuketangSessionExpired(body: {'code': 10005}), isTrue);
    });
  });

  group('cookies', () {
    test('parses multiple headers, joined cookies and attributes', () {
      final cookies = parseYuketangSetCookies([
        'sessionid=abc123; Path=/; HttpOnly',
        'csrftoken=token1; Path=/, uv_id=2598; Path=/',
      ]);

      expect(cookies['sessionid'], 'abc123');
      expect(cookies['csrftoken'], 'token1');
      expect(cookies['uv_id'], '2598');
      expect(cookies.containsKey('Path'), isFalse);
    });

    test('merges only whitelisted, non-empty cookies', () {
      final merged = mergeYuketangCookies(
        {'sessionid': 'old', 'university_id': '100'},
        {'sessionid': 'new', 'university_id': '', 'unknown': 'x'},
      );

      expect(merged['sessionid'], 'new');
      expect(merged['university_id'], '100');
      expect(merged.containsKey('unknown'), isFalse);
    });
  });

  group('YuketangSnapshot', () {
    test('round-trips through JSON', () {
      final snapshot = YuketangSnapshot(
        user: const YuketangUser(
          name: '同学甲',
          school: '示例大学',
          schoolNumber: '20260001',
          userId: '42',
        ),
        courses: const [
          YuketangCourse(
            classroomId: '1001',
            courseId: '2001',
            name: '课程甲',
            className: '班级甲',
            teacher: '教师甲',
            term: 202601,
            role: 5,
          ),
        ],
        fetchedAt: DateTime(2026, 10, 26, 9),
        liveLessons: const [
          YuketangLiveLesson(
            lessonId: '9001',
            classroomId: '1001',
            courseName: '课程甲',
            className: '班级甲',
            role: 5,
          ),
        ],
        homeworks: [
          YuketangHomework(
            id: '3',
            title: '第三周作业',
            courseName: '课程甲',
            classroomId: '1001',
            leafTypeId: '9101',
            deadline: DateTime(2026, 10, 31, 23, 59),
            status: '未提交',
          ),
        ],
        experiments: [
          YuketangExperiment(
            id: '6',
            title: '实验7',
            courseName: '课程甲',
            classroomId: '1001',
            eventId: '5501',
            deadline: DateTime(2026, 11, 2, 23, 59),
            status: '未提交',
          ),
        ],
        classCoursewares: [
          YuketangCourseware(
            id: '7',
            title: '电路分析-实验7-实验报告',
            courseName: '课程甲',
            createdAt: DateTime(2026, 10, 27, 20, 47),
            coursewareId: '7241493',
            isClassMaterial: true,
            pageCount: 4,
          ),
        ],
      );

      final decoded = YuketangSnapshot.fromJson(snapshot.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.user.name, '同学甲');
      expect(decoded.courses.single.name, '课程甲');
      expect(decoded.courses.single.role, 5);
      expect(decoded.fetchedAt, DateTime(2026, 10, 26, 9));
      expect(decoded.liveLessons.single.courseName, '课程甲');
      expect(decoded.homeworks.single.title, '第三周作业');
      expect(decoded.homeworks.single.status, '未提交');
      expect(decoded.homeworks.single.deadline, DateTime(2026, 10, 31, 23, 59));
      expect(decoded.experiments.single.title, '实验7');
      expect(decoded.experiments.single.eventId, '5501');
      expect(decoded.experiments.single.status, '未提交');
      expect(decoded.classCoursewares.single.title, '电路分析-实验7-实验报告');
      expect(decoded.classCoursewares.single.courseName, '课程甲');
      expect(decoded.classCoursewares.single.pageCount, 4);
      expect(decoded.classCoursewares.single.isUnread, isTrue);
    });

    test('treats missing activity lists as empty for old snapshots', () {
      final decoded = YuketangSnapshot.fromJson({
        'user': {'name': '同学甲'},
        'courses': [],
        'fetchedAt': '2026-10-26T09:00:00.000',
      });

      expect(decoded, isNotNull);
      expect(decoded!.liveLessons, isEmpty);
      expect(decoded.homeworks, isEmpty);
      expect(decoded.experiments, isEmpty);
      expect(decoded.classCoursewares, isEmpty);
    });

    test('filters active homeworks by status and deadline', () {
      final now = DateTime(2026, 10, 29, 12);
      final snapshot = YuketangSnapshot(
        user: const YuketangUser(
          name: '同学甲',
          school: '',
          schoolNumber: '',
          userId: '42',
        ),
        courses: const [],
        fetchedAt: now,
        homeworks: [
          YuketangHomework(
            id: '1',
            title: '未截止',
            courseName: '课程甲',
            classroomId: '1',
            deadline: DateTime(2026, 10, 30),
            status: '未提交',
          ),
          YuketangHomework(
            id: '2',
            title: '已截止',
            courseName: '课程甲',
            classroomId: '1',
            deadline: DateTime(2026, 10, 28),
            status: '未提交',
          ),
          YuketangHomework(
            id: '3',
            title: '已提交',
            courseName: '课程甲',
            classroomId: '1',
            deadline: DateTime(2026, 10, 30),
            status: '已提交',
          ),
        ],
      );

      final active = snapshot.activeHomeworks(now);

      expect(active, hasLength(1));
      expect(active.single.title, '未截止');
    });

    test('hides stale live lessons', () {
      final now = DateTime(2026, 10, 29, 12);
      final snapshot = YuketangSnapshot(
        user: const YuketangUser(
          name: '同学甲',
          school: '',
          schoolNumber: '',
          userId: '42',
        ),
        courses: const [],
        fetchedAt: now.subtract(const Duration(minutes: 30)),
        liveLessons: const [
          YuketangLiveLesson(
            lessonId: '1',
            classroomId: '2',
            courseName: '模拟电子技术A',
          ),
        ],
      );

      expect(
        snapshot.liveLessonsAt(now.subtract(const Duration(minutes: 29))),
        hasLength(1),
      );
      expect(snapshot.liveLessonsAt(now), isEmpty);
    });

    test('returns recent unread class coursewares newest first', () {
      final now = DateTime(2026, 10, 29, 12);
      YuketangCourseware material({
        required String id,
        required String title,
        required DateTime createdAt,
        bool? done,
        int? viewedPages,
        DateTime? endAt,
      }) {
        return YuketangCourseware(
          id: id,
          title: title,
          courseName: '电路分析A1-A2',
          createdAt: createdAt,
          isClassMaterial: true,
          done: done,
          pageCount: 4,
          viewedPages: viewedPages,
          endAt: endAt,
        );
      }

      final snapshot = YuketangSnapshot(
        user: const YuketangUser(
          name: '同学甲',
          school: '',
          schoolNumber: '',
          userId: '42',
        ),
        courses: const [],
        fetchedAt: now,
        classCoursewares: [
          material(
            id: '1',
            title: '实验7',
            createdAt: now.subtract(const Duration(days: 2)),
            done: false,
            viewedPages: 1,
          ),
          material(
            id: '2',
            title: '旧资料',
            createdAt: now.subtract(const Duration(days: 30)),
          ),
          material(
            id: '3',
            title: '已看完',
            createdAt: now.subtract(const Duration(days: 1)),
            done: true,
          ),
          material(
            id: '4',
            title: '已结束',
            createdAt: now.subtract(const Duration(days: 2)),
            endAt: now.subtract(const Duration(days: 1)),
          ),
        ],
      );

      final unread = snapshot.unreadClassCoursewares(now);
      expect(unread, hasLength(1));
      expect(unread.single.title, '实验7');

      expect(
        material(
          id: '3',
          title: '已看完',
          createdAt: now,
          done: true,
        ).statusLabel(now),
        '已看完',
      );
      expect(
        material(
          id: '4',
          title: '已结束',
          createdAt: now,
          endAt: now.subtract(const Duration(hours: 1)),
        ).statusLabel(now),
        '已结束',
      );
      expect(
        material(
          id: '5',
          title: '未开始',
          createdAt: now,
        ).statusLabel(now),
        '未开始',
      );
    });
  });

  group('parseYuketangCourseLog', () {
    test('separates coursewares, homeworks and exams', () {
      final log = parseYuketangCourseLog(_course, {
        'errcode': 0,
        'data': {
          'activities': [
            {
              'id': 1,
              'type': 14,
              'title': '第一次课',
              'create_time': 1793000000000,
            },
            {
              'id': 2,
              'type': 20,
              'title': '期中试卷',
              'content': {
                'score_d': 1794000000000,
                'leaf_type_id': 9001,
                'leaf_id': 8001,
                'sku_id': 7001,
              },
            },
            {
              'id': 3,
              'type': 19,
              'title': '第三周作业',
              'content': {
                'score_d': 1794000000000,
                'leaf_id': 8101,
                'leaf_type_id': 9101,
              },
            },
            {
              'id': 6,
              'type': 100,
              'title': '实验7',
              'event_id': 5501,
              'deadline': 1794500000000,
              'content': {},
            },
            {
              'id': 7,
              'type': 2,
              'courseware_id': 7241493,
              'title': '电路分析-实验7-实验报告',
              'create_time': 1793105254000,
              'count': 4,
              'view': {'depth': 1, 'done': false},
            },
            {
              'id': 4,
              'type': 5,
              'title': '标准版试卷',
              'content': {'score_d': 1795000000000, 'leaf_type_id': 9002},
            },
            {'id': 5, 'type': 5, 'title': '投票', 'content': {}},
          ],
        },
      });

      expect(log.coursewares, hasLength(2));
      final lesson = log.coursewares.firstWhere(
        (item) => !item.isClassMaterial,
      );
      expect(lesson.title, '第一次课');
      expect(
        lesson.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1793000000000),
      );

      final report = log.coursewares.firstWhere(
        (item) => item.isClassMaterial,
      );
      expect(report.title, '电路分析-实验7-实验报告');
      expect(report.courseName, '课程甲');
      expect(report.coursewareId, '7241493');
      expect(report.pageCount, 4);
      expect(report.done, isFalse);
      expect(report.viewedPages, 1);
      expect(report.isStarted, isTrue);
      expect(report.statusLabel(DateTime(2026, 10, 29)), '进行中');
      expect(report.progressLabel, '已看 1/4');

      expect(log.homeworks, hasLength(1));
      expect(log.homeworks.single.title, '第三周作业');
      expect(log.homeworks.single.leafId, '8101');
      expect(log.homeworks.single.leafTypeId, '9101');
      expect(log.homeworks.single.courseName, '课程甲');
      expect(
        log.homeworks.single.deadline,
        DateTime.fromMillisecondsSinceEpoch(1794000000000),
      );

      expect(log.experiments, hasLength(1));
      expect(log.experiments.single.title, '实验7');
      expect(log.experiments.single.eventId, '5501');
      expect(
        log.experiments.single.deadline,
        DateTime.fromMillisecondsSinceEpoch(1794500000000),
      );

      expect(log.exams, hasLength(2));
      expect(log.exams.first.title, '期中试卷');
      expect(log.exams.first.examId, '9001');
      expect(log.exams.first.leafId, '8001');
      expect(log.exams.first.skuId, '7001');
      expect(
        log.exams.first.deadline,
        DateTime.fromMillisecondsSinceEpoch(1794000000000),
      );
      expect(log.exams.last.title, '标准版试卷');
    });

    test('returns empty lists for a malformed response', () {
      final log = parseYuketangCourseLog(_course, {'data': {}});
      expect(log.coursewares, isEmpty);
      expect(log.homeworks, isEmpty);
      expect(log.experiments, isEmpty);
      expect(log.exams, isEmpty);
    });
  });

  group('parseYuketangExperimentReport', () {
    YuketangExperiment experiment() => const YuketangExperiment(
      id: '6',
      title: '实验7',
      courseName: '电路分析A1-A2',
      classroomId: '30932608',
      eventId: '5501',
    );

    test('treats empty data as unsubmitted', () {
      final result = parseYuketangExperimentReport(experiment(), {
        'errcode': 0,
        'data': {},
      });
      expect(result.status, '未提交');
      expect(result.finished, isFalse);
      expect(result.statusError, isNull);
    });

    test('reads graded score', () {
      final result = parseYuketangExperimentReport(experiment(), {
        'data': {'finished': true, 'score': 88},
      });
      expect(result.status, '已批改');
      expect(result.score, 88);
      expect(result.finished, isTrue);
    });

    test('marks finished but ungraded as submitted', () {
      final result = parseYuketangExperimentReport(experiment(), {
        'data': {'finished': true, 'score': -1},
      });
      expect(result.status, '已提交');
      expect(result.score, isNull);
    });
  });

  group('parseYuketangLiveLessons', () {
    test('reads on-lesson classrooms', () {
      final lessons = parseYuketangLiveLessons({
        'code': 0,
        'data': {
          'onLessonClassrooms': [
            {
              'lessonId': 123,
              'classroomId': 33481802,
              'courseId': 808649,
              'courseName': '模拟电子技术A',
              'classroomName': '电科254-5',
              'role': 5,
            },
            {
              'lessonId': 123,
              'classroomId': 33481802,
              'courseName': '重复项',
            },
          ],
        },
      });

      expect(lessons, hasLength(1));
      expect(lessons.single.lessonId, '123');
      expect(lessons.single.classroomId, '33481802');
      expect(lessons.single.courseName, '模拟电子技术A');
      expect(lessons.single.className, '电科254-5');
      expect(lessons.single.role, 5);
    });

    test('returns empty for unauthenticated or malformed responses', () {
      expect(parseYuketangLiveLessons({'code': 50000, 'data': {}}), isEmpty);
      expect(parseYuketangLiveLessons({'data': {}}), isEmpty);
      expect(parseYuketangLiveLessons('not json'), isEmpty);
    });
  });

  group('parseYuketangHomeworkStatus', () {
    YuketangHomework homework() => const YuketangHomework(
      id: '3',
      title: '实验7',
      courseName: '电路分析A1-A2',
      classroomId: '30932608',
      leafTypeId: '9101',
    );

    test('marks unsubmitted homework', () {
      final result = parseYuketangHomeworkStatus(homework(), {
        'data': {
          'answer_count': 0,
          'problems': [
            {
              'content': {'score': 10},
              'user': {},
            },
          ],
        },
      });

      expect(result.status, '未提交');
      expect(result.answeredCount, 0);
      expect(result.problemCount, 1);
      expect(result.statusError, isNull);
    });

    test('marks partial answers as in progress', () {
      final result = parseYuketangHomeworkStatus(homework(), {
        'data': {
          'answer_count': 1,
          'problems': [
            {
              'content': {'score': 10},
              'user': {
                'submit_time': 1793000000,
                'my_answer': {'content': '答案'},
              },
            },
            {
              'content': {'score': 10},
              'user': {},
            },
          ],
        },
      });

      expect(result.status, '进行中');
      expect(result.answeredCount, 1);
      expect(result.problemCount, 2);
    });

    test('marks submitted homework without scores', () {
      final result = parseYuketangHomeworkStatus(homework(), {
        'data': {
          'problems': [
            {
              'content': {'score': 10},
              'user': {'submit_time': 1793000000},
            },
            {
              'content': {'score': 10},
              'user': {'submit_time': 1793000001},
            },
          ],
        },
      });

      expect(result.status, '已提交');
      expect(result.score, isNull);
    });

    test('marks graded homework and sums scores', () {
      final result = parseYuketangHomeworkStatus(homework(), {
        'data': {
          'problems': [
            {
              'content': {'score': 10},
              'user': {'status': 4, 'my_score': 4},
            },
            {
              'content': {'score': 10},
              'user': {'status': 4, 'my_score': 5},
            },
          ],
        },
      });

      expect(result.status, '已批改');
      expect(result.score, 9);
      expect(result.totalScore, 20);
    });

    test('marks empty responses as status errors', () {
      final result = parseYuketangHomeworkStatus(homework(), {'data': {}});
      expect(result.statusError, '作业状态为空');
    });
  });

  group('parseYuketangExamDetail', () {
    test('reads title, counts, times, status and score', () {
      final exam = YuketangExam(
        id: '2',
        title: '期中试卷',
        examId: '9001',
        deadline: DateTime(2026, 10, 20),
      );
      final detail = parseYuketangExamDetail(exam, {
        'data': {
          'title': '期中试卷（A 卷）',
          'problem_count': 10,
          'total_score': 100,
          'start_time': 1793000000000,
          'deadline': 1794000000000,
          'result': {'unfinished_count': 0, 'score': 85},
        },
      });

      expect(detail.title, '期中试卷（A 卷）');
      expect(detail.problemCount, 10);
      expect(detail.totalScore, 100);
      expect(
        detail.startAt,
        DateTime.fromMillisecondsSinceEpoch(1793000000000),
      );
      expect(
        detail.deadline,
        DateTime.fromMillisecondsSinceEpoch(1794000000000),
      );
      expect(detail.status, '已批改');
      expect(detail.score, 85);
      expect(detail.detailError, isNull);
    });

    test('marks in-progress, unstarted and empty details', () {
      final exam = YuketangExam(id: '2', title: '期中试卷', examId: '9001');
      final inProgress = parseYuketangExamDetail(exam, {
        'data': {
          'problem_count': 10,
          'result': {'unfinished_count': 3},
        },
      });
      expect(inProgress.status, '进行中 · 已答 7/10');
      expect(inProgress.score, isNull);

      final unstarted = parseYuketangExamDetail(exam, {
        'data': {'result': null},
      });
      expect(unstarted.status, '未作答');

      final empty = parseYuketangExamDetail(exam, {'data': {}});
      expect(empty.detailError, '试卷详情为空');
    });
  });

  group('parseYuketangTime', () {
    test('parses milliseconds, seconds and strings', () {
      expect(
        parseYuketangTime(1793000000000),
        DateTime.fromMillisecondsSinceEpoch(1793000000000),
      );
      expect(
        parseYuketangTime(1793000000),
        DateTime.fromMillisecondsSinceEpoch(1793000000000),
      );
      expect(
        parseYuketangTime('1793000000000'),
        DateTime.fromMillisecondsSinceEpoch(1793000000000),
      );
      expect(parseYuketangTime('2026-10-26 09:00'), DateTime(2026, 10, 26, 9));
      expect(parseYuketangTime(0), isNull);
      expect(parseYuketangTime(null), isNull);
    });
  });

  group('YuketangPage', () {
    testWidgets('未登录时显示扫码入口', (tester) async {
      await _pumpPage(
        tester,
        YuketangService(store: _FakeYuketangStore(const YuketangStoredState())),
      );

      expect(find.text('登录雨课堂'), findsWidgets);
      expect(find.widgetWithText(FilledButton, '登录雨课堂'), findsOneWidget);
    });

    testWidgets('已登录时显示用户与课程', (tester) async {
      final store = _FakeYuketangStore(
        YuketangStoredState(
          cookies: const {'sessionid': 'fake'},
          snapshot: _snapshot(),
          lastCheckedAt: DateTime(2026, 10, 26, 9),
        ),
      );
      await _pumpPage(tester, YuketangService(store: store));

      expect(find.text('已登录：同学甲'), findsOneWidget);
      expect(find.text('示例大学'), findsOneWidget);
      expect(find.text('课程（1）'), findsOneWidget);
      expect(find.text('课程甲'), findsNWidgets(2));
      expect(find.text('班级甲 · 教师甲'), findsOneWidget);
    });

    testWidgets('显示正在上课、未截止作业和实验', (tester) async {
      final store = _FakeYuketangStore(
        YuketangStoredState(
          cookies: const {'sessionid': 'fake'},
          snapshot: _snapshot(),
          lastCheckedAt: DateTime(2026, 10, 26, 9),
        ),
      );
      await _pumpPage(tester, YuketangService(store: store));

      expect(find.text('活跃'), findsOneWidget);
      expect(find.text('第三周作业'), findsOneWidget);
      expect(find.text('实验7'), findsOneWidget);
      expect(find.text('电路分析-实验7-实验报告'), findsOneWidget);
      expect(find.text('未提交'), findsNWidgets(2));
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('正在上课'), findsNWidgets(2));
    });

    testWidgets('会话失效时提示重新扫码', (tester) async {
      final store = _FakeYuketangStore(
        YuketangStoredState(
          cookies: const {'sessionid': 'expired'},
          snapshot: _snapshot(),
          lastCheckedAt: DateTime(2026, 10, 26, 9),
        ),
      );
      await _pumpPage(tester, _ExpiredYuketangService(store));

      await tester.tap(find.text('刷新课程'));
      await tester.pumpAndSettle();

      expect(find.text('雨课堂登录已过期，请重新扫码'), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
    });

    testWidgets('课程详情页显示课件作业实验试卷四栏', (tester) async {
      final service = _CourseLogYuketangService(_courseLog());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: YuketangCoursePage(service: service, course: _course),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('课件 2'), findsOneWidget);
      expect(find.text('作业 1'), findsOneWidget);
      expect(find.text('实验 1'), findsOneWidget);
      expect(find.text('试卷 1'), findsOneWidget);
      expect(find.text('课件（2）'), findsOneWidget);
      expect(find.text('第一次课'), findsOneWidget);
      expect(find.text('电路分析-实验7-实验报告'), findsOneWidget);
      expect(find.text('进行中'), findsOneWidget);
      expect(find.textContaining('已看 1/4'), findsOneWidget);
      expect(find.textContaining('班级课件'), findsOneWidget);

      await tester.tap(find.text('作业 1'));
      await tester.pumpAndSettle();

      expect(find.text('第三周作业'), findsOneWidget);
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('已答 1/2'), findsOneWidget);

      await tester.tap(find.text('实验 1'));
      await tester.pumpAndSettle();

      expect(find.text('实验7'), findsOneWidget);
      expect(find.text('未提交'), findsOneWidget);

      await tester.tap(find.text('试卷 1'));
      await tester.pumpAndSettle();

      expect(find.text('期中试卷'), findsOneWidget);
      expect(find.text('题数 10 · 总分 100 · 得分 85'), findsOneWidget);
      expect(find.text('已批改'), findsOneWidget);
    });

    testWidgets('点击课程进入课件作业试卷详情', (tester) async {
      final store = _FakeYuketangStore(
        YuketangStoredState(
          cookies: const {'sessionid': 'fake'},
          snapshot: _snapshot(),
          lastCheckedAt: DateTime(2026, 10, 26, 9),
        ),
      );
      final service = _CourseLogYuketangService(_courseLog(), store: store);
      await _pumpPage(tester, service);

      await tester.ensureVisible(find.text('班级甲 · 教师甲'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('班级甲 · 教师甲'));
      await tester.pumpAndSettle();

      expect(find.text('课件 2'), findsOneWidget);
      expect(find.text('作业 1'), findsOneWidget);
      expect(find.text('实验 1'), findsOneWidget);
      expect(find.text('试卷 1'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(WidgetTester tester, YuketangService service) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: YuketangPage(service: service),
    ),
  );
  await tester.pumpAndSettle();
}

const YuketangCourse _course = YuketangCourse(
  classroomId: '1001',
  courseId: '2001',
  name: '课程甲',
  className: '班级甲',
  teacher: '教师甲',
  term: 202601,
  role: 5,
);

YuketangCourseLog _courseLog() {
  return YuketangCourseLog(
    course: _course,
    coursewares: [
      YuketangCourseware(
        id: '1',
        title: '第一次课',
        courseName: '课程甲',
        createdAt: DateTime(2026, 10, 20, 8),
      ),
      YuketangCourseware(
        id: '7',
        title: '电路分析-实验7-实验报告',
        courseName: '课程甲',
        createdAt: DateTime(2026, 10, 27, 20, 47),
        coursewareId: '7241493',
        isClassMaterial: true,
        done: false,
        pageCount: 4,
        viewedPages: 1,
      ),
    ],
    homeworks: [
      YuketangHomework(
        id: '3',
        title: '第三周作业',
        courseName: '课程甲',
        classroomId: '1001',
        leafId: '8101',
        leafTypeId: '9101',
        deadline: DateTime(2026, 10, 31, 23, 59),
        status: '进行中',
        answeredCount: 1,
        problemCount: 2,
      ),
    ],
    experiments: [
      YuketangExperiment(
        id: '6',
        title: '实验7',
        courseName: '课程甲',
        classroomId: '1001',
        eventId: '5501',
        deadline: DateTime(2026, 11, 2, 23, 59),
        status: '未提交',
      ),
    ],
    exams: [
      YuketangExam(
        id: '2',
        title: '期中试卷',
        examId: '9001',
        deadline: DateTime(2026, 10, 30, 23, 59),
        problemCount: 10,
        totalScore: 100,
        startAt: DateTime(2026, 10, 29, 8),
        status: '已批改',
        score: 85,
      ),
    ],
  );
}

YuketangSnapshot _snapshot() {
  return YuketangSnapshot(
    user: const YuketangUser(
      name: '同学甲',
      school: '示例大学',
      schoolNumber: '20260001',
      userId: '42',
    ),
    courses: const [
      YuketangCourse(
        classroomId: '1001',
        courseId: '2001',
        name: '课程甲',
        className: '班级甲',
        teacher: '教师甲',
        term: 202601,
        role: 5,
      ),
    ],
    fetchedAt: DateTime.now(),
    liveLessons: const [
      YuketangLiveLesson(
        lessonId: '9001',
        classroomId: '1001',
        courseName: '课程甲',
        className: '班级甲',
        role: 5,
      ),
    ],
    homeworks: [
      YuketangHomework(
        id: '3',
        title: '第三周作业',
        courseName: '课程甲',
        classroomId: '1001',
        leafTypeId: '9101',
        deadline: DateTime.now().add(const Duration(days: 2)),
        status: '未提交',
      ),
    ],
    experiments: [
      YuketangExperiment(
        id: '6',
        title: '实验7',
        courseName: '课程甲',
        classroomId: '1001',
        eventId: '5501',
        deadline: DateTime.now().add(const Duration(days: 4)),
        status: '未提交',
      ),
    ],
    classCoursewares: [
      YuketangCourseware(
        id: '7',
        title: '电路分析-实验7-实验报告',
        courseName: '课程甲',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        coursewareId: '7241493',
        isClassMaterial: true,
        done: false,
        pageCount: 4,
        viewedPages: 1,
      ),
    ],
  );
}

class _FakeYuketangStore extends YuketangSessionStore {
  _FakeYuketangStore(this.state);

  final YuketangStoredState state;

  @override
  Future<YuketangStoredState> load() async => state;

  @override
  Future<void> saveCookies(Map<String, String> cookies) async {}

  @override
  Future<void> saveSnapshot(YuketangSnapshot snapshot) async {}

  @override
  Future<void> saveLastChecked(DateTime at) async {}

  @override
  Future<void> clear() async {}
}

class _ExpiredYuketangService extends YuketangService {
  _ExpiredYuketangService(YuketangSessionStore store) : super(store: store);

  @override
  Future<YuketangSnapshot> refresh() async {
    throw const YuketangException(
      '雨课堂登录已过期，请重新扫码',
      kind: YuketangFailureKind.sessionExpired,
    );
  }
}

class _CourseLogYuketangService extends YuketangService {
  _CourseLogYuketangService(this.log, {YuketangSessionStore? store})
    : super(store: store ?? _FakeYuketangStore(const YuketangStoredState()));

  final YuketangCourseLog log;

  @override
  Future<YuketangCourseLog> fetchCourseLog(YuketangCourse course) async => log;
}
