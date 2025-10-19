"""
Flow7 Backend - Tier System Demo

This script demonstrates the tier-based date range enforcement.
Run this after starting the Flask server (python app.py).
"""

import requests
from datetime import datetime, timedelta
import json


BASE_URL = "http://localhost:8000"


def test_tier_limits():
    """Test tier limits for FREE, PRO, and ULTRA tiers"""
    
    print("=" * 60)
    print("Flow7 Tier System Demo")
    print("=" * 60)
    print()
    
    tiers = {
        "FREE": 14,
        "PRO": 30,
        "ULTRA": 60
    }
    
    for tier_name, max_days in tiers.items():
        print(f"\n{'=' * 60}")
        print(f"Testing {tier_name} Tier (Max {max_days} days)")
        print('=' * 60)
        
        # Get tier info
        response = requests.get(
            f"{BASE_URL}/tier-info",
            headers={"X-User-Tier": tier_name}
        )
        
        if response.status_code == 200:
            tier_info = response.json()
            print(f"✓ Tier Info: {json.dumps(tier_info, indent=2)}")
        else:
            print(f"✗ Failed to get tier info: {response.text}")
            continue
        
        # Test creating event within limit
        valid_date = datetime.now() + timedelta(days=max_days - 1)
        event_data = {
            "date": valid_date.isoformat(),
            "start_time": "09:00",
            "end_time": "10:00",
            "title": f"{tier_name} - Valid Event (Day {max_days - 1})"
        }
        
        print(f"\n1. Creating event within limit (day {max_days - 1})...")
        response = requests.post(
            f"{BASE_URL}/events",
            json=event_data,
            headers={
                "Content-Type": "application/json",
                "X-User-Tier": tier_name
            }
        )
        
        if response.status_code == 201:
            print(f"   ✓ Event created successfully!")
            print(f"   Event ID: {response.json().get('id')}")
        else:
            print(f"   ✗ Failed: {response.text}")
        
        # Test creating event beyond limit
        invalid_date = datetime.now() + timedelta(days=max_days + 1)
        event_data = {
            "date": invalid_date.isoformat(),
            "start_time": "09:00",
            "end_time": "10:00",
            "title": f"{tier_name} - Invalid Event (Day {max_days + 1})"
        }
        
        print(f"\n2. Creating event beyond limit (day {max_days + 1})...")
        response = requests.post(
            f"{BASE_URL}/events",
            json=event_data,
            headers={
                "Content-Type": "application/json",
                "X-User-Tier": tier_name
            }
        )
        
        if response.status_code == 403:
            print(f"   ✓ Correctly rejected: {response.json().get('error')}")
        else:
            print(f"   ✗ Should have been rejected but got: {response.status_code}")
            print(f"   Response: {response.text}")
    
    print("\n" + "=" * 60)
    print("Demo Complete!")
    print("=" * 60)


def test_event_crud():
    """Test basic CRUD operations"""
    
    print("\n" + "=" * 60)
    print("Testing CRUD Operations")
    print("=" * 60)
    
    # Create
    print("\n1. Creating event...")
    event_data = {
        "date": (datetime.now() + timedelta(days=1)).isoformat(),
        "start_time": "14:00",
        "end_time": "15:00",
        "title": "CRUD Test Event"
    }
    
    response = requests.post(
        f"{BASE_URL}/events",
        json=event_data,
        headers={
            "Content-Type": "application/json",
            "X-User-Tier": "FREE"
        }
    )
    
    if response.status_code == 201:
        event = response.json()
        event_id = event.get('id')
        print(f"   ✓ Created event with ID: {event_id}")
        
        # Read
        print(f"\n2. Reading event {event_id}...")
        response = requests.get(f"{BASE_URL}/events/{event_id}")
        
        if response.status_code == 200:
            print(f"   ✓ Retrieved event: {response.json().get('title')}")
        else:
            print(f"   ✗ Failed to read: {response.text}")
        
        # Update
        print(f"\n3. Updating event {event_id}...")
        update_data = {
            "title": "Updated CRUD Test Event",
            "start_time": "15:00",
            "end_time": "16:00"
        }
        
        response = requests.put(
            f"{BASE_URL}/events/{event_id}",
            json=update_data,
            headers={
                "Content-Type": "application/json",
                "X-User-Tier": "FREE"
            }
        )
        
        if response.status_code == 200:
            print(f"   ✓ Updated event: {response.json().get('title')}")
        else:
            print(f"   ✗ Failed to update: {response.text}")
        
        # Delete
        print(f"\n4. Deleting event {event_id}...")
        response = requests.delete(f"{BASE_URL}/events/{event_id}")
        
        if response.status_code in [200, 204]:
            print(f"   ✓ Deleted event successfully")
        else:
            print(f"   ✗ Failed to delete: {response.text}")
    else:
        print(f"   ✗ Failed to create event: {response.text}")


if __name__ == "__main__":
    try:
        # Check if server is running
        response = requests.get(f"{BASE_URL}/health")
        if response.status_code != 200:
            print("Error: Server is not responding correctly")
            exit(1)
        
        print(f"✓ Server is running at {BASE_URL}")
        
        # Run tests
        test_tier_limits()
        test_event_crud()
        
    except requests.exceptions.ConnectionError:
        print(f"Error: Could not connect to server at {BASE_URL}")
        print("Please make sure the Flask server is running:")
        print("  cd backend && python app.py")
        exit(1)
    except Exception as e:
        print(f"Error: {e}")
        exit(1)
