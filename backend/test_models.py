"""
Unit tests for Flow7 Backend
"""

import unittest
from datetime import datetime, timedelta
from models import UserTier, validate_date_range, get_max_allowed_date


class TestUserTier(unittest.TestCase):
    """Test UserTier enum and methods"""
    
    def test_tier_max_days(self):
        """Test that each tier has correct max days"""
        self.assertEqual(UserTier.FREE.max_days_access, 14)
        self.assertEqual(UserTier.PRO.max_days_access, 30)
        self.assertEqual(UserTier.ULTRA.max_days_access, 60)
    
    def test_tier_from_string(self):
        """Test creating UserTier from string"""
        self.assertEqual(UserTier.from_string("FREE"), UserTier.FREE)
        self.assertEqual(UserTier.from_string("free"), UserTier.FREE)
        self.assertEqual(UserTier.from_string("PRO"), UserTier.PRO)
        self.assertEqual(UserTier.from_string("ULTRA"), UserTier.ULTRA)
        
        # Invalid tier should default to FREE
        self.assertEqual(UserTier.from_string("INVALID"), UserTier.FREE)
        self.assertEqual(UserTier.from_string(""), UserTier.FREE)


class TestDateValidation(unittest.TestCase):
    """Test date range validation functions"""
    
    def test_validate_date_range_free_tier(self):
        """Test date validation for FREE tier (14 days)"""
        tier = UserTier.FREE
        
        # Today should be valid
        today = datetime.now()
        self.assertTrue(validate_date_range(today, tier))
        
        # 13 days from now should be valid
        valid_date = today + timedelta(days=13)
        self.assertTrue(validate_date_range(valid_date, tier))
        
        # 14 days from now should be valid (edge case)
        edge_date = today + timedelta(days=14)
        self.assertTrue(validate_date_range(edge_date, tier))
        
        # 15 days from now should be invalid
        invalid_date = today + timedelta(days=15)
        self.assertFalse(validate_date_range(invalid_date, tier))
        
        # Yesterday should be invalid
        past_date = today - timedelta(days=1)
        self.assertFalse(validate_date_range(past_date, tier))
    
    def test_validate_date_range_pro_tier(self):
        """Test date validation for PRO tier (30 days)"""
        tier = UserTier.PRO
        today = datetime.now()
        
        # 29 days from now should be valid
        valid_date = today + timedelta(days=29)
        self.assertTrue(validate_date_range(valid_date, tier))
        
        # 30 days from now should be valid (edge case)
        edge_date = today + timedelta(days=30)
        self.assertTrue(validate_date_range(edge_date, tier))
        
        # 31 days from now should be invalid
        invalid_date = today + timedelta(days=31)
        self.assertFalse(validate_date_range(invalid_date, tier))
    
    def test_validate_date_range_ultra_tier(self):
        """Test date validation for ULTRA tier (60 days)"""
        tier = UserTier.ULTRA
        today = datetime.now()
        
        # 59 days from now should be valid
        valid_date = today + timedelta(days=59)
        self.assertTrue(validate_date_range(valid_date, tier))
        
        # 60 days from now should be valid (edge case)
        edge_date = today + timedelta(days=60)
        self.assertTrue(validate_date_range(edge_date, tier))
        
        # 61 days from now should be invalid
        invalid_date = today + timedelta(days=61)
        self.assertFalse(validate_date_range(invalid_date, tier))
    
    def test_get_max_allowed_date(self):
        """Test getting max allowed date for each tier"""
        today = datetime.now().date()
        
        # FREE tier
        max_date_free = get_max_allowed_date(UserTier.FREE)
        expected_free = today + timedelta(days=14)
        self.assertEqual(max_date_free.date(), expected_free)
        
        # PRO tier
        max_date_pro = get_max_allowed_date(UserTier.PRO)
        expected_pro = today + timedelta(days=30)
        self.assertEqual(max_date_pro.date(), expected_pro)
        
        # ULTRA tier
        max_date_ultra = get_max_allowed_date(UserTier.ULTRA)
        expected_ultra = today + timedelta(days=60)
        self.assertEqual(max_date_ultra.date(), expected_ultra)


if __name__ == '__main__':
    unittest.main()
