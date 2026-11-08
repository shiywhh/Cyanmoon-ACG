import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'catalog_models.dart';

String catalogAccountName(CatalogJson user, {String fallback = '账户'}) {
  for (final key in ['nickname', 'username', 'user_name', 'email']) {
    final value = '${user[key] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

class CatalogProfileHeader extends StatelessWidget {
  const CatalogProfileHeader({
    super.key,
    required this.avatar,
    required this.name,
    this.id = '',
    this.onTap,
  });
  final Widget avatar;
  final String name, id;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(28),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (id.isNotEmpty && id != '0') ...[
                  const SizedBox(height: 8),
                  Text(
                    'ID: $id',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
    ),
  );
}

class CatalogAccountDashboard extends StatelessWidget {
  const CatalogAccountDashboard({
    super.key,
    required this.header,
    required this.accountActions,
    this.libraryActions = const [],
    required this.logout,
    this.refresh,
    this.busy = false,
    this.error,
  });
  final Widget header;
  final List<Widget> accountActions, libraryActions;
  final VoidCallback? logout;
  final Future<void> Function()? refresh;
  final bool busy;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: header,
        ),
        const SizedBox(height: 16),
        SettingsSection(title: const Text('账户'), tiles: accountActions),
        if (libraryActions.isNotEmpty)
          SettingsSection(title: const Text('内容'), tiles: libraryActions),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: OutlinedButton.icon(
            onPressed: busy ? null : logout,
            icon: const Icon(Icons.logout),
            label: const Text('退出账号'),
          ),
        ),
      ],
    );
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: list,
      ),
    );
    return refresh == null
        ? content
        : RefreshIndicator(onRefresh: refresh!, child: content);
  }
}

class CatalogAccountLink extends StatelessWidget {
  const CatalogAccountLink({
    super.key,
    required this.title,
    required this.icon,
    this.onTap,
  });
  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SettingsTile(
    title: Text(title),
    leading: icon,
    trailing: const Icon(Icons.chevron_right),
    enabled: onTap != null,
    onPressed: onTap == null ? null : (_) => onTap!(),
  );
}
