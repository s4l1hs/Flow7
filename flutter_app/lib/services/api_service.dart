import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/event.dart';
import '../models/user_tier.dart';

class ApiService {
  final String baseUrl;
  final UserTier userTier;

  ApiService({
    required this.baseUrl,
    required this.userTier,
  });

  // Get maximum allowed future date based on user tier
  DateTime getMaxAllowedDate() {
    return DateTime.now().add(Duration(days: userTier.maxDaysAccess));
  }

  // Validate if a date is within allowed range
  bool isDateAllowed(DateTime date) {
    final now = DateTime.now();
    final maxDate = getMaxAllowedDate();
    
    // Normalize dates to midnight for comparison
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedNow = DateTime(now.year, now.month, now.day);
    final normalizedMax = DateTime(maxDate.year, maxDate.month, maxDate.day);
    
    return !normalizedDate.isBefore(normalizedNow) && 
           !normalizedDate.isAfter(normalizedMax);
  }

  // Create event
  Future<Event> createEvent(Event event) async {
    if (!isDateAllowed(event.date)) {
      throw Exception(
        'Date is outside allowed range for ${userTier.name} tier. '
        'Maximum ${userTier.maxDaysAccess} days from today.'
      );
    }

    final response = await http.post(
      Uri.parse('$baseUrl/events'),
      headers: {
        'Content-Type': 'application/json',
        'X-User-Tier': userTier.name,
      },
      body: jsonEncode(event.toJson()),
    );

    if (response.statusCode == 201) {
      return Event.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create event: ${response.body}');
    }
  }

  // Get events for a date range
  Future<List<Event>> getEvents(DateTime startDate, DateTime endDate) async {
    final response = await http.get(
      Uri.parse('$baseUrl/events?start_date=${startDate.toIso8601String()}&end_date=${endDate.toIso8601String()}'),
      headers: {
        'X-User-Tier': userTier.name,
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.map((json) => Event.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load events: ${response.body}');
    }
  }

  // Update event
  Future<Event> updateEvent(Event event) async {
    if (event.id == null) {
      throw Exception('Event ID is required for update');
    }

    if (!isDateAllowed(event.date)) {
      throw Exception(
        'Date is outside allowed range for ${userTier.name} tier. '
        'Maximum ${userTier.maxDaysAccess} days from today.'
      );
    }

    final response = await http.put(
      Uri.parse('$baseUrl/events/${event.id}'),
      headers: {
        'Content-Type': 'application/json',
        'X-User-Tier': userTier.name,
      },
      body: jsonEncode(event.toJson()),
    );

    if (response.statusCode == 200) {
      return Event.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update event: ${response.body}');
    }
  }

  // Delete event
  Future<void> deleteEvent(String eventId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/events/$eventId'),
      headers: {
        'X-User-Tier': userTier.name,
      },
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete event: ${response.body}');
    }
  }
}
