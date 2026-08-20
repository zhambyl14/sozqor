// lib/features/shell/root_shell.dart
//
// The five tabs and the floating navigation bar.
//
// 4.0 moves "Ойнау" into the middle and lifts it out of the bar. Starting a
// round is the single action the app wants most, so it gets the one shape on
// the bar that is impossible to miss — everything else is a quiet pill.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../providers.dart';
import '../../services/push_service.dart';
import '../arena/arena_screen.dart';
import '../home/home_screen.dart';
import '../play/play_hub_screen.dart';
import '../profile/profile_screen.dart';
import '../words/word_bank_screen.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  static const _rawScreens = <Widget>[
    HomeScreen(),
    ArenaScreen(),
    PlayHubScreen(),
    WordBankScreen(),
    ProfileScreen(),
  ];

  /// Tapping a notification should land on the thing it was about.
  static const _tabByName = <String, SqTab>{
    'home': SqTab.home,
    'arena': SqTab.arena,
    'play': SqTab.play,
    'words': SqTab.words,
    'me': SqTab.me,
  };

  /// [IndexedStack] keeps every tab mounted at once, including the four that
  /// are off-screen. None of the tab screens passes its own
  /// [ScrollController], so without this they would all bind to the single
  /// [PrimaryScrollController] the route provides — four Scrollables sharing
  /// one controller, which is what made a fast fling on one tab occasionally
  /// pick up another tab's in-flight scroll simulation and never settle. Each
  /// tab gets its own controller so their scroll positions can never cross.
  late final _scrollControllers =
      List.generate(_rawScreens.length, (_) => ScrollController());
  late final _screens = [
    for (var i = 0; i < _rawScreens.length; i++)
      PrimaryScrollController(
        controller: _scrollControllers[i],
        child: _rawScreens[i],
      ),
  ];

  @override
  void initState() {
    super.initState();
    PushService.instance.onOpen = _openFromPush;
    // A tap that arrived while the app was still starting.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => PushService.instance.drainPendingOpen());
  }

  @override
  void dispose() {
    if (PushService.instance.onOpen == _openFromPush) {
      PushService.instance.onOpen = null;
    }
    for (final c in _scrollControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _openFromPush(Map<String, dynamic> data) {
    if (!mounted) return;
    final tab = _tabByName[(data['tab'] ?? '').toString()];
    if (tab == null) return;
    ref.read(tabProvider.notifier).state = tab.index;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final index = ref.watch(tabProvider).clamp(0, _screens.length - 1);
    final d = isDark(context);
    final hasInvites =
        (ref.watch(pendingInvitesProvider).value ?? const []).isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg(d),
      extendBody: true,
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: _NavBar(
        index: index,
        hasInvites: hasInvites,
        onTap: (i) => ref.read(tabProvider.notifier).state = i,
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final bool hasInvites;
  final ValueChanged<int> onTap;
  const _NavBar({required this.index, required this.hasInvites, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        // The raised centre button pokes 14pt above the bar, so the row needs
        // headroom and a Stack that does not clip.
        child: SizedBox(
          height: 84,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.glass(d),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.border(d)),
                  boxShadow: [BoxShadow(
                    color: AppColors.shadow(d, alpha: 0.18),
                    blurRadius: 26, offset: const Offset(0, 10))],
                ),
                child: Row(
                  children: [
                    for (final tab in kTabOrder)
                      Expanded(
                        child: _NavItem(
                          tab: tab,
                          selected: tab.index == index,
                          raised: tab == SqTab.play,
                          badge: tab == SqTab.arena && hasInvites,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTap(tab.index);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final SqTab tab;
  final bool selected, raised;
  final bool badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.tab,
    required this.selected,
    required this.raised,
    this.badge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final activeInk = d ? AppColors.primary : AppColors.primaryDeep;
    final idleInk = d ? AppColors.text3D : const Color(0xFFA9A5BC);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (raised)
              Transform.translate(
                offset: const Offset(0, -14),
                child: Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      const BoxShadow(
                        color: AppColors.primaryDeep,
                        offset: Offset(0, 5), blurRadius: 0),
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.55),
                        blurRadius: 22, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Icon(tab.iconOn, size: 25, color: Colors.white),
                ),
              )
            else
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: 40, height: 30,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.soft(AppColors.primary, d)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      selected ? tab.iconOn : tab.iconOff,
                      size: 21,
                      color: selected ? activeInk : idleInk),
                  ),
                  if (badge) const Positioned(top: 2, right: 6, child: SqDot()),
                ],
              ),
            SizedBox(height: raised ? 0 : 3),
            Transform.translate(
              offset: Offset(0, raised ? -6 : 0),
              child: Text(tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                  color: raised || selected ? activeInk : idleInk)),
            ),
          ],
        ),
      ),
    );
  }
}
