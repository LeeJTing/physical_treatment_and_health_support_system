import 'dart:io';

/// Cross-repository contract tests support the server's separate checkout.
File serverSource(String relativePath) {
  final configured = Platform.environment['AI_SERVER_ROOT'];
  for (final root in [
    ?configured,
    'ai_server',
    '../fyp-fastapi/ai_server',
  ]) {
    final file = File('$root/$relativePath');
    if (file.existsSync()) return file;
  }
  throw StateError(
    'Set AI_SERVER_ROOT to the fyp-fastapi/ai_server checkout to run server contract checks.',
  );
}
