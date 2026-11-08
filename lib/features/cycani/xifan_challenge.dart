import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

Map<String, String>? parseXifanChallenge(Object? result) {
  if (result is! Map) return null;
  final payload = <String, String>{};
  for (final name in [
    'lot_number',
    'captcha_output',
    'pass_token',
    'gen_time',
  ]) {
    final value = result[name];
    if (value is! String || value.isEmpty || value.length > 8192) return null;
    payload[name] = value;
  }
  return payload;
}

class XifanChallengePage extends StatefulWidget {
  const XifanChallengePage({super.key});

  @override
  State<XifanChallengePage> createState() => _XifanChallengePageState();
}

class _XifanChallengePageState extends State<XifanChallengePage> {
  PlatformInAppWebViewWidget? _web;
  bool _finished = false;

  static const _document = '''
<!doctype html><html lang="zh-CN"><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://*.geetest.com https://*.geetest.cn; connect-src https://*.geetest.com https://*.geetest.cn; img-src data: https://*.geetest.com https://*.geetest.cn; style-src 'unsafe-inline' https://*.geetest.com https://*.geetest.cn; frame-src https://*.geetest.com https://*.geetest.cn">
</head><body><button id="open" disabled>开始验证</button><p id="state"></p>
<script>
const button = document.getElementById('open'), state = document.getElementById('state');
const script = document.createElement('script');
script.src = 'https://static.geetest.com/v4/gt4.js';
script.onerror = () => state.textContent = '验证组件加载失败';
script.onload = () => {
  if (!window.initGeetest4) { state.textContent = '验证组件不可用'; return; }
  window.initGeetest4({captchaId:'9c1f947ab00eca920049a0d25ba85cd7',product:'bind'}, captcha => {
    captcha.onReady(() => { button.disabled = false; });
    captcha.onSuccess(() => {
      const data = captcha.getValidate();
      window.flutter_inappwebview.callHandler('xifanChallenge', data);
    });
    captcha.onError(() => { state.textContent = '验证失败，可重新尝试'; });
    button.onclick = () => { state.textContent = ''; captcha.showCaptcha(); };
  });
};
document.head.appendChild(script);
</script></body></html>
''';

  @override
  void initState() {
    super.initState();
    if (InAppWebViewPlatform.instance == null) return;
    _web = PlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams(
        initialData: InAppWebViewInitialData(
          data: _document,
          baseUrl: WebUri('https://next.xifanacg.com/'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useShouldOverrideUrlLoading: true,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          allowFileAccess: false,
          allowContentAccess: false,
        ),
        shouldOverrideUrlLoading: (_, request) async =>
            request.isForMainFrame == false
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL,
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'xifanChallenge',
            callback: (args) {
              final data = parseXifanChallenge(
                args.isEmpty ? null : args.first,
              );
              if (mounted && !_finished && data != null) {
                _finished = true;
                Navigator.of(context).pop(data);
              }
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('安全验证')),
    body: _web?.build(context) ?? const Center(child: Text('此平台未启用验证组件')),
  );
}
