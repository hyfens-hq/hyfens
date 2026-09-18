import 'dart:io';

Future<void> main() async {
  final host = Platform.environment['HYFENS_HEALTHCHECK_HOST'] ?? '127.0.0.1';
  final port =
      int.tryParse(Platform.environment['HYFENS_PORT'] ?? '18081') ?? 18081;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.get(host, port, '/readyz');
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      exitCode = 1;
    }
  } on Object {
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}
