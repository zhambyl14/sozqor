// test/screens_build_test.dart
//
// Every screen has to survive being built.
//
// A widget that throws while building is replaced by an error widget, and the
// tab it lived in becomes a dead rectangle. That is how the arena shipped:
// nothing in `flutter analyze` or the existing tests looks at whether a screen
// can be constructed at all, so a layout mistake in one tab was invisible
// until somebody opened it on a phone.
//
// Supabase is initialised against an address that answers nothing, which is
// the point: every repository call fails the way it does offline, so this
// exercises the loading and error paths the screens actually have to render
// rather than a happy path with fixtures. What is being asserted is narrow and
// worth a lot — no screen throws while building.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sozqor/core/theme/app_theme.dart';
import 'package:sozqor/features/arena/arena_screen.dart';
import 'package:sozqor/features/arena/clan_screen.dart';
import 'package:sozqor/features/arena/leaderboard_screen.dart';
import 'package:sozqor/features/arena/league_screen.dart';
import 'package:sozqor/features/arena/tournament_screen.dart';
import 'package:sozqor/features/events/events_screen.dart';
import 'package:sozqor/features/home/chest_screen.dart';
import 'package:sozqor/features/home/home_screen.dart';
import 'package:sozqor/features/home/missions_screen.dart';
import 'package:sozqor/features/home/story_screen.dart';
import 'package:sozqor/features/moderator/moderator_screen.dart';
import 'package:sozqor/features/play/ai_chat_screen.dart';
import 'package:sozqor/features/play/packs_screen.dart';
import 'package:sozqor/features/play/play_hub_screen.dart';
import 'package:sozqor/features/profile/account_screen.dart';
import 'package:sozqor/features/profile/achievements_screen.dart';
import 'package:sozqor/features/profile/friends_screen.dart';
import 'package:sozqor/features/profile/legal_screen.dart';
import 'package:sozqor/features/profile/profile_screen.dart';
import 'package:sozqor/features/profile/report_screen.dart';
import 'package:sozqor/features/profile/settings_screen.dart';
import 'package:sozqor/features/profile/shop_screen.dart';
import 'package:sozqor/features/words/add_word_screen.dart';
import 'package:sozqor/features/words/explore_screen.dart';
import 'package:sozqor/features/words/word_bank_screen.dart';

/// Every screen that can be reached with no arguments.
const _screens = <String, Widget>{
  // the five tabs
  'home': HomeScreen(),
  'arena': ArenaScreen(),
  'play': PlayHubScreen(),
  'words': WordBankScreen(),
  'me': ProfileScreen(),
  // pushed from the tabs
  'achievements': AchievementsScreen(),
  'shop': ShopScreen(),
  'report': ReportScreen(),
  'friends': FriendsScreen(),
  'clan': ClanScreen(),
  'leaderboard': LeaderboardScreen(),
  'settings': SettingsScreen(),
  'account': AccountScreen(),
  'legal terms': LegalScreen(doc: LegalDoc.terms),
  'legal privacy': LegalScreen(doc: LegalDoc.privacy),
  'league': LeagueScreen(),
  'tournament': TournamentScreen(),
  'events': EventsScreen(),
  'missions': MissionsScreen(),
  'chest': ChestScreen(),
  'story': StoryScreen(),
  'packs': PacksScreen(),
  'explore': ExploreScreen(),
  'add word': AddWordScreen(),
  'ai chat': AiChatScreen(),
  'moderator': ModeratorScreen(),
};

/// A small phone with text scaled to the ceiling the app clamps at — the
/// combination a layout mistake shows up under first.
const _small = Size(360, 640);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      // Nothing listens here. Requests fail, which is exactly the state every
      // screen has to be able to draw.
      url: 'http://127.0.0.1:1',
      publishableKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  for (final entry in _screens.entries) {
    testWidgets('${entry.key} builds', (tester) async {
      tester.view.physicalSize = _small;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final dark in [false, true]) {
        await tester.pumpWidget(ProviderScope(
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: entry.value,
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 50));

        final err = tester.takeException();
        expect(err, isNull,
            reason: '${entry.key} threw while building in '
                    '${dark ? 'dark' : 'light'} mode:\n$err');
      }
    });
  }
}
