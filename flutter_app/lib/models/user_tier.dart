enum UserTier {
  free,
  pro,
  ultra,
}

extension UserTierExtension on UserTier {
  int get maxDaysAccess {
    switch (this) {
      case UserTier.free:
        return 14;
      case UserTier.pro:
        return 30;
      case UserTier.ultra:
        return 60;
    }
  }

  String get name {
    switch (this) {
      case UserTier.free:
        return 'FREE';
      case UserTier.pro:
        return 'PRO';
      case UserTier.ultra:
        return 'ULTRA';
    }
  }
}
