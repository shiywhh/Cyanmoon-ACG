// DanDanPlay API credentials for the client signature flow.
// Release/PR CI injects them via --dart-define=DANDANAPI_APPID / DANDANAPI_KEY.
const Map<String, String> dandanCredentials = {
  'id': String.fromEnvironment('DANDANAPI_APPID'),
  'value': String.fromEnvironment('DANDANAPI_KEY'),
};

bool get hasDandanCredentials =>
    dandanCredentials['id']!.trim().isNotEmpty &&
    dandanCredentials['value']!.trim().isNotEmpty;

class DandanConfigurationException implements Exception {
  const DandanConfigurationException();
  @override
  String toString() => '弹弹play应用凭据未配置';
}
