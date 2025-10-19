import os
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime
from typing import List, Dict, Optional


class FirestoreService:
    """Service class for Firestore database operations"""
    
    def __init__(self):
        """Initialize Firestore connection"""
        # Initialize Firebase Admin SDK
        if not firebase_admin._apps:
            # In production, use service account credentials
            # For development, you can use default credentials or a service account file
            if os.path.exists('serviceAccountKey.json'):
                cred = credentials.Certificate('serviceAccountKey.json')
                firebase_admin.initialize_app(cred)
            else:
                # Use default credentials (works in Google Cloud environment)
                firebase_admin.initialize_app()
        
        self.db = firestore.client()
        self.events_collection = self.db.collection('events')

    def create_event(self, event_data: Dict) -> Dict:
        """
        Create a new event in Firestore
        
        Args:
            event_data: Dictionary containing event details
            
        Returns:
            Dictionary with created event including ID
        """
        # Add timestamp
        event_data['created_at'] = firestore.SERVER_TIMESTAMP
        event_data['updated_at'] = firestore.SERVER_TIMESTAMP
        
        # Create document
        doc_ref = self.events_collection.add(event_data)
        event_id = doc_ref[1].id
        
        # Return event with ID
        result = event_data.copy()
        result['id'] = event_id
        
        return result

    def get_events(
        self, 
        start_date: datetime, 
        end_date: datetime,
        user_id: Optional[str] = None
    ) -> List[Dict]:
        """
        Get events within a date range
        
        Args:
            start_date: Start date for query
            end_date: End date for query
            user_id: Optional user ID to filter events
            
        Returns:
            List of event dictionaries
        """
        query = self.events_collection
        
        # Filter by date range
        query = query.where('date', '>=', start_date.isoformat())
        query = query.where('date', '<=', end_date.isoformat())
        
        # Filter by user if provided
        if user_id:
            query = query.where('user_id', '==', user_id)
        
        # Order by date and start time
        query = query.order_by('date').order_by('start_time')
        
        # Execute query
        docs = query.stream()
        
        events = []
        for doc in docs:
            event = doc.to_dict()
            event['id'] = doc.id
            events.append(event)
        
        return events

    def get_event(self, event_id: str) -> Optional[Dict]:
        """
        Get a single event by ID
        
        Args:
            event_id: Event document ID
            
        Returns:
            Event dictionary or None if not found
        """
        doc = self.events_collection.document(event_id).get()
        
        if doc.exists:
            event = doc.to_dict()
            event['id'] = doc.id
            return event
        
        return None

    def update_event(self, event_id: str, event_data: Dict) -> Dict:
        """
        Update an existing event
        
        Args:
            event_id: Event document ID
            event_data: Dictionary with updated event data
            
        Returns:
            Updated event dictionary
        """
        # Add update timestamp
        event_data['updated_at'] = firestore.SERVER_TIMESTAMP
        
        # Update document
        doc_ref = self.events_collection.document(event_id)
        doc_ref.update(event_data)
        
        # Return updated event
        result = event_data.copy()
        result['id'] = event_id
        
        return result

    def delete_event(self, event_id: str) -> bool:
        """
        Delete an event
        
        Args:
            event_id: Event document ID
            
        Returns:
            True if deleted successfully
        """
        self.events_collection.document(event_id).delete()
        return True
