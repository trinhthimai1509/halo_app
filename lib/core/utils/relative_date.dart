import '../constants/app_strings.dart';

/// Formats [date] relative to [now]: "Today", "Yesterday", a weekday within
/// the last week, "Mar 4" within the year, otherwise "Mar 4, 2025".
String formatRelativeDay(DateTime date, {required DateTime now}) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(day).inDays;

  if (difference <= 0) return AppStrings.today;
  if (difference == 1) return AppStrings.yesterday;
  if (difference < 7) return AppStrings.weekdays[date.weekday - 1];

  final month = AppStrings.monthsShort[date.month - 1];
  if (date.year == now.year) return '$month ${date.day}';
  return '$month ${date.day}, ${date.year}';
}
