import 'catalog_account_widgets.dart';
import 'package:flutter/material.dart';
import 'cycani_api.dart';

class CycaniAccountPage extends StatefulWidget {
  const CycaniAccountPage({super.key, this.embedded = false, this.api});
  final CycaniApi? api;
  final bool embedded;
  @override
  State<CycaniAccountPage> createState() => _CycaniAccountPageState();
}

class _CycaniAccountPageState extends State<CycaniAccountPage>
    with VerificationCooldownState {
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  final form = GlobalKey<FormState>();
  final username = TextEditingController(),
      password = TextEditingController(),
      nickname = TextEditingController(),
      email = TextEditingController(),
      code = TextEditingController();
  String mode = 'login';
  bool busy = false;
  @override
  void dispose() {
    for (final c in [username, password, nickname, email, code]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  void _message(String value) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _sendCode() async {
    if (busy || countdown > 0 || !email.text.contains('@')) return;
    setState(() => busy = true);
    try {
      await api.sendCode(email.text, mode == 'register' ? 'register' : 'reset');
      if (!mounted) return;
      cooldown.start();
      _message('验证码已发送');
    } catch (e) {
      _message('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    if (busy || form.currentState?.validate() != true) return;
    setState(() => busy = true);
    try {
      if (mode == 'reset') {
        await api.resetPassword(email.text, code.text, password.text);
        if (mounted) setState(() => mode = 'login');
        _message('密码已重置');
      } else {
        if (mode == 'register')
          await api.register({
            'username': username.text.trim(),
            'password': password.text,
            'nickname': nickname.text.trim(),
            'email': email.text.trim(),
            'email_code': code.text.trim(),
          });
        await api.login(username.text, password.text);
        if (mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
      }
      password.clear();
    } catch (e) {
      _message('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool secret = false,
    bool required = true,
  }) => CatalogAccountField(
    controller: c,
    label: label,
    secret: secret,
    required: required,
    enabled: !busy,
  );
  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Image.asset(
                    'assets/images/logo/cycani.png',
                    width: 76,
                    height: 76,
                  ),
                ),
                const SizedBox(height: 24),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'login', label: Text('登录')),
                    ButtonSegment(value: 'register', label: Text('注册')),
                    ButtonSegment(value: 'reset', label: Text('重置密码')),
                  ],
                  selected: {mode},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() => mode = v.single),
                ),
                const SizedBox(height: 24),
                if (mode != 'reset') _field(username, '用户名'),
                if (mode == 'register') _field(nickname, '昵称', required: false),
                if (mode != 'login') ...[
                  _field(email, '邮箱'),
                  Row(
                    children: [
                      Expanded(child: _field(code, '验证码')),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: busy || countdown > 0 ? null : _sendCode,
                        child: Text(countdown > 0 ? '${countdown}s' : '发送验证码'),
                      ),
                    ],
                  ),
                ],
                _field(password, mode == 'reset' ? '新密码' : '密码', secret: true),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: Text(
                    busy
                        ? '处理中…'
                        : mode == 'register'
                        ? '注册并登录'
                        : mode == 'reset'
                        ? '重置密码'
                        : '登录',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(
              title: Text(
                mode == 'register'
                    ? '注册'
                    : mode == 'reset'
                    ? '重置密码'
                    : '登录',
              ),
            ),
            body: content,
          );
  }
}
