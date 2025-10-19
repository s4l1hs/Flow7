import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/user_tier.dart';
import '../services/api_service.dart';
import '../widgets/weekly_calendar.dart';
import '../widgets/event_list.dart';
import '../widgets/event_dialog.dart';

class PlannerScreen extends StatefulWidget {
  final UserTier userTier;
  final String apiBaseUrl;

  const PlannerScreen({
    Key? key,
    this.userTier = UserTier.free,
    this.apiBaseUrl = 'http://localhost:8000',
  }) : super(key: key);

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  late ApiService _apiService;
  late DateTime _selectedDate;
  List<Event> _events = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _apiService = ApiService(
      baseUrl: widget.apiBaseUrl,
      userTier: widget.userTier,
    );
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final events = await _apiService.getEvents(startOfDay, endOfDay);
      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading events: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEventDialog([Event? event]) async {
    final result = await showDialog<Event>(
      context: context,
      builder: (context) => EventDialog(
        event: event,
        selectedDate: _selectedDate,
      ),
    );

    if (result != null) {
      if (event == null) {
        await _createEvent(result);
      } else {
        await _updateEvent(result);
      }
    }
  }

  Future<void> _createEvent(Event event) async {
    try {
      await _apiService.createEvent(event);
      await _loadEvents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event created successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating event: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateEvent(Event event) async {
    try {
      await _apiService.updateEvent(event);
      await _loadEvents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating event: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteEvent(Event event) async {
    if (event.id == null) return;

    try {
      await _apiService.deleteEvent(event.id!);
      await _loadEvents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting event: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flow7 - Weekly Planner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showTierInfo(),
          ),
        ],
      ),
      body: Column(
        children: [
          WeeklyCalendar(
            initialDate: DateTime.now(),
            userTier: widget.userTier,
            selectedDate: _selectedDate,
            onDateSelected: (date) {
              setState(() {
                _selectedDate = date;
              });
              _loadEvents();
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_apiService.isDateAllowed(_selectedDate))
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    onPressed: () => _showEventDialog(),
                    color: Theme.of(context).primaryColor,
                    iconSize: 32,
                  ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : EventList(
                    events: _events,
                    onEventTap: _showEventDialog,
                    onEventDelete: _deleteEvent,
                  ),
          ),
        ],
      ),
    );
  }

  void _showTierInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subscription Tier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Plan: ${widget.userTier.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You can plan up to ${widget.userTier.maxDaysAccess} days in the future.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Upgrade to access more planning days:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildTierItem('FREE', 14, widget.userTier == UserTier.free),
            _buildTierItem('PRO', 30, widget.userTier == UserTier.pro),
            _buildTierItem('ULTRA', 60, widget.userTier == UserTier.ultra),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTierItem(String name, int days, bool isCurrent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isCurrent ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: isCurrent ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            '$name: $days days',
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
