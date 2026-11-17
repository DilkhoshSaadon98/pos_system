
import 'package:characters/characters.dart';

import '../../../../core/classes/enums.dart';


class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    this.phone,
    this.isActive = true,
    this.lastLoginAt,
  });

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int,
        fullName: '${m['full_name']}',
        username: '${m['username']}',
        role: UserRole.fromDb(m['role']),
        phone: m['phone'] as String?,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        lastLoginAt: m['last_login_at'] as String?,
      );

  final int id;
  final String fullName;
  final String username;
  final UserRole role;
  final String? phone;
  final bool isActive;
  final String? lastLoginAt;

  bool get canSeeMoney => role.canSeeMoney;
  bool get canManage => role.canManageCatalog;
  bool get canManageUsers => role.canManageUsers;
  bool get canSeeBooks => role.canSeeBooks;
  bool get canUseTill => role.canUseTill;
  bool get canVoid => role.canVoid;

  String get initials {
    final List<String> parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}
