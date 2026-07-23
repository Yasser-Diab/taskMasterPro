import 'package:uuid/uuid.dart';

enum RoadmapSchedulingMode { deadlineDriven, capacityDriven, balanced }

extension RoadmapSchedulingModeX on RoadmapSchedulingMode {
  String get storageValue {
    return switch (this) {
      RoadmapSchedulingMode.deadlineDriven => 'deadline_driven',
      RoadmapSchedulingMode.capacityDriven => 'capacity_driven',
      RoadmapSchedulingMode.balanced => 'balanced',
    };
  }

  static RoadmapSchedulingMode fromStorage(String? value) {
    return switch (value) {
      'deadline_driven' => RoadmapSchedulingMode.deadlineDriven,
      'balanced' => RoadmapSchedulingMode.balanced,
      _ => RoadmapSchedulingMode.capacityDriven,
    };
  }
}

class RoadmapPlan {
  RoadmapPlan({
    String? id,
    required this.userId,
    required this.title,
    this.description = '',
    this.currentLevel,
    this.targetLevel,
    this.status = 'active',
    DateTime? startDate,
    this.originalTargetDate,
    this.currentTargetDate,
    this.forecastFinishDate,
    this.weeklyCapacityMinutes = 0,
    this.maximumDailyMinutes = 0,
    this.preferredDays = const [],
    this.schedulingMode = RoadmapSchedulingMode.capacityDriven,
    this.overallProgress = 0,
    this.confidence,
    this.colorSeed = '#3B82F6',
    this.iconName,
    this.templateKey,
    this.templateVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       startDate = startDate ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String userId;
  final String title;
  final String description;
  final String? currentLevel;
  final String? targetLevel;
  final String status;
  final DateTime startDate;
  final DateTime? originalTargetDate;
  final DateTime? currentTargetDate;
  final DateTime? forecastFinishDate;
  final int weeklyCapacityMinutes;
  final int maximumDailyMinutes;
  final List<int> preferredDays;
  final RoadmapSchedulingMode schedulingMode;
  final double overallProgress;
  final int? confidence;
  final String colorSeed;
  final String? iconName;
  final String? templateKey;
  final int? templateVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RoadmapPlan.fromInput({
    required String userId,
    required CreateRoadmapInput input,
  }) {
    return RoadmapPlan(
      userId: userId,
      title: input.title.trim(),
      description: input.description.trim(),
      currentLevel: input.currentLevel.trim().isEmpty
          ? null
          : input.currentLevel.trim(),
      targetLevel: input.targetLevel.trim().isEmpty
          ? null
          : input.targetLevel.trim(),
      startDate: input.startDate,
      originalTargetDate: input.targetDate,
      currentTargetDate: input.targetDate,
      weeklyCapacityMinutes: input.weeklyCapacityMinutes,
      maximumDailyMinutes: input.maximumDailyMinutes,
      preferredDays: input.preferredDays,
      schedulingMode: input.schedulingMode,
      status: 'active',
    );
  }

  factory RoadmapPlan.fromMap(Map<String, dynamic> map) {
    return RoadmapPlan(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      currentLevel: map['current_level']?.toString(),
      targetLevel: map['target_level']?.toString(),
      status: map['status']?.toString() ?? 'active',
      startDate: _dateFromMap(map['start_date']) ?? DateTime.now(),
      originalTargetDate: _dateFromMap(map['original_target_date']),
      currentTargetDate: _dateFromMap(map['current_target_date']),
      forecastFinishDate: _dateFromMap(map['forecast_finish_date']),
      weeklyCapacityMinutes: _intFromMap(map['weekly_capacity_minutes']),
      maximumDailyMinutes: _intFromMap(map['maximum_daily_minutes']),
      preferredDays: _intListFromMap(map['preferred_days']),
      schedulingMode: RoadmapSchedulingModeX.fromStorage(
        map['scheduling_mode']?.toString(),
      ),
      overallProgress: _doubleFromMap(map['overall_progress']),
      confidence: _nullableIntFromMap(map['confidence']),
      colorSeed: map['color_seed']?.toString() ?? '#3B82F6',
      iconName: map['icon_name']?.toString(),
      templateKey: map['template_key']?.toString(),
      templateVersion: _nullableIntFromMap(map['template_version']),
      createdAt: _dateFromMap(map['created_at']) ?? DateTime.now(),
      updatedAt: _dateFromMap(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'description': description,
      'current_level': currentLevel,
      'target_level': targetLevel,
      'status': status,
      'start_date': _dateOnly(startDate),
      'original_target_date': originalTargetDate == null
          ? null
          : _dateOnly(originalTargetDate!),
      'current_target_date': currentTargetDate == null
          ? null
          : _dateOnly(currentTargetDate!),
      'forecast_finish_date': forecastFinishDate == null
          ? null
          : _dateOnly(forecastFinishDate!),
      'weekly_capacity_minutes': weeklyCapacityMinutes,
      'maximum_daily_minutes': maximumDailyMinutes,
      'preferred_days': preferredDays,
      'scheduling_mode': schedulingMode.storageValue,
      'overall_progress': overallProgress,
      'confidence': confidence,
      'color_seed': colorSeed,
      'icon_name': iconName,
      'template_key': templateKey,
      'template_version': templateVersion,
    };
  }
}

class CreateRoadmapInput {
  const CreateRoadmapInput({
    required this.title,
    required this.description,
    required this.currentLevel,
    required this.targetLevel,
    required this.startDate,
    required this.targetDate,
    required this.weeklyCapacityMinutes,
    required this.maximumDailyMinutes,
    required this.preferredDays,
    required this.schedulingMode,
    required this.structureChoice,
  });

  final String title;
  final String description;
  final String currentLevel;
  final String targetLevel;
  final DateTime startDate;
  final DateTime? targetDate;
  final int weeklyCapacityMinutes;
  final int maximumDailyMinutes;
  final List<int> preferredDays;
  final RoadmapSchedulingMode schedulingMode;
  final String structureChoice;
}

DateTime? _dateFromMap(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

String _dateOnly(DateTime date) {
  return date.toIso8601String().split('T').first;
}

int _intFromMap(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableIntFromMap(Object? value) {
  if (value == null) {
    return null;
  }
  return _intFromMap(value);
}

double _doubleFromMap(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<int> _intListFromMap(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (_nullableIntFromMap(item) != null) _nullableIntFromMap(item)!,
    ];
  }
  return const [];
}
