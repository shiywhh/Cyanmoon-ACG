// Bangumi mirror API credentials for the search signature flow.
// Release/PR CI injects them via --dart-define=CYANMOON_APPID / CYANMOON_KEY.
const Map<String, String> bangumiMirrorCredentials = {
  'id': String.fromEnvironment('CYANMOON_APPID'),
  'value': String.fromEnvironment('CYANMOON_KEY'),
};
