class Event {
  final String? id;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String title;

  Event({
    this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.title,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'start_time': startTime,
      'end_time': endTime,
      'title': title,
    };
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'],
      date: DateTime.parse(json['date']),
      startTime: json['start_time'],
      endTime: json['end_time'],
      title: json['title'],
    );
  }

  Event copyWith({
    String? id,
    DateTime? date,
    String? startTime,
    String? endTime,
    String? title,
  }) {
    return Event(
      id: id ?? this.id,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      title: title ?? this.title,
    );
  }
}
