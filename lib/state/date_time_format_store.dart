import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VaultTimeFormat { twelveHour, twentyFourHour }

enum VaultDateFormat { monthDayYear, dayMonthYear, yearMonthDay }

@immutable
class VaultDateTimeFormatConfig {
  const VaultDateTimeFormatConfig({
    this.timeFormat = VaultTimeFormat.twelveHour,
    this.dateFormat = VaultDateFormat.monthDayYear,
  });

  final VaultTimeFormat timeFormat;
  final VaultDateFormat dateFormat;

  VaultDateTimeFormatConfig copyWith({
    VaultTimeFormat? timeFormat,
    VaultDateFormat? dateFormat,
  }) {
    return VaultDateTimeFormatConfig(
      timeFormat: timeFormat ?? this.timeFormat,
      dateFormat: dateFormat ?? this.dateFormat,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'timeFormat': timeFormat.name,
    'dateFormat': dateFormat.name,
  };

  static VaultDateTimeFormatConfig fromJson(Map<String, dynamic> json) {
    return VaultDateTimeFormatConfig(
      timeFormat: VaultTimeFormat.values.firstWhere(
        (value) => value.name == json['timeFormat'],
        orElse: () => VaultTimeFormat.twelveHour,
      ),
      dateFormat: VaultDateFormat.values.firstWhere(
        (value) => value.name == json['dateFormat'],
        orElse: () => VaultDateFormat.monthDayYear,
      ),
    );
  }
}

class DateTimeFormatStore {
  static const String _prefsKey = 'cc_date_time_format_v1';
  static const VaultDateTimeFormatConfig _defaultConfig =
      VaultDateTimeFormatConfig();

  static final ValueNotifier<VaultDateTimeFormatConfig> formatNotifier =
      ValueNotifier<VaultDateTimeFormatConfig>(_defaultConfig);

  static VaultDateTimeFormatConfig get config => formatNotifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      formatNotifier.value = _defaultConfig;
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        formatNotifier.value = _defaultConfig;
        return;
      }
      formatNotifier.value = VaultDateTimeFormatConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      formatNotifier.value = _defaultConfig;
    }
  }

  static Future<void> setTimeFormat(VaultTimeFormat value) async {
    final next = config.copyWith(timeFormat: value);
    formatNotifier.value = next;
    await _save(next);
  }

  static Future<void> setDateFormat(VaultDateFormat value) async {
    final next = config.copyWith(dateFormat: value);
    formatNotifier.value = next;
    await _save(next);
  }

  static Future<void> reset() async {
    formatNotifier.value = _defaultConfig;
    await _save(_defaultConfig);
  }

  static bool get use24HourClock =>
      config.timeFormat == VaultTimeFormat.twentyFourHour;

  static String formatTime(BuildContext context, DateTime dateTime) {
    final local = dateTime.toLocal();
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: use24HourClock,
    );
  }

  static String formatDate(DateTime dateTime, {bool includeYear = true}) {
    final local = dateTime.toLocal();
    switch (config.dateFormat) {
      case VaultDateFormat.monthDayYear:
        return includeYear
            ? '${local.month}/${local.day}/${local.year}'
            : '${local.month}/${local.day}';
      case VaultDateFormat.dayMonthYear:
        return includeYear
            ? '${local.day}/${local.month}/${local.year}'
            : '${local.day}/${local.month}';
      case VaultDateFormat.yearMonthDay:
        final month = _twoDigits(local.month);
        final day = _twoDigits(local.day);
        return includeYear ? '${local.year}-$month-$day' : '$month-$day';
    }
  }

  static String formatMessageTimestamp(
    BuildContext context,
    DateTime dateTime,
  ) {
    return '${formatDate(dateTime)} ${formatTime(context, dateTime)}';
  }

  static String formatListTimestamp(BuildContext context, DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final isToday = _isSameDate(local, now);
    if (isToday) {
      return formatTime(context, local);
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDate(local, yesterday)) {
      return 'Yesterday';
    }

    return formatDate(local, includeYear: local.year != now.year);
  }

  static String sampleDateLabel(VaultDateFormat dateFormat) {
    final sample = DateTime(2026, 4, 8);
    switch (dateFormat) {
      case VaultDateFormat.monthDayYear:
        return '${sample.month}/${sample.day}/${sample.year}';
      case VaultDateFormat.dayMonthYear:
        return '${sample.day}/${sample.month}/${sample.year}';
      case VaultDateFormat.yearMonthDay:
        return '${sample.year}-${_twoDigits(sample.month)}-${_twoDigits(sample.day)}';
    }
  }

  static String sampleTimeLabel(VaultTimeFormat timeFormat) {
    return timeFormat == VaultTimeFormat.twentyFourHour ? '21:17' : '9:17 PM';
  }

  static bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static Future<void> _save(VaultDateTimeFormatConfig value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(value.toJson()));
  }
}
