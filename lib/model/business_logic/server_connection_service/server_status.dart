/// What GET /health of the AI server answered.
class ServerStatus {
  final String address;
  final String version;

  /// Round trip of the check, so a slow tunnel or a weak Wi-Fi shows up before a meal photo times out.
  final int latencyMs;

  /// AI parts of the server and their state: "ready", "loading" (models still being loaded after
  /// the server started) or "missing" (e.g. the food encoder file was not built). Empty for an older
  /// server that does not report them.
  final Map<String, String> modules;

  const ServerStatus({
    required this.address,
    required this.version,
    required this.latencyMs,
    this.modules = const {},
  });

  factory ServerStatus.fromHealth(String address, Map<String, dynamic> j, int latencyMs) => ServerStatus(
    address: address,
    version: (j['version'] ?? '').toString(),
    latencyMs: latencyMs,
    modules: {
      for (final e in ((j['modules'] as Map?) ?? const {}).entries) e.key.toString(): e.value.toString(),
    },
  );

  bool get allReady => modules.values.every((v) => v == 'ready');

  /// Readable names for the modules the server reports.
  static const labels = {
    'food_recognition': 'Food recognition',
    'diet_planner': 'Diet planner',
    'analysis': 'Health analysis',
    'recommend': 'Treatment plans',
    'chat': 'Chatbot',
    'pose': 'Posture check',
  };
}
