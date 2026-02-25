import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../services/task_notification_service.dart';
import '../../theme/app_colors.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _requestingNotificationPermission = false;
  bool? _notificationsEnabled;

  User? get _currentUser => _client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    TaskNotificationService.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNotificationStatus();
      _requestNotificationPermission(showFeedback: false);
    });
  }

  String get _tasksBucket => SupabaseConfig.tasksBucket;

  Future<void> _refreshNotificationStatus() async {
    final bool? enabled =
        await TaskNotificationService.areNotificationsEnabled();
    if (!mounted || enabled == null) {
      return;
    }
    setState(() {
      _notificationsEnabled = enabled;
    });
  }

  Future<void> _requestNotificationPermission({
    bool showFeedback = true,
  }) async {
    if (_requestingNotificationPermission) {
      return;
    }
    setState(() {
      _requestingNotificationPermission = true;
    });

    try {
      final bool granted = await TaskNotificationService.requestPermissions();
      if (!mounted) {
        return;
      }
      final bool? status =
          await TaskNotificationService.areNotificationsEnabled();
      setState(() {
        _notificationsEnabled = status ?? granted;
      });
      if (showFeedback) {
        final bool enabledNow = _notificationsEnabled ?? granted;
        if (enabledNow) {
          _showSnack('Notifications enabled.');
        } else {
          final String? details = TaskNotificationService.lastError;
          _showSnack(
            details == null
                ? 'Notifications are disabled for this app.'
                : 'Notifications disabled: $details',
          );
        }
      }
    } catch (_) {
      if (showFeedback) {
        final String? details = TaskNotificationService.lastError;
        final String base = details == null
            ? 'Could not request notification permission.'
            : 'Could not request notification permission: $details';
        _showSnack(
          base.contains('MissingPluginException')
              ? '$base Restart app after full reinstall.'
              : base,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _requestingNotificationPermission = false;
        });
      }
    }
  }

  Future<void> _sendTestNotification() async {
    try {
      await TaskNotificationService.showTestNotification();
      _showSnack('Test notification sent.');
    } catch (_) {
      _showSnack('Could not send test notification.');
    }
  }

  Stream<List<_TaskItem>> _tasksStream() {
    final User? user = _currentUser;
    if (user == null) {
      return Stream<List<_TaskItem>>.value(const <_TaskItem>[]);
    }

    return _client
        .from('tasks')
        .stream(primaryKey: <String>['id'])
        .eq('user_id', user.id)
        .order('updated_at', ascending: false)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map(_TaskItem.fromMap).toList()..sort(_compareTasks),
        );
  }

  int _compareTasks(_TaskItem a, _TaskItem b) {
    if (a.isCompleted != b.isCompleted) {
      return a.isCompleted ? 1 : -1;
    }

    if (a.dueAt != null && b.dueAt != null) {
      return a.dueAt!.compareTo(b.dueAt!);
    }
    if (a.dueAt != null) {
      return -1;
    }
    if (b.dueAt != null) {
      return 1;
    }
    return b.updatedAt.compareTo(a.updatedAt);
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDateTime(DateTime value) {
    final String mm = value.month.toString().padLeft(2, '0');
    final String dd = value.day.toString().padLeft(2, '0');
    final String hh = value.hour.toString().padLeft(2, '0');
    final String min = value.minute.toString().padLeft(2, '0');
    return '$mm/$dd ${value.year} $hh:$min';
  }

  Future<void> _syncReminderForTask({
    required String taskId,
    required String title,
    required String details,
    required DateTime? reminderAt,
    required bool isCompleted,
  }) async {
    if (isCompleted || reminderAt == null) {
      await TaskNotificationService.cancelReminder(taskId);
      return;
    }

    await TaskNotificationService.scheduleReminder(
      taskId: taskId,
      title: 'Foxy reminder: $title',
      body: details.isEmpty ? 'You scheduled this task reminder.' : details,
      when: reminderAt,
    );
  }

  List<_TaskAttachment> _removedAttachments({
    required List<_TaskAttachment> previous,
    required List<_TaskAttachment> next,
  }) {
    final Set<String> nextPaths = next
        .map((_TaskAttachment attachment) => attachment.storagePath)
        .where((String path) => path.isNotEmpty)
        .toSet();

    return previous
        .where((_TaskAttachment attachment) {
          if (attachment.storagePath.isEmpty) {
            return false;
          }
          return !nextPaths.contains(attachment.storagePath);
        })
        .toList(growable: false);
  }

  Future<void> _deleteAttachmentFiles(List<_TaskAttachment> attachments) async {
    final List<String> paths = attachments
        .map((_TaskAttachment attachment) => attachment.storagePath)
        .where((String path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) {
      return;
    }

    try {
      await _client.storage.from(_tasksBucket).remove(paths);
    } catch (_) {
      // Avoid blocking task CRUD if file cleanup fails.
    }
  }

  Future<void> _openTaskEditor({_TaskItem? task}) async {
    final _TaskEditorResult? result = await Navigator.of(context)
        .push<_TaskEditorResult>(
          MaterialPageRoute(
            builder: (_) =>
                _TaskEditorScreen(task: task, tasksBucket: _tasksBucket),
          ),
        );
    if (result == null) {
      return;
    }

    if (result.deleted) {
      if (task == null) {
        return;
      }
      await _deleteTask(task);
      return;
    }

    final String title = result.title.trim();
    final String details = result.details.trimRight();
    if (task == null) {
      if (title.isEmpty) {
        _showSnack('Task title is required.');
        return;
      }
      await _createTask(
        title: title,
        details: details,
        dueAt: result.dueAt,
        reminderAt: result.reminderAt,
        isCompleted: result.isCompleted,
        links: result.links,
        attachments: result.attachments,
        subtasks: result.subtasks,
      );
      return;
    }

    final bool updated = await _updateTask(
      task: task,
      title: title,
      details: details,
      dueAt: result.dueAt,
      reminderAt: result.reminderAt,
      isCompleted: result.isCompleted,
      links: result.links,
      attachments: result.attachments,
      subtasks: result.subtasks,
    );

    if (updated) {
      await _deleteAttachmentFiles(
        _removedAttachments(
          previous: task.attachments,
          next: result.attachments,
        ),
      );
    }
  }

  Future<void> _createTask({
    required String title,
    required String details,
    required DateTime? dueAt,
    required DateTime? reminderAt,
    required bool isCompleted,
    required List<String> links,
    required List<_TaskAttachment> attachments,
    required List<_TaskSubtask> subtasks,
  }) async {
    final User? user = _currentUser;
    if (user == null) {
      _showSnack('Session ended. Log in again.');
      return;
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'user_id': user.id,
      'title': title,
      'details': details,
      'is_completed': isCompleted,
      'due_at': dueAt?.toUtc().toIso8601String(),
      'reminder_at': reminderAt?.toUtc().toIso8601String(),
      'links': links,
      'attachments': attachments
          .map((_TaskAttachment attachment) => attachment.toMap())
          .toList(),
      'subtasks': subtasks
          .map((_TaskSubtask subtask) => subtask.toMap())
          .toList(),
    };

    try {
      final Map<String, dynamic> inserted = await _client
          .from('tasks')
          .insert(payload)
          .select('id')
          .single();
      final String taskId = inserted['id'].toString();

      await _syncReminderForTask(
        taskId: taskId,
        title: title,
        details: details,
        reminderAt: reminderAt,
        isCompleted: isCompleted,
      );
      _showSnack('Task created.');
    } catch (_) {
      _showSnack('Could not create task. Run latest supabase_notes_setup.sql.');
    }
  }

  Future<bool> _updateTask({
    required _TaskItem task,
    required String title,
    required String details,
    required DateTime? dueAt,
    required DateTime? reminderAt,
    required bool isCompleted,
    required List<String> links,
    required List<_TaskAttachment> attachments,
    required List<_TaskSubtask> subtasks,
  }) async {
    final User? user = _currentUser;
    if (user == null) {
      _showSnack('Session ended. Log in again.');
      return false;
    }

    try {
      await _client
          .from('tasks')
          .update(<String, dynamic>{
            'title': title,
            'details': details,
            'is_completed': isCompleted,
            'due_at': dueAt?.toUtc().toIso8601String(),
            'reminder_at': reminderAt?.toUtc().toIso8601String(),
            'links': links,
            'attachments': attachments
                .map((_TaskAttachment attachment) => attachment.toMap())
                .toList(),
            'subtasks': subtasks
                .map((_TaskSubtask subtask) => subtask.toMap())
                .toList(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', task.id)
          .eq('user_id', user.id);

      await _syncReminderForTask(
        taskId: task.id,
        title: title,
        details: details,
        reminderAt: reminderAt,
        isCompleted: isCompleted,
      );
      _showSnack('Task updated.');
      return true;
    } catch (_) {
      _showSnack('Could not update task. Check your connection and SQL setup.');
      return false;
    }
  }

  Future<void> _toggleCompleted(_TaskItem task, bool completed) async {
    final User? user = _currentUser;
    if (user == null) {
      _showSnack('Session ended. Log in again.');
      return;
    }

    try {
      await _client
          .from('tasks')
          .update(<String, dynamic>{
            'is_completed': completed,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', task.id)
          .eq('user_id', user.id);
      await _syncReminderForTask(
        taskId: task.id,
        title: task.title,
        details: task.details,
        reminderAt: task.reminderAt,
        isCompleted: completed,
      );
    } catch (_) {
      _showSnack('Could not update task status.');
    }
  }

  Future<void> _deleteTask(_TaskItem task) async {
    final User? user = _currentUser;
    if (user == null) {
      _showSnack('Session ended. Log in again.');
      return;
    }

    try {
      await _client
          .from('tasks')
          .delete()
          .eq('id', task.id)
          .eq('user_id', user.id);
      await _deleteAttachmentFiles(task.attachments);
      await TaskNotificationService.cancelReminder(task.id);
      _showSnack('Task deleted.');
    } catch (_) {
      _showSnack('Could not delete task.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: textColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Plan tasks, subtasks, files, links, and reminders.',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _notificationsEnabled == true
                            ? 'Notifications enabled'
                            : 'Notifications not enabled yet',
                        style: TextStyle(
                          color: _notificationsEnabled == true
                              ? Colors.green.shade700
                              : textColor.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _requestingNotificationPermission
                                ? null
                                : () => _requestNotificationPermission(),
                            icon: _requestingNotificationPermission
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.notifications_active_rounded,
                                  ),
                            label: const Text('Enable alerts'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _sendTestNotification,
                            icon: const Icon(Icons.notification_add_rounded),
                            label: const Text('Test alert'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<_TaskItem>>(
                  stream: _tasksStream(),
                  builder: (BuildContext context, AsyncSnapshot<List<_TaskItem>> snapshot) {
                    if (snapshot.hasError) {
                      return const _TasksEmptyState(
                        text:
                            'Unable to load tasks. Verify tasks table and policies.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: accentRed),
                      );
                    }

                    final List<_TaskItem> tasks = snapshot.data!;
                    if (tasks.isEmpty) {
                      return const _TasksEmptyState(
                        text: 'No tasks yet. Tap Add task to get started.',
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                      itemCount: tasks.length,
                      separatorBuilder: (_, index) => Divider(
                        height: 1,
                        color: textColor.withValues(alpha: 0.12),
                      ),
                      itemBuilder: (BuildContext context, int index) {
                        final _TaskItem task = tasks[index];
                        final int doneSubtasks = task.subtasks
                            .where((_TaskSubtask subtask) => subtask.completed)
                            .length;

                        return Dismissible(
                          key: ValueKey<String>('task-${task.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: accentRed,
                            child: const Icon(
                              Icons.delete_rounded,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (_) async {
                            final bool? delete = await showDialog<bool>(
                              context: context,
                              builder: (BuildContext dialogContext) {
                                return AlertDialog(
                                  backgroundColor: appBackground,
                                  title: const Text('Delete task?'),
                                  content: const Text(
                                    'Attachments and reminders will be removed.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(
                                        dialogContext,
                                      ).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(true),
                                      child: const Text(
                                        'Delete',
                                        style: TextStyle(color: accentRed),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                            return delete == true;
                          },
                          onDismissed: (_) => _deleteTask(task),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            onTap: () => _openTaskEditor(task: task),
                            leading: Checkbox(
                              value: task.isCompleted,
                              activeColor: accentRed,
                              onChanged: (bool? value) {
                                if (value == null) {
                                  return;
                                }
                                _toggleCompleted(task, value);
                              },
                            ),
                            title: Text(
                              task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (task.details.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      task.details,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor.withValues(
                                          alpha: 0.74,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    if (task.dueAt != null)
                                      _TaskMetaPill(
                                        icon: Icons.event_rounded,
                                        text:
                                            'Due ${_formatDateTime(task.dueAt!)}',
                                      ),
                                    if (task.reminderAt != null)
                                      _TaskMetaPill(
                                        icon:
                                            Icons.notifications_active_rounded,
                                        text:
                                            'Remind ${_formatDateTime(task.reminderAt!)}',
                                      ),
                                    if (task.subtasks.isNotEmpty)
                                      _TaskMetaPill(
                                        icon: Icons.checklist_rounded,
                                        text:
                                            'Subtasks $doneSubtasks/${task.subtasks.length}',
                                      ),
                                    if (task.attachments.isNotEmpty)
                                      _TaskMetaPill(
                                        icon: Icons.attach_file_rounded,
                                        text:
                                            '${task.attachments.length} files',
                                      ),
                                    if (task.links.isNotEmpty)
                                      _TaskMetaPill(
                                        icon: Icons.link_rounded,
                                        text: '${task.links.length} links',
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'tasks-fab',
              backgroundColor: accentRed,
              foregroundColor: Colors.white,
              onPressed: () => _openTaskEditor(),
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Add task'),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withValues(alpha: 0.12)),
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
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TasksEmptyState extends StatelessWidget {
  const _TasksEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _TaskEditorScreen extends StatefulWidget {
  const _TaskEditorScreen({required this.tasksBucket, this.task});

  final _TaskItem? task;
  final String tasksBucket;

  @override
  State<_TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<_TaskEditorScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  late final TextEditingController _titleController;
  late final TextEditingController _detailsController;

  late final String _initialTitle;
  late final String _initialDetails;
  late final bool _initialCompleted;
  late final DateTime? _initialDueAt;
  late final DateTime? _initialReminderAt;
  late final List<String> _initialLinks;
  late final List<_TaskAttachment> _initialAttachments;
  late final List<_TaskSubtask> _initialSubtasks;

  late bool _isCompleted;
  DateTime? _dueAt;
  DateTime? _reminderAt;
  List<String> _links = <String>[];
  List<_TaskAttachment> _attachments = <_TaskAttachment>[];
  List<_TaskSubtask> _subtasks = <_TaskSubtask>[];

  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    final _TaskItem? task = widget.task;
    _initialTitle = task?.title ?? '';
    _initialDetails = task?.details ?? '';
    _initialCompleted = task?.isCompleted ?? false;
    _initialDueAt = task?.dueAt;
    _initialReminderAt = task?.reminderAt;
    _initialLinks = List<String>.from(task?.links ?? const <String>[]);
    _initialAttachments = List<_TaskAttachment>.from(
      task?.attachments ?? const <_TaskAttachment>[],
    );
    _initialSubtasks = List<_TaskSubtask>.from(
      task?.subtasks ?? const <_TaskSubtask>[],
    );

    _isCompleted = _initialCompleted;
    _dueAt = _initialDueAt;
    _reminderAt = _initialReminderAt;
    _links = List<String>.from(_initialLinks);
    _attachments = List<_TaskAttachment>.from(_initialAttachments);
    _subtasks = List<_TaskSubtask>.from(_initialSubtasks);

    _titleController = TextEditingController(text: _initialTitle);
    _detailsController = TextEditingController(text: _initialDetails);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _safeExtension(String value, {required String fallback}) {
    final String clean = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    return clean.isEmpty ? fallback : clean;
  }

  String _extensionFromName(String name, {required String fallback}) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return fallback;
    }
    return _safeExtension(name.substring(dot + 1), fallback: fallback);
  }

  String _contentTypeFor(_TaskAttachmentType type, String ext) {
    if (type == _TaskAttachmentType.image) {
      switch (ext) {
        case 'png':
          return 'image/png';
        case 'gif':
          return 'image/gif';
        case 'webp':
          return 'image/webp';
        default:
          return 'image/jpeg';
      }
    }
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  Future<_TaskAttachment> _uploadAttachment({
    required _TaskAttachmentType type,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Session ended');
    }

    final String ext = _extensionFromName(
      fileName,
      fallback: type == _TaskAttachmentType.image ? 'jpg' : 'mp4',
    );
    final String timestamp = DateTime.now().microsecondsSinceEpoch.toString();
    final String path = '${user.id}/${type.storageValue}_$timestamp.$ext';
    final String contentType = _contentTypeFor(type, ext);

    await _client.storage
        .from(widget.tasksBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            cacheControl: '3600',
            contentType: contentType,
          ),
        );

    return _TaskAttachment(
      type: type,
      storagePath: path,
      name: fileName,
      contentType: contentType,
    );
  }

  Future<void> _addAttachment(_TaskAttachmentType type) async {
    if (_isUploading) {
      return;
    }

    final List<String> imageExts = <String>[
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
    ];
    final List<String> videoExts = <String>[
      'mp4',
      'mov',
      'm4v',
      'webm',
      'mkv',
      'avi',
      '3gp',
    ];
    final List<String> allowed = type == _TaskAttachmentType.image
        ? imageExts
        : videoExts;

    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowed,
        withData: true,
      );
      if (!mounted || picked == null || picked.files.isEmpty) {
        return;
      }
      final PlatformFile file = picked.files.first;
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showSnack('Could not read file.');
        return;
      }

      setState(() {
        _isUploading = true;
      });

      final _TaskAttachment attachment = await _uploadAttachment(
        type: type,
        bytes: bytes,
        fileName: file.name,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _attachments = <_TaskAttachment>[..._attachments, attachment];
      });
    } catch (_) {
      _showSnack('Could not upload attachment.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _addLink() async {
    String draft = '';
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: appBackground,
          title: const Text('Add link'),
          content: TextField(
            autofocus: true,
            keyboardType: TextInputType.url,
            onChanged: (String text) {
              draft = text;
            },
            decoration: const InputDecoration(
              hintText: 'https://example.com',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(draft.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (!mounted || value == null || value.isEmpty) {
      return;
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      _showSnack('Enter a valid http/https URL.');
      return;
    }

    setState(() {
      _links = <String>[..._links, uri.toString()];
    });
  }

  Future<void> _addSubtask() async {
    String draft = '';
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: appBackground,
          title: const Text('Add subtask'),
          content: TextField(
            autofocus: true,
            onChanged: (String text) {
              draft = text;
            },
            decoration: const InputDecoration(
              hintText: 'Subtask title',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(draft.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (!mounted || value == null || value.isEmpty) {
      return;
    }
    setState(() {
      _subtasks = <_TaskSubtask>[
        ..._subtasks,
        _TaskSubtask(title: value, completed: false),
      ];
    });
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(now.year - 1, 1, 1);
    final DateTime last = DateTime(now.year + 5, 12, 31);
    final DateTime initialDate = initial ?? now;

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: first,
      lastDate: last,
    );
    if (date == null || !mounted) {
      return null;
    }

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _saveAndExit() {
    if (_isUploading) {
      _showSnack('Wait for upload to finish.');
      return;
    }

    final String title = _titleController.text.trim();
    final String details = _detailsController.text.trimRight();

    if (title.isEmpty) {
      _showSnack('Task title is required.');
      return;
    }

    final bool unchanged =
        title == _initialTitle &&
        details == _initialDetails &&
        _isCompleted == _initialCompleted &&
        _dueAt == _initialDueAt &&
        _reminderAt == _initialReminderAt &&
        _listEquals(_links, _initialLinks) &&
        _listEquals(_attachments, _initialAttachments) &&
        _listEquals(_subtasks, _initialSubtasks);
    if (unchanged) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pop(
      _TaskEditorResult.save(
        title: title,
        details: details,
        isCompleted: _isCompleted,
        dueAt: _dueAt,
        reminderAt: _reminderAt,
        links: _links,
        attachments: _attachments,
        subtasks: _subtasks,
      ),
    );
  }

  Future<void> _deleteTask() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: appBackground,
          title: const Text('Delete task?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: accentRed)),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    Navigator.of(context).pop(const _TaskEditorResult.delete());
  }

  @override
  Widget build(BuildContext context) {
    String formatOrDash(DateTime? value) {
      if (value == null) {
        return 'Not set';
      }
      final String mm = value.month.toString().padLeft(2, '0');
      final String dd = value.day.toString().padLeft(2, '0');
      final String hh = value.hour.toString().padLeft(2, '0');
      final String min = value.minute.toString().padLeft(2, '0');
      return '$mm/$dd/${value.year} $hh:$min';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        _saveAndExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Task'),
          actions: [
            if (widget.task != null)
              IconButton(
                onPressed: _deleteTask,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            IconButton(
              onPressed: _saveAndExit,
              icon: const Icon(Icons.check_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: [
              TextField(
                controller: _titleController,
                style: const TextStyle(
                  color: textColor,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
                decoration: InputDecoration(
                  hintText: 'Task title',
                  hintStyle: TextStyle(
                    color: textColor.withValues(alpha: 0.36),
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                  border: InputBorder.none,
                ),
              ),
              TextField(
                controller: _detailsController,
                minLines: 2,
                maxLines: 5,
                style: const TextStyle(
                  color: textColor,
                  fontSize: 16,
                  height: 1.3,
                ),
                decoration: InputDecoration(
                  hintText: 'Details',
                  hintStyle: TextStyle(
                    color: textColor.withValues(alpha: 0.44),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _isCompleted,
                onChanged: (bool value) {
                  setState(() {
                    _isCompleted = value;
                  });
                },
                title: const Text('Mark as completed'),
                activeThumbColor: accentRed,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final DateTime? picked = await _pickDateTime(_dueAt);
                      if (picked == null || !mounted) {
                        return;
                      }
                      setState(() {
                        _dueAt = picked;
                      });
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text('Due: ${formatOrDash(_dueAt)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final DateTime? picked = await _pickDateTime(_reminderAt);
                      if (picked == null || !mounted) {
                        return;
                      }
                      setState(() {
                        _reminderAt = picked;
                      });
                    },
                    icon: const Icon(Icons.notifications_active_rounded),
                    label: Text('Reminder: ${formatOrDash(_reminderAt)}'),
                  ),
                  if (_dueAt != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _dueAt = null;
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Clear due'),
                    ),
                  if (_reminderAt != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _reminderAt = null;
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Clear reminder'),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _EditorSectionHeader(
                title: 'Subtasks',
                action: TextButton.icon(
                  onPressed: _addSubtask,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add'),
                ),
              ),
              if (_subtasks.isEmpty)
                Text(
                  'No subtasks yet.',
                  style: TextStyle(color: textColor.withValues(alpha: 0.65)),
                ),
              ..._subtasks.asMap().entries.map((
                MapEntry<int, _TaskSubtask> entry,
              ) {
                final int index = entry.key;
                final _TaskSubtask subtask = entry.value;
                return CheckboxListTile(
                  dense: true,
                  value: subtask.completed,
                  activeColor: accentRed,
                  title: Text(
                    subtask.title,
                    style: TextStyle(
                      decoration: subtask.completed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  secondary: IconButton(
                    onPressed: () {
                      setState(() {
                        final List<_TaskSubtask> next = List<_TaskSubtask>.from(
                          _subtasks,
                        );
                        next.removeAt(index);
                        _subtasks = next;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                  onChanged: (bool? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      final List<_TaskSubtask> next = List<_TaskSubtask>.from(
                        _subtasks,
                      );
                      next[index] = next[index].copyWith(completed: value);
                      _subtasks = next;
                    });
                  },
                );
              }),
              const SizedBox(height: 14),
              _EditorSectionHeader(
                title: 'Links',
                action: TextButton.icon(
                  onPressed: _addLink,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Add'),
                ),
              ),
              if (_links.isEmpty)
                Text(
                  'No links yet.',
                  style: TextStyle(color: textColor.withValues(alpha: 0.65)),
                ),
              if (_links.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _links.asMap().entries.map((
                    MapEntry<int, String> entry,
                  ) {
                    final int index = entry.key;
                    final String link = entry.value;
                    return InputChip(
                      avatar: const Icon(Icons.link_rounded, size: 16),
                      label: SizedBox(
                        width: 210,
                        child: Text(
                          link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onDeleted: () {
                        setState(() {
                          final List<String> next = List<String>.from(_links);
                          next.removeAt(index);
                          _links = next;
                        });
                      },
                    );
                  }).toList(),
                ),
              const SizedBox(height: 14),
              _EditorSectionHeader(
                title: 'Attachments',
                action: Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _isUploading
                          ? null
                          : () => _addAttachment(_TaskAttachmentType.image),
                      icon: const Icon(Icons.photo_outlined),
                      label: const Text('Image'),
                    ),
                    TextButton.icon(
                      onPressed: _isUploading
                          ? null
                          : () => _addAttachment(_TaskAttachmentType.video),
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Video'),
                    ),
                  ],
                ),
              ),
              if (_isUploading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(color: accentRed),
                ),
              if (_attachments.isEmpty)
                Text(
                  'No attachments yet.',
                  style: TextStyle(color: textColor.withValues(alpha: 0.65)),
                ),
              if (_attachments.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _attachments.asMap().entries.map((
                    MapEntry<int, _TaskAttachment> entry,
                  ) {
                    final int index = entry.key;
                    final _TaskAttachment attachment = entry.value;
                    return InputChip(
                      avatar: Icon(attachment.type.icon, size: 16),
                      label: SizedBox(
                        width: 190,
                        child: Text(
                          attachment.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onDeleted: () {
                        setState(() {
                          final List<_TaskAttachment> next =
                              List<_TaskAttachment>.from(_attachments);
                          next.removeAt(index);
                          _attachments = next;
                        });
                      },
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorSectionHeader extends StatelessWidget {
  const _EditorSectionHeader({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const Spacer(),
        action,
      ],
    );
  }
}

class _TaskEditorResult {
  const _TaskEditorResult.save({
    required this.title,
    required this.details,
    required this.isCompleted,
    required this.dueAt,
    required this.reminderAt,
    required this.links,
    required this.attachments,
    required this.subtasks,
  }) : deleted = false;

  const _TaskEditorResult.delete()
    : title = '',
      details = '',
      isCompleted = false,
      dueAt = null,
      reminderAt = null,
      links = const <String>[],
      attachments = const <_TaskAttachment>[],
      subtasks = const <_TaskSubtask>[],
      deleted = true;

  final String title;
  final String details;
  final bool isCompleted;
  final DateTime? dueAt;
  final DateTime? reminderAt;
  final List<String> links;
  final List<_TaskAttachment> attachments;
  final List<_TaskSubtask> subtasks;
  final bool deleted;
}

class _TaskItem {
  const _TaskItem({
    required this.id,
    required this.title,
    required this.details,
    required this.isCompleted,
    required this.dueAt,
    required this.reminderAt,
    required this.links,
    required this.attachments,
    required this.subtasks,
    required this.updatedAt,
  });

  factory _TaskItem.fromMap(Map<String, dynamic> map) {
    final dynamic rawLinks = map['links'];
    final dynamic rawAttachments = map['attachments'];
    final dynamic rawSubtasks = map['subtasks'];

    return _TaskItem(
      id: map['id'].toString(),
      title: (map['title'] as String? ?? '').trim(),
      details: map['details'] as String? ?? '',
      isCompleted: map['is_completed'] == true,
      dueAt: DateTime.tryParse(map['due_at']?.toString() ?? '')?.toLocal(),
      reminderAt: DateTime.tryParse(
        map['reminder_at']?.toString() ?? '',
      )?.toLocal(),
      links: rawLinks is List
          ? rawLinks.map((dynamic value) => value.toString()).toList()
          : const <String>[],
      attachments: rawAttachments is List
          ? rawAttachments
                .map(_TaskAttachment.fromDynamic)
                .whereType<_TaskAttachment>()
                .toList(growable: false)
          : const <_TaskAttachment>[],
      subtasks: rawSubtasks is List
          ? rawSubtasks
                .map(_TaskSubtask.fromDynamic)
                .whereType<_TaskSubtask>()
                .toList(growable: false)
          : const <_TaskSubtask>[],
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  final String id;
  final String title;
  final String details;
  final bool isCompleted;
  final DateTime? dueAt;
  final DateTime? reminderAt;
  final List<String> links;
  final List<_TaskAttachment> attachments;
  final List<_TaskSubtask> subtasks;
  final DateTime updatedAt;
}

class _TaskSubtask {
  const _TaskSubtask({required this.title, required this.completed});

  static _TaskSubtask? fromDynamic(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final String title = (raw['title'] ?? '').toString().trim();
    if (title.isEmpty) {
      return null;
    }
    return _TaskSubtask(title: title, completed: raw['completed'] == true);
  }

  _TaskSubtask copyWith({String? title, bool? completed}) {
    return _TaskSubtask(
      title: title ?? this.title,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'title': title, 'completed': completed};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _TaskSubtask &&
        other.title == title &&
        other.completed == completed;
  }

  @override
  int get hashCode => Object.hash(title, completed);

  final String title;
  final bool completed;
}

enum _TaskAttachmentType { image, video }

extension _TaskAttachmentTypeX on _TaskAttachmentType {
  String get storageValue => switch (this) {
    _TaskAttachmentType.image => 'image',
    _TaskAttachmentType.video => 'video',
  };

  IconData get icon => switch (this) {
    _TaskAttachmentType.image => Icons.photo_outlined,
    _TaskAttachmentType.video => Icons.videocam_outlined,
  };
}

_TaskAttachmentType _taskAttachmentTypeFromStorage(String value) {
  switch (value) {
    case 'video':
      return _TaskAttachmentType.video;
    case 'image':
    default:
      return _TaskAttachmentType.image;
  }
}

class _TaskAttachment {
  const _TaskAttachment({
    required this.type,
    required this.storagePath,
    required this.name,
    this.contentType,
  });

  static _TaskAttachment? fromDynamic(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final String path = (raw['storage_path'] ?? raw['path'] ?? '')
        .toString()
        .trim();
    final String name = (raw['name'] ?? '').toString().trim();
    if (path.isEmpty) {
      return null;
    }

    return _TaskAttachment(
      type: _taskAttachmentTypeFromStorage((raw['type'] ?? '').toString()),
      storagePath: path,
      name: name.isEmpty ? path.split('/').last : name,
      contentType: (raw['content_type'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['content_type'] ?? '').toString().trim(),
    );
  }

  String get displayName => name;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.storageValue,
      'storage_path': storagePath,
      'name': name,
      'content_type': contentType,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _TaskAttachment &&
        other.type == type &&
        other.storagePath == storagePath &&
        other.name == name &&
        other.contentType == contentType;
  }

  @override
  int get hashCode => Object.hash(type, storagePath, name, contentType);

  final _TaskAttachmentType type;
  final String storagePath;
  final String name;
  final String? contentType;
}
