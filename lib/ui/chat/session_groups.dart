import '../../i18n/strings.dart';
import '../../models/chat_models.dart';

class SessionGroup {
  const SessionGroup(this.label, this.sessions);
  final String label;
  final List<SessionSummary> sessions;
}

List<SessionGroup> groupSessions(List<SessionSummary> summaries, S strings) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(const Duration(days: 6));

  final todayItems = <SessionSummary>[];
  final yesterdayItems = <SessionSummary>[];
  final weekItems = <SessionSummary>[];
  final earlierItems = <SessionSummary>[];

  for (final summary in summaries) {
    final date = DateTime.fromMillisecondsSinceEpoch(summary.updatedAt);
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isBefore(today)) {
      todayItems.add(summary);
    } else if (day == yesterday) {
      yesterdayItems.add(summary);
    } else if (!day.isBefore(weekStart)) {
      weekItems.add(summary);
    } else {
      earlierItems.add(summary);
    }
  }

  return [
    if (todayItems.isNotEmpty) SessionGroup(strings.today, todayItems),
    if (yesterdayItems.isNotEmpty)
      SessionGroup(strings.yesterday, yesterdayItems),
    if (weekItems.isNotEmpty) SessionGroup(strings.last7Days, weekItems),
    if (earlierItems.isNotEmpty) SessionGroup(strings.earlier, earlierItems),
  ];
}
