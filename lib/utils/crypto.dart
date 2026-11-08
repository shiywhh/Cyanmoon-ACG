import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cyanmoon_acg/utils/bangumi_mirror_credentials.dart';
import 'package:cyanmoon_acg/utils/dandan_credentials.dart';

String generateDandanSignature(String path, int timestamp) {
  final id = dandanCredentials['id']!;
  final value = dandanCredentials['value']!;
  final data = id + timestamp.toString() + path + value;
  final bytes = utf8.encode(data);
  final digest = sha256.convert(bytes);
  return base64Encode(digest.bytes);
}

String generateBangumiMirrorSearchSignature({
  required String method,
  required String path,
  required String body,
  required int timestamp,
}) {
  final id = bangumiMirrorCredentials['id']!;
  final value = bangumiMirrorCredentials['value']!;
  final bodyDigest = sha256.convert(utf8.encode(body)).toString();
  final data = id + timestamp.toString() + method + path + bodyDigest + value;
  final digest = sha256.convert(utf8.encode(data));
  return base64Encode(digest.bytes);
}

Future<String> calculateFileHash(File file) async {
  // 流式分块哈希：更新包可达数百 MB，整文件 readAsBytes 会让内存瞬时翻倍，
  // 低内存设备可能 OOM（更新恰是最不该崩的场景）。
  final output = _DigestSink();
  final converter = sha256.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    converter.add(chunk);
  }
  converter.close();
  return output.digest!;
}

class _DigestSink implements Sink<Digest> {
  String? digest;

  @override
  void add(Digest data) => digest = data.toString();

  @override
  void close() {}
}
