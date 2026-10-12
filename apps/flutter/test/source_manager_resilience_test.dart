import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramacube/core/models/models.dart';
import 'package:dramacube/features/catalog/source_manager.dart';

/// 源管理器韧性测试：复现 v2.7.0「播放全部失败」根因（currentSource 空键毒丸），
/// 验证修复后任何路径下当前源永不为空（有站点时）。

const _s1 = TVBoxSite(key: 's1', name: '源一', api: 'http://127.0.0.1:1/api.php');
const _s2 = TVBoxSite(key: 's2', name: '源二', api: 'http://127.0.0.1:1/api.php');

String _sitesJson(List<TVBoxSite> sites) => jsonEncode(
    sites.map((s) => {'key': s.key, 'name': s.name, 'api': s.api}).toList());

String _healthJson(Map<String, bool> okMap, {int at = 1700000000000}) => jsonEncode(okMap
    .map((k, ok) => MapEntry(k, {'ok': ok, 'ms': ok ? 100 : null, 'at': at})));

/// 假探测适配器：端口 1 → 连接失败（模拟失效源）；其余 → 200（模拟可用源）。
/// 避免依赖真实网络，也绕开 TestWidgetsFlutterBinding 对 HttpClient 的劫持。
class _FakeProbeAdapter implements HttpClientAdapter {
  const _FakeProbeAdapter();

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.port == 1) {
      throw DioException(requestOptions: options, error: 'connection refused');
    }
    return ResponseBody.fromString(
      '{"list":[],"class":[],"total":0}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Dio _fakeProbeDio() => Dio(BaseOptions())..httpClientAdapter = const _FakeProbeAdapter();

/// 等待 SourceManager 构造函数里的 _load() 异步完成。
Future<void> _pump() => Future.delayed(const Duration(milliseconds: 120));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('空键毒丸自愈：_load 把持久化的空 currentSource 恢复为第一个启用源', () async {
    SharedPreferences.setMockInitialValues({
      'src.sites': _sitesJson(const [_s1, _s2]),
      'src.current': '', // 旧版本 bug 持久化下来的空键
      'src.disabled': <String>[],
      'src.health': _healthJson({'s1': false, 's2': false}), // 全失败 → 不触发自动探测
      'src.pinned': true,
    });
    final m = SourceManager();
    await _pump();
    expect(m.state.currentSource, isNotEmpty, reason: '空键必须被自愈，否则全站无可播放内容');
    expect(m.state.currentSource, 's1');
  });

  test('禁用当前源且探测全失败时不留空键（v2.7.0 线上 bug 复现场景）', () async {
    SharedPreferences.setMockInitialValues({
      'src.sites': _sitesJson(const [_s1, _s2]),
      'src.current': 's1',
      'src.disabled': <String>[],
      'src.health': _healthJson({'s1': false, 's2': false}),
      'src.pinned': true, // 用户手动指定过 s1
    });
    final m = SourceManager();
    await _pump();
    expect(m.state.currentSource, 's1');
    // 用户在设置里禁用了当前源 s1，且当时无任何探测可用的源（fastestSite == null）。
    m.toggleDisabled('s1');
    await _pump();
    expect(m.state.currentSource, isNotEmpty);
    expect(m.state.currentSource, 's2', reason: '应切到第一个仍启用的源');
  });

  test('有效的 pinned 当前源不被禁用其他源的动作动摇', () async {
    SharedPreferences.setMockInitialValues({
      'src.sites': _sitesJson(const [_s1, _s2]),
      'src.current': 's2',
      'src.disabled': <String>[],
      'src.health': _healthJson({'s1': true, 's2': true}),
      'src.pinned': true,
    });
    final m = SourceManager();
    await _pump();
    m.toggleDisabled('s1'); // 禁用的是非当前源
    await _pump();
    expect(m.state.currentSource, 's2');
    expect(m.state.disabled, contains('s1'));
  });

  test('autoSelectFastest：空当前源 + 探测全失败 → 回退第一个启用源', () async {
    SharedPreferences.setMockInitialValues({});
    final m = SourceManager();
    await _pump();
    // 直接构造「空当前源 + 全失败」状态（复现毒丸驻留态）。
    final failedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    m.state = SourceState(
      sites: const [_s1, _s2],
      currentSource: '',
      pinned: false,
      health: {
        's1': SiteHealth(ok: false, checkedAt: failedAt),
        's2': SiteHealth(ok: false, checkedAt: failedAt),
      },
    );
    m.autoSelectFastest();
    await _pump();
    expect(m.state.currentSource, isNotEmpty);
    expect(m.state.currentSource, 's1');
  });

  test('testAll 真实探测闭环：一源失效一源可用 → 失效禁用 + 切到可用源', () async {
    final bad = const TVBoxSite(key: 'bad', name: '坏源', api: 'http://127.0.0.1:1/api.php');
    final good = const TVBoxSite(key: 'good', name: '好源', api: 'http://127.0.0.1:2/api.php');

    SharedPreferences.setMockInitialValues({});
    final m = SourceManager(probeDio: _fakeProbeDio());
    await _pump();
    m.state = SourceState(sites: [bad, good], currentSource: 'bad', pinned: false);
    await m.testAll();

    expect(m.state.testingAll, false);
    expect(m.state.disabled, contains('bad'), reason: '失效源应自动禁用');
    expect(m.state.disabled, isNot(contains('good')));
    expect(m.state.currentSource, 'good', reason: '未 pin 定时应切到最快可用源');
    expect(m.state.currentSource, isNotEmpty);
  });

  test('testAll 全部失效：源全部保留（防无源）+ 当前源非空', () async {
    SharedPreferences.setMockInitialValues({});
    final m = SourceManager(probeDio: _fakeProbeDio());
    await _pump();
    m.state = SourceState(
      sites: const [_s1, _s2],
      currentSource: 's1',
      pinned: true,
    );
    await m.testAll(); // 两个源都指向端口 1，必然失败
    expect(m.state.disabled, isEmpty, reason: '全部失效时应保留全部源，避免无可用源');
    expect(m.state.currentSource, isNotEmpty);
    expect(m.state.currentSource, 's1');
  });
}
