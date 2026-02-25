import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../auth/auth_screens.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.supabaseReady});

  final bool supabaseReady;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<_SlideData> _slides = const [
    _SlideData(
      title: 'Meet Foxy',
      description:
          'Your simple productivity fox that helps you focus on what matters most today.',
      icon: Icons.pets_rounded,
      accent: accentGold,
    ),
    _SlideData(
      title: 'Plan Tiny Wins',
      description:
          'Break big work into short, clear tasks and keep moving with less friction.',
      icon: Icons.checklist_rounded,
      accent: accentRed,
    ),
    _SlideData(
      title: 'Finish Strong',
      description:
          'Track your momentum, celebrate progress, and let Foxy keep your day on track.',
      icon: Icons.bolt_rounded,
      accent: accentGold,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(supabaseReady: widget.supabaseReady),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLastPage = _currentIndex == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _slides.length,
              onPageChanged: (int index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (BuildContext context, int index) {
                return _OnboardingSlide(slide: _slides[index]);
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLastPage)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: SizedBox(
                        width: 220,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _goToLogin,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: accentRed,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: 0.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text('Get started'),
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(
                      _slides.length,
                      (int index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: _currentIndex == index ? 26 : 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _currentIndex == index
                              ? accentRed
                              : accentGold,
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.slide});

  final _SlideData slide;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _HeroBadge(icon: slide.icon, accent: slide.accent),
          const SizedBox(height: 44),
          Text(
            slide.title,
            style: textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            slide.description,
            style: textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.16),
          ),
        ),
        Container(
          width: 166,
          height: 166,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: textColor.withValues(alpha: 0.12)),
            color: Colors.white.withValues(alpha: 0.66),
          ),
          child: Icon(icon, size: 82, color: accent),
        ),
      ],
    );
  }
}

class _SlideData {
  const _SlideData({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
}
