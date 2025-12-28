import 'dart:async';
import 'dart:io';

/// Desktop OAuth implementation using local HTTP server
/// This file is only imported on platforms that support dart:io

const int localPort = 9728;

bool isDesktopPlatform() {
  return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
}

HttpServer? _localServer;
Completer<Map<String, String>>? _authCompleter;

/// Start local server and wait for OAuth callback
Future<Map<String, String>> waitForOAuthCallback() async {
  try {
    // Start local server
    await _stopLocalServer();
    _localServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      localPort,
    );
    _authCompleter = Completer<Map<String, String>>();

    _localServer!.listen((request) async {
      if (request.uri.path == '/callback') {
        final params = request.uri.queryParameters;

        // Send a nice HTML response to the browser
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_getSuccessHtml(params.containsKey('error')));
        await request.response.close();

        // Complete the auth flow
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.complete(Map<String, String>.from(params));
        }
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        await request.response.close();
      }
    });

    // Wait for callback with timeout
    final result = await _authCompleter!.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => {'error': 'Authentication timed out'},
    );

    await _stopLocalServer();
    return result;
  } catch (e) {
    await _stopLocalServer();
    return {'error': e.toString()};
  }
}

Future<void> _stopLocalServer() async {
  await _localServer?.close(force: true);
  _localServer = null;
  _authCompleter = null;
}

String _getSuccessHtml(bool isError) {
  final status = isError ? 'Error' : 'Success';
  final message = isError
      ? 'Authentication failed. Please try again.'
      : 'Successfully signed in! You can close this window and return to the app.';
  final icon = isError ? '❌' : '✅';
  final color = isError ? '#ef4444' : '#22c55e';

  return '''
<!DOCTYPE html>
<html>
<head>
  <title>KioKuu - $status</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a1a 0%, #0a0a0a 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      color: white;
    }
    .container {
      text-align: center;
      padding: 3rem;
      background: rgba(255, 255, 255, 0.05);
      border-radius: 24px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      max-width: 400px;
    }
    .icon {
      font-size: 4rem;
      margin-bottom: 1.5rem;
    }
    h1 {
      font-size: 1.5rem;
      margin-bottom: 1rem;
      color: $color;
    }
    p {
      color: rgba(255, 255, 255, 0.7);
      line-height: 1.6;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">$icon</div>
    <h1>$status</h1>
    <p>$message</p>
  </div>
</body>
</html>
''';
}
