# Flow7 API Documentation

## Base URL
```
http://localhost:8000
```

## Headers
All requests should include:
```
X-User-Tier: FREE|PRO|ULTRA
```

## Endpoints

### Health Check
```
GET /health
```
**Response:**
```json
{
  "status": "healthy",
  "service": "Flow7 API"
}
```

### Create Event
```
POST /events
```
**Headers:**
- `Content-Type: application/json`
- `X-User-Tier: FREE|PRO|ULTRA`

**Request Body:**
```json
{
  "date": "2024-01-15T00:00:00",
  "start_time": "09:00",
  "end_time": "10:00",
  "title": "Team Meeting"
}
```

**Response (201 Created):**
```json
{
  "id": "event_id_123",
  "date": "2024-01-15T00:00:00",
  "start_time": "09:00",
  "end_time": "10:00",
  "title": "Team Meeting",
  "created_at": "...",
  "updated_at": "..."
}
```

**Error Response (403 Forbidden):**
```json
{
  "error": "Date is outside allowed range for FREE tier. Maximum 14 days from today"
}
```

### Get Events
```
GET /events?start_date=2024-01-15T00:00:00&end_date=2024-01-16T00:00:00
```
**Query Parameters:**
- `start_date` (required): ISO 8601 format
- `end_date` (required): ISO 8601 format
- `user_id` (optional): Filter by user ID

**Response (200 OK):**
```json
[
  {
    "id": "event_id_123",
    "date": "2024-01-15T00:00:00",
    "start_time": "09:00",
    "end_time": "10:00",
    "title": "Team Meeting"
  }
]
```

### Get Single Event
```
GET /events/{event_id}
```

**Response (200 OK):**
```json
{
  "id": "event_id_123",
  "date": "2024-01-15T00:00:00",
  "start_time": "09:00",
  "end_time": "10:00",
  "title": "Team Meeting"
}
```

### Update Event
```
PUT /events/{event_id}
```
**Headers:**
- `Content-Type: application/json`
- `X-User-Tier: FREE|PRO|ULTRA`

**Request Body:**
```json
{
  "date": "2024-01-15T00:00:00",
  "start_time": "10:00",
  "end_time": "11:00",
  "title": "Updated Meeting"
}
```

**Response (200 OK):**
```json
{
  "id": "event_id_123",
  "date": "2024-01-15T00:00:00",
  "start_time": "10:00",
  "end_time": "11:00",
  "title": "Updated Meeting"
}
```

### Delete Event
```
DELETE /events/{event_id}
```

**Response (204 No Content)**

### Get Tier Information
```
GET /tier-info
```
**Headers:**
- `X-User-Tier: FREE|PRO|ULTRA`

**Response (200 OK):**
```json
{
  "tier": "FREE",
  "max_days_access": 14,
  "max_date": "2024-01-29"
}
```

## User Tier Limits

| Tier  | Max Days Access | Description |
|-------|----------------|-------------|
| FREE  | 14 days        | Free tier with basic planning |
| PRO   | 30 days        | Pro tier with extended planning |
| ULTRA | 60 days        | Ultra tier with maximum planning |

## Date Range Enforcement

The API enforces date range limits based on the user tier specified in the `X-User-Tier` header:

- Requests to create or update events with dates beyond the tier limit will return a 403 Forbidden error
- The error message will include the tier name and maximum allowed days
- Dates are validated from today's date forward
