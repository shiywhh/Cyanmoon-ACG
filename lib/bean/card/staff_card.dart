import 'package:flutter/material.dart';
import 'package:cyanmoon_acg/bean/widget/bangumi_avatar.dart';
import 'package:cyanmoon_acg/modules/staff/staff_item.dart';

class StaffCard extends StatelessWidget {
  const StaffCard({
    super.key,
    required this.staffFullItem,
  });

  final StaffFullItem staffFullItem;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: BangumiAvatar(
        imageUrl: staffFullItem.staff.images?.grid ?? '',
      ),
      title: Text(
        staffFullItem.staff.name,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: staffFullItem.staff.nameCN.isNotEmpty
          ? Text(staffFullItem.staff.nameCN)
          : null,
      trailing: Text(staffFullItem.relations.isNotEmpty
          ? staffFullItem.relations.first
          : ''),
    );
  }
}
