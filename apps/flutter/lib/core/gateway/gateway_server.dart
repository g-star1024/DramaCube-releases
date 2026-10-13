/// 本地网关（Dart 重写，对齐 macOS 版 Swift HongguoGatewayCore）。
///
/// 端点：
/// - GET /api/health — 健康检查
/// - GET /api/tvbox/sites — TVBox 站点列表
/// - GET /api/tvbox/list?site=&pg=&t= — 站点列表（分类/分页）
/// - GET /api/tvbox/detail?site=&id= — 剧集详情
/// - GET /api/tvbox/search?site=&wd= — 站点搜索
/// - GET /api/tvbox/import?url= — 订阅导入
/// - GET /api/tvbox/test?site= — 连通性测试（首页+搜索双测）
/// - GET /api/live/sources / GET /api/live/channels?source= — 直播源/频道
/// - GET /api/live/stream?url= — m3u8 代理（重写分片走本网关，锁大陆 IP 绕 403）
/// - GET /api/play?url= — 直链代理（剥离 Referer + Range 透传）
/// - GET /api/stream/sid/vid — 无预置直链即时解析
/// - GET /api/nas/list / GET /api/nas/scan — NAS 资源库（WebDAV/挂载）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'tvbox_engine.dart';

class GatewayServer {
  HttpServer? _server;
  final int port;
  final String host;
  final TVBoxEngine _tvbox = TVBoxEngine();

  GatewayServer({this.port = 8787, this.host = '127.0.0.1'});

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final router = Router()
      ..get('/api/health', _health)
      ..get('/api/tvbox/sites', _tvboxSites)
      ..get('/api/tvbox/list', _tvboxList)
      ..get('/api/tvbox/detail', _tvboxDetail)
      ..get('/api/tvbox/search', _tvboxSearch)
      ..get('/api/tvbox/import', _tvboxImport)
      ..get('/api/tvbox/test', _tvboxTest)
      ..get('/api/live/sources', _liveSources)
      ..get('/api/live/channels', _liveChannels)
      ..get('/api/live/stream', _liveStream)
      ..get('/api/play', _play)
      ..get('/api/stream/<sid>/<vid>', _stream)
      ..get('/api/nas/list', _nasList)
      ..get('/api/nas/scan', _nasScan);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_cors)
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, host, port);
    // 网关启动日志（release 模式可接 logger 包，当前保持简单）
    assert(() {
      // ignore: avoid_print
      print('[gateway] listening on $host:$port');
      return true;
    }());
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Middleware get _cors => createMiddleware(
        responseHandler: (resp) => resp.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': '*',
        }),
      );

  Response _health(Request req) => Response.ok(jsonEncode({'ok': true, 'version': '2.7.6'}));

  // MARK: TVBox

  Future<Response> _tvboxSites(Request req) async {
    final sites = await _tvbox.sites();
    return _json(sites);
  }

  Future<Response> _tvboxList(Request req) async {
    final site = req.url.queryParameters['site'] ?? '';
    final pg = int.tryParse(req.url.queryParameters['pg'] ?? '1') ?? 1;
    final t = req.url.queryParameters['t'];
    final list = await _tvbox.list(site: site, page: pg, typeId: t);
    return _json(list);
  }

  Future<Response> _tvboxDetail(Request req) async {
    final site = req.url.queryParameters['site'] ?? '';
    final id = req.url.queryParameters['id'] ?? '';
    final detail = await _tvbox.detail(site: site, vodId: id);
    return _json(detail);
  }

  Future<Response> _tvboxSearch(Request req) async {
    final site = req.url.queryParameters['site'] ?? '';
    final wd = req.url.queryParameters['wd'] ?? '';
    final list = await _tvbox.search(site: site, query: wd);
    return _json(list);
  }

  Future<Response> _tvboxImport(Request req) async {
    final url = req.url.queryParameters['url'] ?? '';
    final result = await _tvbox.importSubscription(url);
    return _json(result);
  }

  Future<Response> _tvboxTest(Request req) async {
    final site = req.url.queryParameters['site'] ?? '';
    final result = await _tvbox.test(site);
    return _json(result);
  }

  // MARK: 直播（占位，M2 实现）

  Future<Response> _liveSources(Request req) async => _json([]);
  Future<Response> _liveChannels(Request req) async => _json([]);
  Future<Response> _liveStream(Request req) async => Response.notFound('not implemented');

  // MARK: 代理（占位，M2 实现）

  Future<Response> _play(Request req) async => Response.notFound('not implemented');
  Future<Response> _stream(Request req, String sid, String vid) async => Response.notFound('not implemented');

  // MARK: NAS（占位，M2 实现）

  Future<Response> _nasList(Request req) async => _json([]);
  Future<Response> _nasScan(Request req) async => _json([]);

  // MARK: 工具

  Response _json(Object? data) => Response.ok(
        jsonEncode(data),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
}
