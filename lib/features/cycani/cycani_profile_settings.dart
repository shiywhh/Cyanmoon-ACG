import 'catalog_action.dart';
import 'site_avatar.dart';
import 'catalog_account_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cyanmoon_acg/bean/settings/settings_detail_scaffold.dart';
import 'package:cyanmoon_acg/request/config/api_endpoints.dart';
import 'cycani_account_page.dart';
import 'cycani_api.dart';
import 'catalog_avatar_store.dart';
import 'catalog_models.dart';
import 'qingyue_my_page.dart';

class CycaniProfileSettingsPage extends StatefulWidget {
  const CycaniProfileSettingsPage({
    super.key,
    this.api,
    this.localNavigation = false,
  });
  final CycaniApi? api;
  final bool localNavigation;
  @override
  State<CycaniProfileSettingsPage> createState() =>
      _CycaniProfileSettingsPageState();
}

class _CycaniProfileSettingsPageState extends State<CycaniProfileSettingsPage> {
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  final avatars = CatalogAvatarStore.instance;
  final nickname = TextEditingController();
  late int _profileEpoch;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _profileEpoch = api.sessionEpoch;
    nickname.text = '${api.user['nickname'] ?? ''}';
    api.addListener(_changed);
    avatars.addListener(_changed);
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final draft = nickname.text, epoch = api.sessionEpoch;
    try {
      await avatars.initialize();
      if (api.loggedIn && epoch == api.sessionEpoch) await api.profile();
      if (mounted && epoch == api.sessionEpoch) {
        if (nickname.text == draft)
          nickname.text = '${api.user['nickname'] ?? ''}';
        setState(() {});
      }
    } catch (_) {}
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_profileEpoch != api.sessionEpoch) {
        _profileEpoch = api.sessionEpoch;
        nickname.text = '${api.user['nickname'] ?? ''}';
      }
    });
  }

  @override
  void dispose() {
    api.removeListener(_changed);
    avatars.removeListener(_changed);
    nickname.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) => runCatalogAction(
    busy: busy,
    active: () => mounted,
    setBusy: (value) => setState(() => busy = value),
    action: action,
    onError: (error) => ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error'))),
  );

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('个人资料'),
    leading: widget.localNavigation ? const BackButton() : null,
    body: !api.loggedIn
        ? Center(
            child: FilledButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CycaniAccountPage(),
                  ),
                );
                if (mounted) await _prepare();
              },
              child: const Text('登录'),
            ),
          )
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: SiteAvatarPicker(
                      enabled: !busy,
                      choose: () => avatars.choose(
                        catalogInt(api.user['id'] ?? api.user['user_id']),
                      ),
                      reset: () => avatars.clear(
                        catalogInt(api.user['id'] ?? api.user['user_id']),
                      ),
                      child: Column(
                        children: [
                          CycaniAvatar(api: api, store: avatars, size: 90),
                          const SizedBox(height: 10),
                          const Text('更换头像'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: nickname,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => _run(
                            () => api.updateProfile({
                              'nickname': nickname.text.trim(),
                            }),
                          ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
  );
}

class CycaniSecuritySettingsPage extends StatefulWidget {
  const CycaniSecuritySettingsPage({
    super.key,
    this.api,
    this.localNavigation = false,
  });
  final CycaniApi? api;
  final bool localNavigation;
  @override
  State<CycaniSecuritySettingsPage> createState() =>
      _CycaniSecuritySettingsPageState();
}

class _CycaniSecuritySettingsPageState extends State<CycaniSecuritySettingsPage>
    with VerificationCooldownState {
  CycaniApi get api => widget.api ?? CycaniApi.instance;
  final email = TextEditingController(),
      code = TextEditingController(),
      old = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    email.text = '${api.user['email'] ?? ''}';
    api.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    api.removeListener(_changed);
    for (final c in [email, code, old, password, confirm]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String success = '已保存'}) =>
      runCatalogAction(
        busy: busy,
        active: () => mounted,
        setBusy: (value) => setState(() => busy = value),
        action: action,
        onError: (error) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error'))),
        onSuccess: () => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success))),
      );

  Widget _field(TextEditingController c, String label, {bool secret = false}) =>
      CatalogAccountField(
        controller: c,
        label: label,
        secret: secret,
        enabled: !busy,
      );
  Future<void> _send() async {
    if (countdown > 0 || !email.text.contains('@')) return;
    await _run(() async {
      await api.sendCode(email.text, 'bind');
      if (!mounted) return;
      cooldown.start();
    }, success: '验证码已发送');
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('账户与安全'),
    leading: widget.localNavigation ? const BackButton() : null,
    body: !api.loggedIn
        ? Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CycaniAccountPage(),
                ),
              ),
              child: const Text('登录'),
            ),
          )
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('绑定邮箱', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  _field(email, '邮箱'),
                  Row(
                    children: [
                      Expanded(child: _field(code, '验证码')),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: busy || countdown > 0 ? null : _send,
                        child: Text(countdown > 0 ? '${countdown}s' : '发送验证码'),
                      ),
                    ],
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () =>
                              _run(() => api.bindEmail(email.text, code.text)),
                    child: const Text('绑定'),
                  ),
                  const SizedBox(height: 28),
                  Text('修改密码', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  _field(old, '当前密码', secret: true),
                  _field(password, '新密码', secret: true),
                  _field(confirm, '确认新密码', secret: true),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () {
                            if (password.text.isEmpty ||
                                old.text.isEmpty ||
                                password.text != confirm.text) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请检查密码')),
                              );
                              return;
                            }
                            _run(() async {
                              await api.changePassword(old.text, password.text);
                              old.clear();
                              password.clear();
                              confirm.clear();
                            }, success: '密码已修改');
                          },
                    child: const Text('修改密码'),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('退出登录'),
                    onPressed: busy
                        ? null
                        : () => _run(api.logout, success: '已退出登录'),
                  ),
                ],
              ),
            ),
          ),
  );
}

class QingyueAboutPage extends StatelessWidget {
  const QingyueAboutPage({super.key});
  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('关于'),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.nightlight_round,
            size: 90,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text('青月次元', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(ApiEndpoints.version),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => context.pushNamed('/settings/about/license'),
            child: const Text('开源许可证'),
          ),
        ],
      ),
    ),
  );
}
