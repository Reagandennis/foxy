import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  late DateTime _focusedMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  User? get _currentUser => _client.auth.currentUser;

  Stream<List<_CalendarTask>> _tasksStream() {
    final User? user = _currentUser;
    if (user == null) {
      return Stream<List<_CalendarTask>>.value(const <_CalendarTask>[]);
    }

    return _client
        .from('tasks')
        .stream(primaryKey: <String>['id'])
        .eq('user_id', user.id)
        .order('updated_at', ascending: false)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map(_CalendarTask.fromMap).toList(),
        );
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<DateTime> _calendarDays(DateTime month) {
    final DateTime firstOfMonth = DateTime(month.year, month.month, 1);
    final int startOffset = firstOfMonth.weekday % 7;
    final DateTime firstVisible = firstOfMonth.subtract(
      Duration(days: startOffset),
    );

    return List<DateTime>.generate(
      42,
      (int index) => firstVisible.add(Duration(days: index)),
      growable: false,
    );
  }

  void _moveMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
      final int maxDays = DateUtils.getDaysInMonth(
        _focusedMonth.year,
        _focusedMonth.month,
      );
      final int safeDay = _selectedDay.day > maxDays
          ? maxDays
          : _selectedDay.day;
      _selectedDay = DateTime(_focusedMonth.year, _focusedMonth.month, safeDay);
    });
  }

  String _monthLabel(DateTime month) {
    const List<String> names = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[month.month - 1]} ${month.year}';
  }

  String _dateLabel(DateTime day) {
    return '${day.month}/${day.day}/${day.year}';
  }

  String _timeLabel(DateTime value) {
    final String hh = value.hour.toString().padLeft(2, '0');
    final String mm = value.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    const List<String> weekdayLabels = <String>[
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
    ];

    return SafeArea(
      child: StreamBuilder<List<_CalendarTask>>(
        stream: _tasksStream(),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<_CalendarTask>> snapshot,
            ) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Unable to load calendar tasks. Verify tasks table setup and policies.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: accentRed),
                );
              }

              final List<_CalendarTask> tasks = snapshot.data!;
              final Map<DateTime, List<_CalendarTask>> tasksByDay =
                  <DateTime, List<_CalendarTask>>{};

              for (final _CalendarTask task in tasks) {
                final DateTime eventDate = task.calendarDate;
                final DateTime key = _startOfDay(eventDate);
                tasksByDay.putIfAbsent(key, () => <_CalendarTask>[]).add(task);
              }

              for (final List<_CalendarTask> dayTasks in tasksByDay.values) {
                dayTasks.sort(_CalendarTask.compareForDay);
              }

              final List<DateTime> days = _calendarDays(_focusedMonth);
              final List<_CalendarTask> selectedDayTasks =
                  tasksByDay[_startOfDay(_selectedDay)] ??
                  const <_CalendarTask>[];

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => _moveMonth(-1),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Text(
                            _monthLabel(_focusedMonth),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _moveMonth(1),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: textColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: weekdayLabels
                              .map(
                                (String label) => Expanded(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: textColor.withValues(
                                            alpha: 0.65,
                                          ),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: days.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                                childAspectRatio: 0.95,
                              ),
                          itemBuilder: (BuildContext context, int index) {
                            final DateTime day = days[index];
                            final DateTime key = _startOfDay(day);
                            final int count = tasksByDay[key]?.length ?? 0;
                            final bool isCurrentMonth =
                                day.month == _focusedMonth.month;
                            final bool isSelected = _sameDay(day, _selectedDay);
                            final bool isToday = _sameDay(day, DateTime.now());

                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  _selectedDay = key;
                                  _focusedMonth = DateTime(day.year, day.month);
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accentRed.withValues(alpha: 0.16)
                                      : appBackground.withValues(alpha: 0.62),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? accentRed
                                        : isToday
                                        ? accentGold
                                        : textColor.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        color: isCurrentMonth
                                            ? textColor
                                            : textColor.withValues(alpha: 0.42),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (count > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accentRed.withValues(
                                            alpha: 0.18,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '$count',
                                          style: TextStyle(
                                            color: textColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: textColor.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
                      children: [
                        Text(
                          'Tasks on ${_dateLabel(_selectedDay)}',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (selectedDayTasks.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: surfaceColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: textColor.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              'No tasks for this day.',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ...selectedDayTasks.map((_CalendarTask task) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CalendarTaskTile(
                              task: task,
                              timeLabel: _timeLabel,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              );
            },
      ),
    );
  }
}

class _CalendarTaskTile extends StatelessWidget {
  const _CalendarTaskTile({required this.task, required this.timeLabel});

  final _CalendarTask task;
  final String Function(DateTime value) timeLabel;

  @override
  Widget build(BuildContext context) {
    final DateTime? dueAt = task.dueAt;
    final DateTime? reminderAt = task.reminderAt;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: task.isCompleted
                  ? Colors.green.withValues(alpha: 0.15)
                  : accentRed.withValues(alpha: 0.13),
            ),
            child: Icon(
              task.isCompleted ? Icons.check_rounded : Icons.circle_outlined,
              size: 15,
              color: task.isCompleted ? Colors.green.shade700 : accentRed,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title.isEmpty ? 'Untitled task' : task.title,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                if (task.details.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.72),
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (dueAt != null)
                      _TaskMetaPill(
                        icon: Icons.event_rounded,
                        text: 'Due ${timeLabel(dueAt)}',
                      ),
                    if (reminderAt != null)
                      _TaskMetaPill(
                        icon: Icons.notifications_active_rounded,
                        text: 'Reminder ${timeLabel(reminderAt)}',
                      ),
                    if (dueAt == null && reminderAt == null)
                      _TaskMetaPill(
                        icon: Icons.schedule_rounded,
                        text: 'Created ${timeLabel(task.createdAt)}',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskMetaPill extends StatelessWidget {
  const _TaskMetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: appBackground.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor.withValues(alpha: 0.76)),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.76),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarTask {
  const _CalendarTask({
    required this.title,
    required this.details,
    required this.isCompleted,
    required this.createdAt,
    required this.dueAt,
    required this.reminderAt,
  });

  factory _CalendarTask.fromMap(Map<String, dynamic> map) {
    return _CalendarTask(
      title: (map['title'] as String? ?? '').trim(),
      details: map['details'] as String? ?? '',
      isCompleted: map['is_completed'] == true,
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      dueAt: DateTime.tryParse(map['due_at']?.toString() ?? '')?.toLocal(),
      reminderAt: DateTime.tryParse(
        map['reminder_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  DateTime get calendarDate => dueAt ?? reminderAt ?? createdAt;

  static int compareForDay(_CalendarTask a, _CalendarTask b) {
    return a.calendarDate.compareTo(b.calendarDate);
  }

  final String title;
  final String details;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? dueAt;
  final DateTime? reminderAt;
}
