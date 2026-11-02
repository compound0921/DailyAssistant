import 'dart:convert';

import 'package:daily_assistant/xuexitong/xuexitong_service.dart';
import 'package:daily_assistant/xuexitong/xuexitong_session_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_chaoxing/flutter_chaoxing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cacheKey = 'xuexitong_task_detail_cache_v2';
const _url = 'https://mooc1.chaoxing.com/work/phone/task-work?id=sample';

class _MemoryStore implements SecureKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _CourseApi extends ChaoxingApiService {
  List<ChaoxingCourseTask> work = [
    const ChaoxingCourseTask(
      title: '示例作业',
      url: _url,
      type: 'work',
      statusText: 'uncommitted',
    ),
  ];
  List<ChaoxingCourseTask> exams = [];

  @override
  Future<List<ChaoxingCourseTask>> fetchWorkList(
    ChaoxingSession session, {
    required String courseId,
    required String classId,
  }) async => work;

  @override
  Future<List<ChaoxingCourseTask>> fetchExamList(
    ChaoxingSession session, {
    required String courseId,
    required String classId,
  }) async => exams;
}

class _Harness {
  final api = _CourseApi();
  dynamic feed = {'result': 1, 'data': 'invalid list'};
  String detail = '<html><body>截止时间：2099-11-20 23:59</body></html>';
  bool failDetail = false;
  int detailRequests = 0;
  late XuexitongService service;

  Future<void> init() async {
    final store = XuexitongSessionStore(store: _MemoryStore());
    await store.saveSession(
      ChaoxingSession(
        cookieHeader: 'test_session=synthetic',
        puid: 'sample-user',
        uid: 'sample-user',
        fid: 'sample-school',
        savedAt: DateTime.now(),
      ),
    );
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          dynamic body;
          if (request.path.contains('/gas/taskmsg')) {
            body = feed;
          } else if (request.path.contains('/mycourse/backclazzdata')) {
            body = {
              'result': 1,
              'channelList': [
                {
                  'content': {
                    'id': 'sample-class',
                    'course': {
                      'data': [
                        {'id': 'sample-course', 'name': '示例课程'},
                      ],
                    },
                  },
                },
              ],
            };
          } else if (request.path.contains('/taskactivelist')) {
            body = {'status': 1, 'activeList': []};
          } else {
            detailRequests++;
            if (failDetail) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }
            handler.resolve(
              Response(requestOptions: request, statusCode: 200, data: detail),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: jsonEncode(body),
            ),
          );
        },
      ),
    );
    service = XuexitongService(store: store, api: api, dio: dio);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness harness;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    harness = _Harness();
    await harness.init();
  });

  test(
    'empty bold status uses body label or stays unknown, never pending',
    () async {
      harness.api.work = [
        const ChaoxingCourseTask(
          title: '示例作业',
          url: _url,
          type: 'work',
          detail: '示例作业 已提交 发布时间 2026-10-20',
        ),
        const ChaoxingCourseTask(
          title: '状态缺失任务',
          url: 'https://mooc1.chaoxing.com/work/unknown',
          type: 'work',
        ),
      ];
      final result = await harness.service.fetchTasks();
      expect(result.tasks.map((task) => task.status), [1, -2]);
      expect(harness.detailRequests, 0);
      expect(result.warnings.join(), contains('提交状态未知'));
    },
  );

  test(
    'closed tasks without due times retain cleanup identity without details',
    () async {
      harness.api.work = [
        const ChaoxingCourseTask(
          title: '旧作业',
          url: _url,
          type: 'work',
          statusText: '已过期',
        ),
      ];
      harness.api.exams = [
        const ChaoxingCourseTask(
          title: '旧考试',
          url: 'https://mooc1.chaoxing.com/exam/closed',
          type: 'exam',
          statusText: '已结束',
        ),
      ];
      final result = await harness.service.fetchTasks();
      expect(result.tasks, hasLength(2));
      expect(result.tasks.every((task) => task.status == -1), isTrue);
      expect(harness.detailRequests, 0);
    },
  );

  test(
    'malformed feed falls back and preserves pending exam with raw status 4',
    () async {
      harness.api.exams = [
        const ChaoxingCourseTask(
          title: '示例考试',
          url: 'https://mooc1.chaoxing.com/exam/sample',
          type: 'exam',
          statusText: '未完成',
          status: 4,
        ),
      ];
      final result = await harness.service.fetchTasks();
      expect(result.usedFallback, isTrue);
      expect(result.warnings.join(), contains('任务列表结构异常'));
      expect(result.tasks, hasLength(2));
      expect(result.tasks.every((task) => task.status == 0), isTrue);
      expect(harness.detailRequests, 2);
    },
  );

  test(
    'stale homework time survives failure without refreshing cache',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final oldTime = DateTime.now().subtract(const Duration(hours: 1));
      final oldDue = DateTime(2099, 11, 19, 23, 59);
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          _url: {
            'title': '示例作业',
            'status': 'uncommitted',
            'dueAt': oldDue.toIso8601String(),
            'fetchedAt': oldTime.toIso8601String(),
          },
        }),
      );
      harness.failDetail = true;
      final failed = await harness.service.fetchTasks();
      expect(failed.tasks.single.endTime, oldDue);
      expect(failed.warnings.join(), contains('详情读取失败'));
      expect(
        (jsonDecode(prefs.getString(_cacheKey)!) as Map)[_url]['fetchedAt'],
        oldTime.toIso8601String(),
      );

      harness.failDetail = false;
      final recovered = await harness.service.fetchTasks();
      expect(recovered.tasks.single.endTime, DateTime(2099, 11, 20, 23, 59));
      await harness.service.fetchTasks();
      expect(harness.detailRequests, 2); // 成功后才复用短期缓存。
    },
  );

  test(
    'failed detail is retried, explicit no-deadline result may be cached',
    () async {
      harness.failDetail = true;
      final failed = await harness.service.fetchTasks();
      expect(failed.tasks, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(_cacheKey)!), isEmpty);

      harness.failDetail = false;
      harness.detail = '<html><body>示例作业 无截止时间</body></html>';
      final recovered = await harness.service.fetchTasks();
      expect(recovered.tasks.single.endTime.millisecondsSinceEpoch, 0);
      await harness.service.fetchTasks();
      expect(harness.detailRequests, 2);
    },
  );

  test('full feed at safety limit reports possibly incomplete sync', () async {
    harness.feed = {
      'result': 1,
      'data': List.generate(
        50,
        (i) => {
          'id': 'sample-$i',
          'title': '示例任务 $i',
          'type': 'work',
          'status': 0,
        },
      ),
    };
    final result = await harness.service.fetchTasks();
    expect(result.tasks, hasLength(300));
    expect(result.warnings.join(), contains('300 条上限'));
    expect(result.usedFallback, isFalse);
  });
}
