class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String clipsBucket = String.fromEnvironment(
    'SUPABASE_CLIPS_BUCKET',
    defaultValue: 'note-clips',
  );
  static const String tasksBucket = String.fromEnvironment(
    'SUPABASE_TASKS_BUCKET',
    defaultValue: 'task-assets',
  );
  static const String resetRedirectTo = String.fromEnvironment(
    'SUPABASE_RESET_REDIRECT',
    defaultValue: 'foxy://reset-password/',
  );

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
