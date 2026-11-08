import 'dart:convert';

// cyanmoon 为新的分享方案名；kazumi 为主站生态的历史方案名，解析保持兼容。
final RegExp _ruleLinkSchemePattern = RegExp(
  r'(?:cyanmoon|kazumi):(?://)?',
  caseSensitive: false,
);

Iterable<({String scheme, String rawPayload})> findRuleLinkSegments(
  String input,
) sync* {
  final matches = _ruleLinkSchemePattern.allMatches(input).toList();
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final end = index + 1 < matches.length
        ? matches[index + 1].start
        : input.length;
    yield (
      scheme: match.group(0)!,
      rawPayload: input.substring(match.end, end),
    );
  }
}

String jsonToRuleLink(String jsonStr) {
  final base64Str = base64Encode(utf8.encode(jsonStr));
  return 'cyanmoon://$base64Str';
}

String ruleLinkToJson(String ruleLinkStr) {
  final input = ruleLinkStr.trim();
  final schemeMatch = _ruleLinkSchemePattern.matchAsPrefix(input);
  if (schemeMatch == null) {
    throw const FormatException('Invalid rule link');
  }

  var payload = input.substring(schemeMatch.end);
  try {
    payload = Uri.decodeComponent(payload);
  } on FormatException {
    throw const FormatException('Invalid encoding in rule link');
  } on ArgumentError {
    throw const FormatException('Invalid encoding in rule link');
  }
  payload = payload.replaceAll(RegExp(r'\s'), '');
  if (payload.isEmpty) {
    throw const FormatException('Kazumi rule link is empty');
  }

  // Accept both standard and URL-safe Base64, with or without padding. Links
  // are frequently wrapped by chat applications or percent-encoded by URI
  // handlers before they reach the import dialog.
  final normalized = base64.normalize(
    payload.replaceAll('-', '+').replaceAll('_', '/'),
  );
  try {
    return utf8.decode(base64.decode(normalized));
  } on FormatException {
    throw const FormatException('Invalid rule link payload');
  }
}
