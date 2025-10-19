from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime
from models import UserTier, validate_date_range, get_max_allowed_date
from firestore_service import FirestoreService
import os


app = Flask(__name__)
CORS(app)  # Enable CORS for Flutter app

# Initialize Firestore service
db_service = FirestoreService()


def get_user_tier_from_request() -> UserTier:
    """Extract user tier from request headers"""
    tier_str = request.headers.get('X-User-Tier', 'FREE')
    return UserTier.from_string(tier_str)


def validate_event_date(date_str: str, user_tier: UserTier) -> tuple:
    """
    Validate event date against user tier limits
    
    Returns:
        Tuple of (is_valid, error_message)
    """
    try:
        event_date = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
    except ValueError:
        return False, "Invalid date format"
    
    if not validate_date_range(event_date, user_tier):
        max_date = get_max_allowed_date(user_tier)
        return False, (
            f"Date is outside allowed range for {user_tier.value} tier. "
            f"Maximum {user_tier.max_days_access} days from today "
            f"(until {max_date.date().isoformat()})"
        )
    
    return True, None


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'Flow7 API'}), 200


@app.route('/events', methods=['POST'])
def create_event():
    """Create a new event with tier-based date validation"""
    try:
        data = request.get_json()
        user_tier = get_user_tier_from_request()
        
        # Validate required fields
        required_fields = ['date', 'start_time', 'end_time', 'title']
        for field in required_fields:
            if field not in data:
                return jsonify({'error': f'Missing required field: {field}'}), 400
        
        # Validate date range based on user tier
        is_valid, error_msg = validate_event_date(data['date'], user_tier)
        if not is_valid:
            return jsonify({'error': error_msg}), 403
        
        # Create event
        event = db_service.create_event(data)
        
        return jsonify(event), 201
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/events', methods=['GET'])
def get_events():
    """Get events within a date range"""
    try:
        start_date_str = request.args.get('start_date')
        end_date_str = request.args.get('end_date')
        
        if not start_date_str or not end_date_str:
            return jsonify({'error': 'start_date and end_date are required'}), 400
        
        # Parse dates
        start_date = datetime.fromisoformat(start_date_str.replace('Z', '+00:00'))
        end_date = datetime.fromisoformat(end_date_str.replace('Z', '+00:00'))
        
        # Get events
        user_id = request.args.get('user_id')
        events = db_service.get_events(start_date, end_date, user_id)
        
        return jsonify(events), 200
        
    except ValueError:
        return jsonify({'error': 'Invalid date format'}), 400
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/events/<event_id>', methods=['GET'])
def get_event(event_id):
    """Get a single event by ID"""
    try:
        event = db_service.get_event(event_id)
        
        if event is None:
            return jsonify({'error': 'Event not found'}), 404
        
        return jsonify(event), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/events/<event_id>', methods=['PUT'])
def update_event(event_id):
    """Update an event with tier-based date validation"""
    try:
        data = request.get_json()
        user_tier = get_user_tier_from_request()
        
        # Check if event exists
        existing_event = db_service.get_event(event_id)
        if existing_event is None:
            return jsonify({'error': 'Event not found'}), 404
        
        # Validate date if provided
        if 'date' in data:
            is_valid, error_msg = validate_event_date(data['date'], user_tier)
            if not is_valid:
                return jsonify({'error': error_msg}), 403
        
        # Update event
        event = db_service.update_event(event_id, data)
        
        return jsonify(event), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/events/<event_id>', methods=['DELETE'])
def delete_event(event_id):
    """Delete an event"""
    try:
        # Check if event exists
        existing_event = db_service.get_event(event_id)
        if existing_event is None:
            return jsonify({'error': 'Event not found'}), 404
        
        # Delete event
        db_service.delete_event(event_id)
        
        return '', 204
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/tier-info', methods=['GET'])
def get_tier_info():
    """Get information about user tier limits"""
    user_tier = get_user_tier_from_request()
    max_date = get_max_allowed_date(user_tier)
    
    return jsonify({
        'tier': user_tier.value,
        'max_days_access': user_tier.max_days_access,
        'max_date': max_date.date().isoformat(),
    }), 200


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=True)
