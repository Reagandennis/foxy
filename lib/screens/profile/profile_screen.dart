import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/theme_mode_service.dart';
import '../../theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _nameController = TextEditingController();
  bool _savingProfile = false;

  User? get _user => _client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    final User? user = _user;
    final String existingName = (user?.userMetadata?['display_name'] ?? '')
        .toString()
        .trim();
    _nameController.text = existingName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) {
      return;
    }
    final String value = _nameController.text.trim();

    setState(() {
      _savingProfile = true;
    });

    try {
      await _client.auth.updateUser(
        UserAttributes(data: <String, dynamic>{'display_name': value}),
      );
      _showSnack('Profile updated.');
    } catch (_) {
      _showSnack('Could not update profile.');
    } finally {
      if (mounted) {
        setState(() {
          _savingProfile = false;
        });
      }
    }
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: textColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentRed, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = _user;
    final String email = user?.email?.trim() ?? 'No account email found';
    final String userId = user?.id ?? 'unknown';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          _sectionCard(
            title: 'Profile Settings',
            icon: Icons.person_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email: $email',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Display name',
                    labelStyle: TextStyle(
                      color: textColor.withValues(alpha: 0.7),
                    ),
                    filled: true,
                    fillColor: inputFillColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: textColor.withValues(alpha: 0.16),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: textColor.withValues(alpha: 0.16),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentRed,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _savingProfile ? null : _saveProfile,
                  icon: _savingProfile
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Save profile'),
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'Settings',
            icon: Icons.settings_rounded,
            child: Column(
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeModeService.notifier,
                  builder:
                      (BuildContext context, ThemeMode mode, Widget? child) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Appearance',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.78),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                foregroundColor: textColor,
                                selectedForegroundColor: Colors.white,
                                selectedBackgroundColor: accentRed,
                              ),
                              segments: const <ButtonSegment<ThemeMode>>[
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.light,
                                  label: Text('Light'),
                                  icon: Icon(Icons.light_mode_rounded),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.dark,
                                  label: Text('Dark'),
                                  icon: Icon(Icons.dark_mode_rounded),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.system,
                                  label: Text('System'),
                                  icon: Icon(Icons.settings_suggest_rounded),
                                ),
                              ],
                              selected: <ThemeMode>{mode},
                              onSelectionChanged: (Set<ThemeMode> selected) {
                                if (selected.isNotEmpty) {
                                  ThemeModeService.setMode(selected.first);
                                }
                              },
                            ),
                          ],
                        );
                      },
                ),
              ],
            ),
          ),
          _sectionCard(
            title: 'About',
            icon: Icons.info_outline_rounded,
            child: Text(
              'Foxy helps you capture notes quickly, plan tasks clearly, and keep momentum daily.',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.82),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _sectionCard(
            title: 'Legal',
            icon: Icons.gavel_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your data is stored under your account with Supabase row-level security and per-user storage policies.',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.82),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can permanently delete your account and data from the side menu.',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.74),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'User ID: $userId',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
