/// Small settings kept on this phone only (not in Supabase), e.g. the address of the AI server
/// on the team's laptop, which changes with the Wi-Fi network or the tunnel.
abstract class LocalSettings {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// In memory, for tests and desktop runs.
class MemoryLocalSettings implements LocalSettings {
  final Map<String, String> values;
  MemoryLocalSettings([Map<String, String>? initial]) : values = {...?initial};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}
