import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageCleanupQueue {
  static const String _key = 'foxy.storage_cleanup_queue.v1';

  static Future<void> enqueue({
    required String bucket,
    required List<String> paths,
  }) async {
    if (paths.isEmpty) {
      return;
    }

    final List<_CleanupJob> jobs = await _readJobs();
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Set<String> seen = jobs
        .map((_CleanupJob job) => '${job.bucket}|${job.path}')
        .toSet();

    for (final String path in paths) {
      final String trimmed = path.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final String dedupeKey = '$bucket|$trimmed';
      if (seen.contains(dedupeKey)) {
        continue;
      }
      jobs.add(
        _CleanupJob(
          bucket: bucket,
          path: trimmed,
          retries: 0,
          nextAttemptAtMs: now,
        ),
      );
      seen.add(dedupeKey);
    }

    await _writeJobs(jobs);
  }

  static Future<void> drain(SupabaseClient client) async {
    final List<_CleanupJob> jobs = await _readJobs();
    if (jobs.isEmpty) {
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<_CleanupJob> pending = <_CleanupJob>[];

    for (final _CleanupJob job in jobs) {
      if (job.nextAttemptAtMs > now) {
        pending.add(job);
        continue;
      }

      try {
        await client.storage.from(job.bucket).remove(<String>[job.path]);
      } catch (_) {
        pending.add(job.retry(now));
      }
    }

    await _writeJobs(pending);
  }

  static Future<List<_CleanupJob>> _readJobs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) {
      return <_CleanupJob>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <_CleanupJob>[];
      }
      return decoded
          .map(_CleanupJob.fromDynamic)
          .whereType<_CleanupJob>()
          .toList(growable: false);
    } catch (_) {
      return <_CleanupJob>[];
    }
  }

  static Future<void> _writeJobs(List<_CleanupJob> jobs) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (jobs.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
      _key,
      jsonEncode(jobs.map((_CleanupJob job) => job.toMap()).toList()),
    );
  }
}

class _CleanupJob {
  const _CleanupJob({
    required this.bucket,
    required this.path,
    required this.retries,
    required this.nextAttemptAtMs,
  });

  static _CleanupJob? fromDynamic(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final String bucket = (raw['bucket'] ?? '').toString().trim();
    final String path = (raw['path'] ?? '').toString().trim();
    if (bucket.isEmpty || path.isEmpty) {
      return null;
    }
    final int retries = int.tryParse((raw['retries'] ?? '0').toString()) ?? 0;
    final int next =
        int.tryParse((raw['next_attempt_at_ms'] ?? '0').toString()) ?? 0;

    return _CleanupJob(
      bucket: bucket,
      path: path,
      retries: retries < 0 ? 0 : retries,
      nextAttemptAtMs: next,
    );
  }

  _CleanupJob retry(int nowMs) {
    final int nextRetries = retries + 1;
    final int delaySeconds = 1 << (nextRetries.clamp(0, 10));
    return _CleanupJob(
      bucket: bucket,
      path: path,
      retries: nextRetries,
      nextAttemptAtMs: nowMs + (delaySeconds * 1000),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'bucket': bucket,
      'path': path,
      'retries': retries,
      'next_attempt_at_ms': nextAttemptAtMs,
    };
  }

  final String bucket;
  final String path;
  final int retries;
  final int nextAttemptAtMs;
}
