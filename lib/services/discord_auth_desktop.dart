import 'dart:async';
import 'dart:io';
import '../config/app_config.dart';

bool isDesktopPlatform() =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

int get localPort => AppConfig.desktopOAuthPort;

Future<Map<String, dynamic>> waitForOAuthCallback() async {
  final completer = Completer<Map<String, dynamic>>();
  HttpServer? server;

  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, localPort);

    Timer(const Duration(minutes: 5), () {
      if (!completer.isCompleted) {
        completer.complete({'error': 'Timeout'});
        server?.close();
      }
    });

    await for (HttpRequest request in server) {
      if (request.uri.path == '/callback') {
        final params = request.uri.queryParameters;

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_successHtml(params.containsKey('error')));
        await request.response.close();

        if (params.containsKey('error')) {
          completer.complete({'error': params['error']});
        } else {
          completer.complete({
            'token': params['token'],
            'user_id': params['user_id'],
            'username': params['username'],
            'photo_url': params['photo_url'],
          });
        }
        break;
      }
    }
  } catch (e) {
    if (!completer.isCompleted) {
      completer.complete({'error': e.toString()});
    }
  } finally {
    await server?.close();
  }

  return completer.future;
}

String _successHtml(bool isError) =>
    '''
<!DOCTYPE html>
<html>
<head><title>KioKuu</title>
<style>
body{font-family:system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#1a1a2e;color:#fff}
.box{text-align:center;padding:40px;background:rgba(255,255,255,0.1);border-radius:16px}
h1{color:${isError ? '#f44' : '#4c5'}}
</style></head>
<body><div class="box">
<h1>${isError ? '❌ Error' : '✅ Success!'}</h1>
<p>${isError ? 'Authentication failed.' : 'You can close this window.'}</p>
</div>
<script>setTimeout(()=>window.close(),2000)</script>
</body></html>
''';
