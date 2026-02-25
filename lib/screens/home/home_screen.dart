import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_screens.dart';
import '../calendar/calendar_screen.dart';
import '../tasks/tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SupabaseClient _client = Supabase.instance.client;
  _HomeSection _activeSection = _HomeSection.notes;
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  User? get _currentUser => _client.auth.currentUser;

  Stream<List<_NoteItem>> _notesStream() {
    final User? user = _currentUser;
    if (user == null) {
      return Stream<List<_NoteItem>>.value(const <_NoteItem>[]);
    }

    return _client
        .from('notes')
        .stream(primaryKey: <String>['id'])
        .eq('user_id', user.id)
        .order('updated_at', ascending: false)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map((_NoteItem.fromMap)).toList()..sort(_compareNotes),
        );
  }

  int _compareNotes(_NoteItem a, _NoteItem b) {
    if (a.isPinned != b.isPinned) {
      return a.isPinned ? -1 : 1;
    }
    return b.updatedAt.compareTo(a.updatedAt);
  }

  bool _clipsEqual(List<_NoteClip> a, List<_NoteClip> b) {
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

  String get _clipsBucket => SupabaseConfig.clipsBucket;

  List<_NoteClip> _removedClips({
    required List<_NoteClip> previous,
    required List<_NoteClip> next,
  }) {
    final Set<String> keepPaths = next
        .map((_NoteClip clip) => clip.storagePath)
        .where((String path) => path.isNotEmpty)
        .toSet();

    return previous
        .where((_NoteClip clip) {
          if (clip.storagePath.isEmpty) {
            return false;
          }
          return !keepPaths.contains(clip.storagePath);
        })
        .toList(growable: false);
  }

  Future<void> _deleteClipFiles(List<_NoteClip> clips) async {
    final List<String> paths = clips
        .map((_NoteClip clip) => clip.storagePath)
        .where((String path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) {
      return;
    }

    try {
      await _client.storage.from(_clipsBucket).remove(paths);
    } catch (_) {
      // Keep note actions resilient if storage cleanup fails.
    }
  }

  List<_NoteItem> _applySearch(List<_NoteItem> notes) {
    if (_searchQuery.isEmpty) {
      return notes;
    }

    final String query = _searchQuery.toLowerCase();
    return notes.where((_NoteItem note) {
      return note.title.toLowerCase().contains(query) ||
          note.searchableBody.toLowerCase().contains(query) ||
          note.clips.any(
            (_NoteClip clip) => clip.searchText.toLowerCase().contains(query),
          );
    }).toList();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _switchSection(_HomeSection section) {
    setState(() {
      _activeSection = section;
      if (_activeSection != _HomeSection.notes) {
        _isSearching = false;
        _searchController.clear();
        _searchQuery = '';
      }
    });
    Navigator.of(context).pop();
  }

  Future<void> _openNoteEditor({_NoteItem? note}) async {
    final _NoteEditorResult? result = await Navigator.of(context)
        .push<_NoteEditorResult>(
          MaterialPageRoute(builder: (_) => _NoteEditorScreen(note: note)),
        );

    if (result == null) {
      return;
    }

    if (result.deleted) {
      if (note == null) {
        return;
      }
      await _deleteNote(note.id, clips: note.clips);
      return;
    }

    final String title = result.title.trimRight();
    final String body = result.body;

    if (note == null) {
      if (title.isEmpty &&
          body.isEmpty &&
          result.clips.isEmpty &&
          !result.isPinned) {
        return;
      }
      await _createNote(
        title: title,
        body: body,
        isPinned: result.isPinned,
        clips: result.clips,
      );
      return;
    }

    final bool advancedChanged =
        note.isPinned != result.isPinned ||
        !_clipsEqual(note.clips, result.clips);

    final bool updated = await _updateNote(
      noteId: note.id,
      title: title,
      body: body,
      isPinned: advancedChanged ? result.isPinned : null,
      clips: advancedChanged ? result.clips : null,
    );

    if (advancedChanged && updated) {
      await _deleteClipFiles(
        _removedClips(previous: note.clips, next: result.clips),
      );
    }
  }

  Future<void> _createNote({
    required String title,
    required String body,
    required bool isPinned,
    required List<_NoteClip> clips,
  }) async {
    final User? user = _currentUser;
    if (user == null) {
      _showSnack('Session ended. Log in again.');
      return;
    }

    final bool includesAdvancedFields = isPinned || clips.isNotEmpty;
    final Map<String, dynamic> payload = <String, dynamic>{
      'user_id': user.id,
      'title': title,
      'body': body,
    };
    if (includesAdvancedFields) {
      payload['is_pinned'] = isPinned;
      payload['clips'] = clips.map((_NoteClip clip) => clip.toMap()).toList();
    }

    try {
      await _client.from('notes').insert(payload);
      _showSnack('Note created.');
    } catch (_) {
      _showSnack(
        includesAdvancedFields
            ? 'Could not save clips or pin. Run latest supabase_notes_setup.sql.'
            : 'Could not create note. Check your Supabase table setup.',
      );
    }
  }

  Future<bool> _updateNote({
    required String noteId,
    required String title,
    required String body,
    bool? isPinned,
    List<_NoteClip>? clips,
  }) async {
    final User? user = _currentUser;
    if (user == null) {
      _showSnack('Session ended. Log in again.');
      return false;
    }

    final bool includesAdvancedFields = isPinned != null || clips != null;
    final Map<String, dynamic> payload = <String, dynamic>{
      'title': title,
      'body': body,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (isPinned != null) {
      payload['is_pinned'] = isPinned;
    }
    if (clips != null) {
      payload['clips'] = clips.map((_NoteClip clip) => clip.toMap()).toList();
    }

    try {
      await _client
          .from('notes')
          .update(payload)
          .eq('id', noteId)
          .eq('user_id', user.id);
      _showSnack('Note updated.');
      return true;
    } catch (_) {
      _showSnack(
        includesAdvancedFields
            ? 'Could not save clips or pin. Run latest supabase_notes_setup.sql.'
            : 'Could not update note. Check your connection and try again.',
      );
      return false;
    }
  }

  Future<void> _togglePin(_NoteItem note) async {
    final User? user = _currentUser;
    if (user == null) {
      _showSnack('Session ended. Log in again.');
      return;
    }

    final bool nextPinned = !note.isPinned;
    try {
      await _client
          .from('notes')
          .update(<String, dynamic>{
            'is_pinned': nextPinned,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', note.id)
          .eq('user_id', user.id);
      _showSnack(nextPinned ? 'Note pinned.' : 'Note unpinned.');
    } catch (_) {
      _showSnack(
        'Could not update pin. Run latest supabase_notes_setup.sql and try again.',
      );
    }
  }

  Future<void> _deleteNote(
    String noteId, {
    List<_NoteClip> clips = const <_NoteClip>[],
  }) async {
    final User? user = _currentUser;
    if (user == null) {
      _showSnack('Session ended. Log in again.');
      return;
    }

    try {
      await _client
          .from('notes')
          .delete()
          .eq('id', noteId)
          .eq('user_id', user.id);
      await _deleteClipFiles(clips);
      _showSnack('Note deleted.');
    } catch (_) {
      _showSnack('Could not delete note. Check your connection and try again.');
    }
  }

  String _formatStamp(DateTime dateTime) {
    final DateTime now = DateTime.now();
    if (dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day) {
      final String hh = dateTime.hour.toString().padLeft(2, '0');
      final String mm = dateTime.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    return '${dateTime.month}/${dateTime.day}';
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _logOut() async {
    await _client.auth.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen(supabaseReady: true)),
      (route) => false,
    );
  }

  Widget _buildNotesBody() {
    return SafeArea(
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            height: _isSearching ? 78 : 0,
            padding: EdgeInsets.fromLTRB(16, _isSearching ? 10 : 0, 16, 10),
            child: _isSearching
                ? TextField(
                    controller: _searchController,
                    onChanged: (String value) {
                      setState(() {
                        _searchQuery = value.trim();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search notes...',
                      hintStyle: TextStyle(
                        color: textColor.withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: textColor,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: textColor.withValues(alpha: 0.12),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: accentRed,
                          width: 1.5,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: StreamBuilder<List<_NoteItem>>(
              stream: _notesStream(),
              builder: (BuildContext context, AsyncSnapshot<List<_NoteItem>> snapshot) {
                if (snapshot.hasError) {
                  return const _EmptyNotesState(
                    text:
                        'Unable to load notes. Verify Supabase table and RLS policies.',
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: accentRed),
                  );
                }

                final List<_NoteItem> notes = snapshot.data!;
                final List<_NoteItem> visibleNotes = _applySearch(notes);

                if (visibleNotes.isEmpty) {
                  return _EmptyNotesState(
                    text: notes.isEmpty
                        ? 'No notes yet. Tap the pencil to create your first note.'
                        : 'No notes match your search.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: visibleNotes.length,
                  separatorBuilder: (_, index) => Divider(
                    height: 1,
                    color: textColor.withValues(alpha: 0.12),
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final _NoteItem note = visibleNotes[index];
                    final String preview = note.previewText;

                    return Dismissible(
                      key: ValueKey<String>(note.id),
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
                        final bool? shouldDelete = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              backgroundColor: appBackground,
                              title: const Text('Delete note?'),
                              content: const Text(
                                'This action cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(false);
                                  },
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(true);
                                  },
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: accentRed),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                        return shouldDelete == true;
                      },
                      onDismissed: (_) =>
                          _deleteNote(note.id, clips: note.clips),
                      child: ListTile(
                        onTap: () => _openNoteEditor(note: note),
                        onLongPress: () => _togglePin(note),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        title: Text(
                          note.title.isEmpty ? 'Untitled note' : note.title,
                          style: const TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: preview.isEmpty
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  preview,
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.78),
                                    fontSize: 14,
                                    height: 1.32,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        trailing: SizedBox(
                          width: 72,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: () => _togglePin(note),
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 26,
                                  minHeight: 26,
                                ),
                                icon: Icon(
                                  note.isPinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  color: note.isPinned
                                      ? accentRed
                                      : textColor.withValues(alpha: 0.45),
                                ),
                              ),
                              Text(
                                _formatStamp(note.updatedAt),
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.52),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isNotes = _activeSection == _HomeSection.notes;

    return Scaffold(
      drawer: Drawer(
        backgroundColor: appBackground,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const ListTile(
                leading: Icon(Icons.pets_rounded, color: accentRed),
                title: Text(
                  'Foxy',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                subtitle: Text(
                  'Simple productivity notes',
                  style: TextStyle(color: textColor),
                ),
              ),
              const Divider(height: 28),
              ListTile(
                leading: const _DrawerFoxIcon(
                  accent: accentRed,
                  symbol: Icons.sticky_note_2_rounded,
                ),
                title: const Text(
                  'Notes',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: _activeSection == _HomeSection.notes,
                selectedTileColor: accentRed.withValues(alpha: 0.1),
                onTap: () => _switchSection(_HomeSection.notes),
              ),
              ListTile(
                leading: const _DrawerFoxIcon(
                  accent: accentGold,
                  symbol: Icons.checklist_rounded,
                ),
                title: const Text(
                  'Tasks',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: _activeSection == _HomeSection.tasks,
                selectedTileColor: accentRed.withValues(alpha: 0.1),
                onTap: () => _switchSection(_HomeSection.tasks),
              ),
              ListTile(
                leading: const _DrawerFoxIcon(
                  accent: accentRed,
                  symbol: Icons.calendar_month_rounded,
                ),
                title: const Text(
                  'Calendar',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: _activeSection == _HomeSection.calendar,
                selectedTileColor: accentRed.withValues(alpha: 0.1),
                onTap: () => _switchSection(_HomeSection.calendar),
              ),
              const Divider(height: 28),
              ListTile(
                leading: const _DrawerFoxIcon(
                  accent: accentGold,
                  symbol: Icons.logout_rounded,
                ),
                title: const Text(
                  'Log out',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _logOut,
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          _activeSection.label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: textColor),
            );
          },
        ),
        actions: isNotes
            ? [
                IconButton(
                  onPressed: _toggleSearch,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return RotationTransition(
                            turns: animation,
                            child: child,
                          );
                        },
                    child: Icon(
                      _isSearching ? Icons.close_rounded : Icons.search_rounded,
                      key: ValueKey<bool>(_isSearching),
                      color: textColor,
                    ),
                  ),
                ),
              ]
            : <Widget>[],
      ),
      body: switch (_activeSection) {
        _HomeSection.notes => _buildNotesBody(),
        _HomeSection.tasks => const TasksScreen(),
        _HomeSection.calendar => const CalendarScreen(),
      },
      floatingActionButton: isNotes
          ? FloatingActionButton(
              onPressed: () => _openNoteEditor(),
              backgroundColor: accentRed,
              foregroundColor: Colors.white,
              child: const Icon(Icons.edit_rounded),
            )
          : null,
    );
  }
}

class _EmptyNotesState extends StatelessWidget {
  const _EmptyNotesState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

enum _HomeSection { notes, tasks, calendar }

extension _HomeSectionX on _HomeSection {
  String get label => switch (this) {
    _HomeSection.notes => 'Notes',
    _HomeSection.tasks => 'Tasks',
    _HomeSection.calendar => 'Calendar',
  };
}

class _DrawerFoxIcon extends StatelessWidget {
  const _DrawerFoxIcon({required this.accent, required this.symbol});

  final Color accent;
  final IconData symbol;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
              border: Border.all(color: textColor.withValues(alpha: 0.12)),
            ),
            child: Icon(Icons.pets_rounded, size: 18, color: accent),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: appBackground,
                border: Border.all(color: textColor.withValues(alpha: 0.16)),
              ),
              child: Icon(symbol, size: 9, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteEditorScreen extends StatefulWidget {
  const _NoteEditorScreen({this.note});

  final _NoteItem? note;

  @override
  State<_NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<_NoteEditorScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final Map<String, Future<String?>> _photoPreviewUrlCache =
      <String, Future<String?>>{};
  late final TextEditingController _titleController;
  late final quill.QuillController _bodyController;
  late final FocusNode _bodyFocusNode;
  late final ScrollController _bodyScrollController;
  late final String _initialTitle;
  late final String _initialBody;
  late final String _initialBodySignature;
  late final bool _initialPinned;
  late final List<_NoteClip> _initialClips;
  late bool _isPinned;
  late List<_NoteClip> _clips;
  bool _isUploadingClip = false;

  @override
  void initState() {
    super.initState();
    _initialTitle = widget.note?.title ?? '';
    _initialBody = widget.note?.body ?? '';
    _initialPinned = widget.note?.isPinned ?? false;
    _initialClips = List<_NoteClip>.from(
      widget.note?.clips ?? const <_NoteClip>[],
    );
    _isPinned = _initialPinned;
    _clips = List<_NoteClip>.from(_initialClips);
    _titleController = TextEditingController(text: _initialTitle);
    _bodyController = _NoteBodyCodec.controllerFromStorage(_initialBody);
    _bodyFocusNode = FocusNode();
    _bodyScrollController = ScrollController();
    _initialBodySignature = _NoteBodyCodec.canonicalDeltaJsonFromStorage(
      _initialBody,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  bool _clipsEqual(List<_NoteClip> a, List<_NoteClip> b) {
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

  void _saveAndExit() {
    if (_isUploadingClip) {
      _showSnack('Wait for upload to finish.');
      return;
    }

    final String title = _titleController.text.trimRight();
    final String body = _NoteBodyCodec.encodeForStorage(
      _bodyController.document,
    );
    final String currentBodySignature =
        _NoteBodyCodec.canonicalDeltaJsonFromDocument(_bodyController.document);

    if (title == _initialTitle &&
        currentBodySignature == _initialBodySignature &&
        _isPinned == _initialPinned &&
        _clipsEqual(_clips, _initialClips)) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pop(
      _NoteEditorResult.save(
        title: title,
        body: body,
        isPinned: _isPinned,
        clips: _clips,
      ),
    );
  }

  String get _clipsBucket => SupabaseConfig.clipsBucket;

  void _appendClip(_NoteClip clip) {
    setState(() {
      _clips = <_NoteClip>[..._clips, clip];
    });
  }

  Future<String?> _photoPreviewUrl(_NoteClip clip) {
    if (clip.type != _NoteClipType.photo || clip.storagePath.isEmpty) {
      return Future<String?>.value(null);
    }

    return _photoPreviewUrlCache.putIfAbsent(clip.storagePath, () async {
      try {
        return await _client.storage
            .from(_clipsBucket)
            .createSignedUrl(clip.storagePath, 60 * 60);
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> _showPhotoPreview(_NoteClip clip) async {
    if (clip.type != _NoteClipType.photo) {
      _showSnack('Preview is available for photo clips.');
      return;
    }

    final String? signedUrl = await _photoPreviewUrl(clip);
    if (!mounted) {
      return;
    }
    if (signedUrl == null) {
      _showSnack('Could not load photo preview.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: appBackground,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440, maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  signedUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, stackTrace) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Could not render image preview.'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _safeExtension(String value, {required String fallback}) {
    final String clean = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (clean.isEmpty) {
      return fallback;
    }
    return clean;
  }

  String _extensionFromName(String name, {required String fallback}) {
    final int dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) {
      return fallback;
    }
    return _safeExtension(name.substring(dotIndex + 1), fallback: fallback);
  }

  String _contentTypeFor(_NoteClipType type, String extension) {
    if (type == _NoteClipType.photo) {
      switch (extension) {
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

    if (type == _NoteClipType.video) {
      switch (extension) {
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

    return 'text/html; charset=utf-8';
  }

  String _rawUploadError(Object error) {
    if (error is StorageException) {
      return error.message;
    }
    return error.toString();
  }

  String _friendlyUploadError({
    required Object error,
    required _NoteClipType type,
  }) {
    final String raw = _rawUploadError(error);
    final String lower = raw.toLowerCase();
    if (lower.contains('bucket')) {
      return 'Upload failed: bucket "$_clipsBucket" is missing or inaccessible.';
    }
    if (lower.contains('row-level security') ||
        lower.contains('permission') ||
        lower.contains('policy') ||
        lower.contains('not authorized') ||
        lower.contains('unauthorized')) {
      return 'Upload denied by storage policy. Run latest supabase_notes_setup.sql.';
    }
    return 'Could not upload ${type.label.toLowerCase()}: $raw';
  }

  Future<_NoteClip> _uploadClipBytes({
    required _NoteClipType type,
    required Uint8List bytes,
    required String extension,
    required String contentType,
    required String name,
    String? sourceUrl,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Session ended. Log in again.');
    }

    final String safeExt = _safeExtension(
      extension,
      fallback: type == _NoteClipType.webClip ? 'html' : 'bin',
    );
    final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final String path = '${user.id}/${type.storageValue}_$stamp.$safeExt';

    await _client.storage
        .from(_clipsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: contentType,
          ),
        );

    return _NoteClip(
      type: type,
      storagePath: path,
      contentType: contentType,
      sourceUrl: sourceUrl,
      name: name,
    );
  }

  Future<void> _addPickedMedia(_NoteClipType type) async {
    try {
      final List<String> photoExts = <String>[
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
      final List<String> allowed = type == _NoteClipType.photo
          ? photoExts
          : videoExts;

      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowed,
        withData: true,
        allowMultiple: false,
      );
      if (!mounted || picked == null || picked.files.isEmpty) {
        return;
      }
      final PlatformFile file = picked.files.first;
      final Uint8List? bytesRaw = file.bytes;
      if (bytesRaw == null || bytesRaw.isEmpty) {
        _showSnack('Could not read selected file.');
        return;
      }

      setState(() {
        _isUploadingClip = true;
      });
      final Uint8List bytes = bytesRaw;

      final String ext = _extensionFromName(
        file.name,
        fallback: type == _NoteClipType.photo ? 'jpg' : 'mp4',
      );
      final _NoteClip clip = await _uploadClipBytes(
        type: type,
        bytes: bytes,
        extension: ext,
        contentType: _contentTypeFor(type, ext),
        name: file.name,
      );
      if (!mounted) {
        return;
      }

      _appendClip(clip);
      _showSnack('${type.label} uploaded.');
    } catch (error) {
      _showSnack(_friendlyUploadError(error: error, type: type));
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingClip = false;
        });
      }
    }
  }

  Future<String?> _promptWebClipUrl() async {
    String draftValue = '';
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: appBackground,
          title: const Text('Clip webpage'),
          content: TextField(
            autofocus: true,
            keyboardType: TextInputType.url,
            onChanged: (String text) {
              draftValue = text;
            },
            decoration: const InputDecoration(
              hintText: 'https://example.com/article',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(draftValue.trim()),
              child: const Text('Clip'),
            ),
          ],
        );
      },
    );

    if (value == null || value.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      _showSnack('Enter a valid http/https URL.');
      return null;
    }
    return uri.toString();
  }

  Future<void> _addWebClip() async {
    final String? targetUrl = await _promptWebClipUrl();
    if (!mounted || targetUrl == null) {
      return;
    }

    try {
      setState(() {
        _isUploadingClip = true;
      });

      final Uri uri = Uri.parse(targetUrl);
      final http.Response response = await http
          .get(uri)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showSnack('Could not fetch webpage (${response.statusCode}).');
        return;
      }

      final Uint8List bytes = response.bodyBytes.isEmpty
          ? Uint8List.fromList(utf8.encode(response.body))
          : response.bodyBytes;
      if (bytes.isEmpty) {
        _showSnack('Webpage is empty.');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        _showSnack('Webpage too large to clip (max 5MB).');
        return;
      }

      final String contentType =
          response.headers['content-type'] ?? 'text/html; charset=utf-8';
      final _NoteClip clip = await _uploadClipBytes(
        type: _NoteClipType.webClip,
        bytes: bytes,
        extension: 'html',
        contentType: contentType,
        name: uri.host.isEmpty ? 'web-clip.html' : '${uri.host}.html',
        sourceUrl: targetUrl,
      );
      if (!mounted) {
        return;
      }

      _appendClip(clip);
      _showSnack('Web clip saved.');
    } catch (error) {
      _showSnack(
        _friendlyUploadError(error: error, type: _NoteClipType.webClip),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingClip = false;
        });
      }
    }
  }

  Future<void> _openInsertClipSheet() async {
    if (_isUploadingClip) {
      return;
    }

    final _NoteClipType? selected = await showModalBottomSheet<_NoteClipType>(
      context: context,
      backgroundColor: appBackground,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_outlined, color: textColor),
                title: const Text('Photo clip'),
                subtitle: const Text('Upload from gallery'),
                onTap: () => Navigator.of(context).pop(_NoteClipType.photo),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined, color: textColor),
                title: const Text('Video clip'),
                subtitle: const Text('Upload from gallery'),
                onTap: () => Navigator.of(context).pop(_NoteClipType.video),
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded, color: textColor),
                title: const Text('Web clipper'),
                subtitle: const Text('Save webpage snapshot'),
                onTap: () => Navigator.of(context).pop(_NoteClipType.webClip),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    switch (selected) {
      case _NoteClipType.photo:
      case _NoteClipType.video:
        await _addPickedMedia(selected);
        break;
      case _NoteClipType.webClip:
        await _addWebClip();
        break;
    }
  }

  void _removeClipAt(int index) {
    setState(() {
      final List<_NoteClip> next = List<_NoteClip>.from(_clips);
      final _NoteClip removed = next.removeAt(index);
      _clips = next;
      if (removed.storagePath.isNotEmpty) {
        _photoPreviewUrlCache.remove(removed.storagePath);
      }
    });
  }

  Future<void> _deleteNote() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: appBackground,
          title: const Text('Delete note?'),
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

    Navigator.of(context).pop(const _NoteEditorResult.delete());
  }

  @override
  Widget build(BuildContext context) {
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
          title: const Text('Note'),
          actions: [
            if (widget.note != null)
              IconButton(
                onPressed: _deleteNote,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            IconButton(
              onPressed: () {
                setState(() {
                  _isPinned = !_isPinned;
                });
              },
              icon: Icon(
                _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              ),
            ),
            IconButton(
              onPressed: _saveAndExit,
              icon: const Icon(Icons.check_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Title',
                    hintStyle: TextStyle(
                      color: textColor.withValues(alpha: 0.36),
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                    border: InputBorder.none,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _isUploadingClip ? null : _openInsertClipSheet,
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                      _isUploadingClip ? 'Uploading clip...' : 'Insert clip',
                    ),
                  ),
                ),
                if (_isUploadingClip)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(color: accentRed),
                  ),
                if (_clips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _clips.asMap().entries.map((
                        MapEntry<int, _NoteClip> entry,
                      ) {
                        final int index = entry.key;
                        final _NoteClip clip = entry.value;
                        return FutureBuilder<String?>(
                          future: _photoPreviewUrl(clip),
                          builder:
                              (
                                BuildContext context,
                                AsyncSnapshot<String?> snapshot,
                              ) {
                                final Widget avatar;
                                if (clip.type == _NoteClipType.photo &&
                                    snapshot.data != null) {
                                  avatar = ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      snapshot.data!,
                                      width: 24,
                                      height: 24,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, error, stackTrace) {
                                        return Icon(clip.type.icon, size: 16);
                                      },
                                    ),
                                  );
                                } else {
                                  avatar = Icon(clip.type.icon, size: 16);
                                }

                                return GestureDetector(
                                  onTap: clip.type == _NoteClipType.photo
                                      ? () => _showPhotoPreview(clip)
                                      : null,
                                  child: InputChip(
                                    avatar: avatar,
                                    label: SizedBox(
                                      width: 160,
                                      child: Text(
                                        clip.displayLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    onDeleted: () => _removeClipAt(index),
                                  ),
                                );
                              },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: textColor.withValues(alpha: 0.1)),
                  ),
                  child: quill.QuillSimpleToolbar(
                    controller: _bodyController,
                    config: const quill.QuillSimpleToolbarConfig(
                      showFontFamily: false,
                      showFontSize: false,
                      showColorButton: false,
                      showBackgroundColorButton: false,
                      showSearchButton: false,
                      showSubscript: false,
                      showSuperscript: false,
                      showDirection: false,
                      showLink: false,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: textColor.withValues(alpha: 0.1),
                      ),
                    ),
                    child: quill.QuillEditor(
                      controller: _bodyController,
                      focusNode: _bodyFocusNode,
                      scrollController: _bodyScrollController,
                      config: const quill.QuillEditorConfig(
                        placeholder: 'Start typing your note...',
                        expands: true,
                        padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteEditorResult {
  const _NoteEditorResult.save({
    required this.title,
    required this.body,
    required this.isPinned,
    required this.clips,
  }) : deleted = false;

  const _NoteEditorResult.delete()
    : title = '',
      body = '',
      isPinned = false,
      clips = const <_NoteClip>[],
      deleted = true;

  final String title;
  final String body;
  final bool isPinned;
  final List<_NoteClip> clips;
  final bool deleted;
}

class _NoteItem {
  const _NoteItem({
    required this.id,
    required this.title,
    required this.body,
    required this.plainBody,
    required this.isPinned,
    required this.clips,
    required this.updatedAt,
  });

  factory _NoteItem.fromMap(Map<String, dynamic> map) {
    final DateTime parsed =
        DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    final dynamic rawClips = map['clips'];
    final List<_NoteClip> parsedClips = rawClips is List
        ? rawClips
              .map(_NoteClip.fromDynamic)
              .whereType<_NoteClip>()
              .toList(growable: false)
        : const <_NoteClip>[];
    final String storedBody = map['body'] as String? ?? '';

    return _NoteItem(
      id: map['id'].toString(),
      title: map['title'] as String? ?? '',
      body: storedBody,
      plainBody: _NoteBodyCodec.plainTextFromStorage(storedBody),
      isPinned: map['is_pinned'] == true,
      clips: parsedClips,
      updatedAt: parsed,
    );
  }

  String get clipsSummary {
    if (clips.isEmpty) {
      return '';
    }

    final int photos = clips
        .where((_NoteClip clip) => clip.type == _NoteClipType.photo)
        .length;
    final int videos = clips
        .where((_NoteClip clip) => clip.type == _NoteClipType.video)
        .length;
    final int webClips = clips
        .where((_NoteClip clip) => clip.type == _NoteClipType.webClip)
        .length;

    final List<String> parts = <String>[];
    if (photos > 0) {
      parts.add('$photos photo');
    }
    if (videos > 0) {
      parts.add('$videos video');
    }
    if (webClips > 0) {
      parts.add('$webClips web');
    }

    return '${parts.join(' • ')} clip${clips.length == 1 ? '' : 's'}';
  }

  String get previewText {
    if (plainBody.trim().isNotEmpty && clipsSummary.isEmpty) {
      return plainBody;
    }
    if (plainBody.trim().isEmpty) {
      return clipsSummary;
    }
    return '$plainBody\n$clipsSummary';
  }

  String get searchableBody => plainBody;

  final String id;
  final String title;
  final String body;
  final String plainBody;
  final bool isPinned;
  final List<_NoteClip> clips;
  final DateTime updatedAt;
}

class _NoteBodyCodec {
  static const String _richPrefix = '__foxy_rich_v1__:';

  static quill.QuillController controllerFromStorage(String stored) {
    final quill.Document document = documentFromStorage(stored);
    final int cursor = document.length <= 1 ? 0 : document.length - 1;
    return quill.QuillController(
      document: document,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  static quill.Document documentFromStorage(String stored) {
    final String normalized = stored.replaceAll('\r\n', '\n');
    if (normalized.trim().isEmpty) {
      return quill.Document();
    }

    final String? richPayload = _richPayload(normalized);
    if (richPayload != null) {
      final quill.Document? richDoc = _documentFromJson(richPayload);
      if (richDoc != null) {
        return richDoc;
      }
    }

    final quill.Document plainDoc = quill.Document();
    plainDoc.insert(0, normalized);
    return plainDoc;
  }

  static String encodeForStorage(quill.Document document) {
    final String plain = document.toPlainText().trimRight();
    if (plain.isEmpty) {
      return '';
    }
    if (!_hasFormatting(document)) {
      return plain;
    }
    return '$_richPrefix${canonicalDeltaJsonFromDocument(document)}';
  }

  static String canonicalDeltaJsonFromStorage(String stored) {
    return canonicalDeltaJsonFromDocument(documentFromStorage(stored));
  }

  static String canonicalDeltaJsonFromDocument(quill.Document document) {
    return jsonEncode(document.toDelta().toJson());
  }

  static String plainTextFromStorage(String stored) {
    return documentFromStorage(stored).toPlainText().trimRight();
  }

  static bool _hasFormatting(quill.Document document) {
    final List<dynamic> ops = document.toDelta().toJson();
    for (final dynamic rawOp in ops) {
      if (rawOp is! Map) {
        continue;
      }
      final dynamic attributes = rawOp['attributes'];
      if (attributes is Map && attributes.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  static String? _richPayload(String body) {
    if (!body.startsWith(_richPrefix)) {
      return null;
    }
    final String payload = body.substring(_richPrefix.length).trim();
    if (payload.isEmpty) {
      return null;
    }
    return payload;
  }

  static quill.Document? _documentFromJson(String payload) {
    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is! List) {
        return null;
      }
      return quill.Document.fromJson(decoded.cast<Map<String, dynamic>>());
    } catch (_) {
      return null;
    }
  }
}

enum _NoteClipType { photo, video, webClip }

extension _NoteClipTypeX on _NoteClipType {
  String get label => switch (this) {
    _NoteClipType.photo => 'Photo clip',
    _NoteClipType.video => 'Video clip',
    _NoteClipType.webClip => 'Web clip',
  };

  String get storageValue => switch (this) {
    _NoteClipType.photo => 'photo',
    _NoteClipType.video => 'video',
    _NoteClipType.webClip => 'web_clip',
  };

  IconData get icon => switch (this) {
    _NoteClipType.photo => Icons.photo_outlined,
    _NoteClipType.video => Icons.videocam_outlined,
    _NoteClipType.webClip => Icons.link_rounded,
  };
}

_NoteClipType _clipTypeFromStorage(String value) {
  switch (value) {
    case 'photo':
      return _NoteClipType.photo;
    case 'video':
      return _NoteClipType.video;
    case 'web':
    case 'webclip':
    case 'web_clip':
      return _NoteClipType.webClip;
    default:
      return _NoteClipType.webClip;
  }
}

class _NoteClip {
  const _NoteClip({
    required this.type,
    required this.storagePath,
    required this.name,
    this.contentType,
    this.sourceUrl,
  });

  static _NoteClip? fromDynamic(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final String storagePath = (raw['storage_path'] ?? raw['path'] ?? '')
        .toString()
        .trim();
    final String sourceUrl = (raw['source_url'] ?? raw['url'] ?? '')
        .toString()
        .trim();
    final String name = (raw['name'] ?? raw['label'] ?? '').toString().trim();
    if (storagePath.isEmpty && sourceUrl.isEmpty) {
      return null;
    }

    final String resolvedName = name.isNotEmpty
        ? name
        : sourceUrl.isNotEmpty
        ? sourceUrl
        : storagePath.split('/').last;

    return _NoteClip(
      type: _clipTypeFromStorage((raw['type'] ?? '').toString()),
      storagePath: storagePath,
      name: resolvedName,
      contentType: (raw['content_type'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['content_type'] ?? '').toString().trim(),
      sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
    );
  }

  String get displayLabel => name;

  String get searchText {
    final String parts = <String>[name, storagePath, sourceUrl ?? ''].join(' ');
    return parts;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.storageValue,
      'storage_path': storagePath,
      'name': name,
      'content_type': contentType,
      'source_url': sourceUrl,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _NoteClip &&
        other.type == type &&
        other.storagePath == storagePath &&
        other.name == name &&
        other.contentType == contentType &&
        other.sourceUrl == sourceUrl;
  }

  @override
  int get hashCode =>
      Object.hash(type, storagePath, name, contentType, sourceUrl);

  final _NoteClipType type;
  final String storagePath;
  final String name;
  final String? contentType;
  final String? sourceUrl;
}
