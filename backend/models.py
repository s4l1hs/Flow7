from enum import Enum
from datetime import datetime, timedelta


class UserTier(Enum):
    FREE = "FREE"
    PRO = "PRO"
    ULTRA = "ULTRA"

    @property
    def max_days_access(self) -> int:
        """Returns the maximum number of days a user can plan ahead"""
        tier_limits = {
            UserTier.FREE: 14,
            UserTier.PRO: 30,
            UserTier.ULTRA: 60,
        }
        return tier_limits[self]

    @classmethod
    def from_string(cls, tier_str: str):
        """Convert string to UserTier enum"""
        try:
            return cls[tier_str.upper()]
        except KeyError:
            return cls.FREE  # Default to FREE if invalid tier


def validate_date_range(date: datetime, user_tier: UserTier) -> bool:
    """
    Validates if a date is within the allowed range for a user tier.
    
    Args:
        date: The date to validate
        user_tier: The user's subscription tier
        
    Returns:
        True if date is within allowed range, False otherwise
    """
    today = datetime.now().date()
    max_date = today + timedelta(days=user_tier.max_days_access)
    target_date = date.date() if isinstance(date, datetime) else date
    
    return today <= target_date <= max_date


def get_max_allowed_date(user_tier: UserTier) -> datetime:
    """
    Get the maximum allowed date for a user tier.
    
    Args:
        user_tier: The user's subscription tier
        
    Returns:
        The maximum allowed date
    """
    today = datetime.now().date()
    return datetime.combine(
        today + timedelta(days=user_tier.max_days_access),
        datetime.min.time()
    )
