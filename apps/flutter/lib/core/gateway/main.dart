/// 网关独立入口（Docker 部署用，dart compile exe 编译为 AOT 可执行文件）。
library;

import 'gateway_server.dart';

Future<void> main(List<String> args) async {
  final port = int.tryParse(
        const String.fromEnvironment('GATEWAY_PORT', defaultValue: '8787'),
      ) ??
      8787;
  final gateway = GatewayServer(port: port, host: '0.0.0.0');
  await gateway.start();
  // ignore: avoid_print
  print('[dramacube-gateway] listening on 0.0.0.0:$port');
}
