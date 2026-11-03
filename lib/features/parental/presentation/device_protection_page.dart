import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_area_guard.dart';
import 'device_protection_section.dart';
import 'uninstall_tile.dart';

/// Bảo vệ máy: gom trạng thái chống tắt (Trợ năng, bảo vệ màn Cài đặt) và
/// chống gỡ (quản trị thiết bị) vào một chỗ.
class DeviceProtectionPage extends StatelessWidget {
  const DeviceProtectionPage({super.key, required this.guard});

  final ParentGuard guard;

  @override
  Widget build(BuildContext context) {
    return ParentAreaGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Bảo vệ máy')),
        body: ListView(
          children: [
            DeviceProtectionSection(guard: guard),
            UninstallTile(guard: guard),
          ],
        ),
      ),
    );
  }
}
