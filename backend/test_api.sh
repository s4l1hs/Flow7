#!/bin/bash

# Flow7 API Testing Examples
# This script demonstrates how to interact with the Flow7 API using curl

BASE_URL="http://localhost:8000"

echo "========================================="
echo "Flow7 API Testing Examples"
echo "========================================="
echo ""

# Check if server is running
echo "1. Health Check"
echo "Command: curl -X GET $BASE_URL/health"
curl -X GET $BASE_URL/health
echo -e "\n"

# Get tier information
echo "========================================="
echo "2. Get Tier Information (FREE)"
echo "Command: curl -X GET -H 'X-User-Tier: FREE' $BASE_URL/tier-info"
curl -X GET -H "X-User-Tier: FREE" $BASE_URL/tier-info
echo -e "\n"

echo "========================================="
echo "3. Get Tier Information (PRO)"
echo "Command: curl -X GET -H 'X-User-Tier: PRO' $BASE_URL/tier-info"
curl -X GET -H "X-User-Tier: PRO" $BASE_URL/tier-info
echo -e "\n"

echo "========================================="
echo "4. Get Tier Information (ULTRA)"
echo "Command: curl -X GET -H 'X-User-Tier: ULTRA' $BASE_URL/tier-info"
curl -X GET -H "X-User-Tier: ULTRA" $BASE_URL/tier-info
echo -e "\n"

# Create event - valid date for FREE tier (5 days from now)
echo "========================================="
echo "5. Create Event (Valid - 5 days from now, FREE tier)"
VALID_DATE=$(date -u -d "+5 days" +"%Y-%m-%dT00:00:00")
echo "Command: curl -X POST -H 'Content-Type: application/json' -H 'X-User-Tier: FREE' \\"
echo "  -d '{\"date\":\"$VALID_DATE\",\"start_time\":\"09:00\",\"end_time\":\"10:00\",\"title\":\"Team Meeting\"}' \\"
echo "  $BASE_URL/events"
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-User-Tier: FREE" \
  -d "{\"date\":\"$VALID_DATE\",\"start_time\":\"09:00\",\"end_time\":\"10:00\",\"title\":\"Team Meeting\"}" \
  $BASE_URL/events
echo -e "\n"

# Create event - invalid date for FREE tier (20 days from now)
echo "========================================="
echo "6. Create Event (Invalid - 20 days from now, FREE tier - should fail)"
INVALID_DATE=$(date -u -d "+20 days" +"%Y-%m-%dT00:00:00")
echo "Command: curl -X POST -H 'Content-Type: application/json' -H 'X-User-Tier: FREE' \\"
echo "  -d '{\"date\":\"$INVALID_DATE\",\"start_time\":\"14:00\",\"end_time\":\"15:00\",\"title\":\"Future Event\"}' \\"
echo "  $BASE_URL/events"
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-User-Tier: FREE" \
  -d "{\"date\":\"$INVALID_DATE\",\"start_time\":\"14:00\",\"end_time\":\"15:00\",\"title\":\"Future Event\"}" \
  $BASE_URL/events
echo -e "\n"

# Create event - valid date for PRO tier (25 days from now)
echo "========================================="
echo "7. Create Event (Valid - 25 days from now, PRO tier)"
PRO_VALID_DATE=$(date -u -d "+25 days" +"%Y-%m-%dT00:00:00")
echo "Command: curl -X POST -H 'Content-Type: application/json' -H 'X-User-Tier: PRO' \\"
echo "  -d '{\"date\":\"$PRO_VALID_DATE\",\"start_time\":\"11:00\",\"end_time\":\"12:00\",\"title\":\"PRO Event\"}' \\"
echo "  $BASE_URL/events"
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-User-Tier: PRO" \
  -d "{\"date\":\"$PRO_VALID_DATE\",\"start_time\":\"11:00\",\"end_time\":\"12:00\",\"title\":\"PRO Event\"}" \
  $BASE_URL/events
echo -e "\n"

# Get events for a date range
echo "========================================="
echo "8. Get Events (Date Range)"
START_DATE=$(date -u -d "today" +"%Y-%m-%dT00:00:00")
END_DATE=$(date -u -d "+30 days" +"%Y-%m-%dT23:59:59")
echo "Command: curl -X GET '$BASE_URL/events?start_date=$START_DATE&end_date=$END_DATE'"
curl -X GET "$BASE_URL/events?start_date=$START_DATE&end_date=$END_DATE"
echo -e "\n"

# Example: Update event (requires event ID from creation)
echo "========================================="
echo "9. Update Event Example"
echo "First, create an event and capture its ID:"
EVENT_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-User-Tier: FREE" \
  -d "{\"date\":\"$VALID_DATE\",\"start_time\":\"16:00\",\"end_time\":\"17:00\",\"title\":\"Update Test\"}" \
  $BASE_URL/events)
echo "Event created: $EVENT_RESPONSE"

# Note: In a real script, you would parse the JSON to extract the ID
# For this example, we show the command structure:
echo ""
echo "To update the event (replace EVENT_ID with actual ID):"
echo "curl -X PUT -H 'Content-Type: application/json' -H 'X-User-Tier: FREE' \\"
echo "  -d '{\"title\":\"Updated Title\",\"start_time\":\"16:30\",\"end_time\":\"17:30\"}' \\"
echo "  $BASE_URL/events/EVENT_ID"
echo ""

# Example: Delete event
echo "========================================="
echo "10. Delete Event Example"
echo "To delete an event (replace EVENT_ID with actual ID):"
echo "curl -X DELETE $BASE_URL/events/EVENT_ID"
echo ""

echo "========================================="
echo "Testing Complete!"
echo "========================================="
echo ""
echo "Note: Some commands may fail if Firestore is not configured."
echo "To properly test CRUD operations, ensure serviceAccountKey.json is in backend/"
echo ""
