/// User role types
enum UserRole {
  admin,
  free,
  premium,
}

/// Extension to convert string to UserRole
extension UserRoleExtension on UserRole {
  String get value {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.free:
        return 'free';
      case UserRole.premium:
        return 'premium';
    }
  }

  static UserRole fromString(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'premium':
        return UserRole.premium;
      case 'free':
      default:
        return UserRole.free;
    }
  }
}

/// User permissions based on role
class RolePermissions {
  final UserRole role;

  RolePermissions(this.role);

  /// Admin has all permissions
  bool get isAdmin => role == UserRole.admin;

  /// Premium has subscription features
  bool get isPremium => role == UserRole.premium;

  /// Free is default role
  bool get isFree => role == UserRole.free;

  /// Can export to PDF
  bool get canExportPDF => isAdmin || isPremium;

  /// Can access advanced analytics
  bool get canAccessAnalytics => isAdmin || isPremium;

  /// Can create unlimited payments/collections
  bool get hasUnlimitedTransactions => isAdmin;

  /// Can access premium features
  bool get canAccessPremiumFeatures => isAdmin || isPremium;

  /// Can manage users (admin only)
  bool get canManageUsers => isAdmin;

  /// Can access all data (admin only)
  bool get canAccessAllData => isAdmin;

  /// Maximum number of transactions (null = unlimited)
  int? get maxTransactions {
    if (isAdmin) return null; // unlimited
    if (isPremium) return 3000; // 3000 for premium
    return 15; // 15 for free
  }

  /// Maximum number of active sessions
  int get maxActiveSessions {
    if (isAdmin) return 1; // solo 1 sesión
    if (isPremium) return 3; // 3 sesiones
    return 2; // 2 sesiones para free
  }

  /// Can customize app theme
  bool get canCustomizeTheme => isAdmin || isPremium;

  /// Can use advanced search filters
  bool get canUseAdvancedFilters => isAdmin || isPremium;
}
