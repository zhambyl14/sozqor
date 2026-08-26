// lib/features/profile/friends_screen.dart
//
// Friends: find people, add them, and challenge them without leaving the
// screen. Pending friend battles are pinned to the top, because an invite
// nobody notices is the same as no invite at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/question.dart';
import '../../data/models/word.dart';
import '../../data/repos/cosmetics_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/question_factory.dart';
import '../arena/battle_screen.dart';
import '../auth/guest_gate.dart';
import 'public_profile_screen.dart';
import 'worn_avatar.dart';

/// What the people on this screen are wearing. One request for the whole
/// list, keyed off the friends list so it refetches exactly when that does.
final _friendsWornProvider =
    FutureProvider<Map<String, WornCosmetics>>((ref) async {
  final rows = await ref.watch(friendsProvider.future);
  if (rows.isEmpty) return const {};
  return ref
      .watch(cosmeticsRepoProvider)
      .worn(rows.map((r) => r.userId).toList());
});

/// Requests waiting on an answer from this user. `value` carries the row id.
final friendRequestsProvider = FutureProvider<List<BoardRow>>((ref) {
  ref.watch(authChangesProvider);
  return ref.watch(boardRepoProvider).friendRequests();
});

/// Requests this user has sent that nobody has answered yet.
final sentRequestsProvider = FutureProvider<List<BoardRow>>((ref) {
  ref.watch(authChangesProvider);
  return ref.watch(boardRepoProvider).sentRequests();
});

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _search = TextEditingController();
  List<BoardRow> _results = const [];
  /// Cosmetics for the search results only; the friends list has its own
  /// provider, and a stranger's frame matters as much as a friend's.
  Map<String, WornCosmetics> _resultWorn = const {};
  bool _searching = false;
  bool _searched = false;
  String? _challenging;

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  /// Shares the learner's own @username so a friend can find them the same
  /// way this screen finds others.
  Future<void> _shareUsername() async {
    final username = ref.read(myProfileProvider).valueOrNull?.username ?? '';
    if (username.isEmpty) return;
    await Share.share(trp('Мені SozQor-да @{p1} деп тап', {'p1': username}));
  }

  Future<void> _find() async {
    final q = _search.text.trim();
    if (q.length < 2) {
      sqSnack(context, tr('Кемінде 2 таңба жазыңыз'), error: true);
      return;
    }
    setState(() => _searching = true);
    try {
      final rows = await ref.read(boardRepoProvider).searchUsers(q);
      // A failed cosmetics lookup must not lose the search itself: the names
      // are the answer, the frames are decoration on top of it.
      final worn = rows.isEmpty
          ? const <String, WornCosmetics>{}
          : await ref
              .read(cosmeticsRepoProvider)
              .worn(rows.map((r) => r.userId).toList())
              .catchError((_) => const <String, WornCosmetics>{});
      if (mounted) {
        setState(() {
          _results = rows;
          _resultWorn = worn;
          _searched = true;
        });
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// EN-15: asking, not taking. The other person decides.
  Future<void> _add(BoardRow row) async {
    try {
      final result =
          await ref.read(boardRepoProvider).sendFriendRequest(row.userId);
      ref.invalidate(friendsProvider);
      ref.invalidate(sentRequestsProvider);
      ref.invalidate(friendRequestsProvider);
      ref.invalidate(teamProvider);
      if (!mounted) return;
      sqSnack(context, switch (result) {
        // They had already asked, so this answered them.
        'friends' => trp('{p1} досқа қосылды', {'p1': row.name}),
        'blocked' => tr('Бұл адамға сұраныс жіберілмейді'),
        _         => trp('{p1} сұраныс жіберілді', {'p1': row.name}),
      });
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
  }

  /// Accepts or declines a request that was sent to this user.
  Future<void> _respond(BoardRow row, {required bool accept}) async {
    try {
      await ref.read(boardRepoProvider)
          .respondToRequest(row.value, accept: accept);
      ref.invalidate(friendRequestsProvider);
      ref.invalidate(friendsProvider);
      ref.invalidate(teamProvider);
      if (!mounted) return;
      sqSnack(context, accept
          ? trp('{p1} досқа қосылды', {'p1': row.name})
          : tr('Сұраныс қабылданбады'));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
  }

  Future<void> _remove(BoardRow row) async {
    final ok = await sqConfirm(context,
      title: tr('Достан шығару'),
      message: trp('{p1} тізімнен шығарылсын ба?', {'p1': row.name}),
      confirm: tr('Шығару'));
    if (!ok) return;
    try {
      await ref.read(boardRepoProvider).removeFriend(row.userId);
      ref.invalidate(friendsProvider);
      ref.invalidate(teamProvider);
      if (mounted) sqSnack(context, trp('{p1} тізімнен шығарылды', {'p1': row.name}));
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    }
  }

  /// EN-17: opens somebody's public profile.
  Future<void> _openProfile(BoardRow row) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PublicProfileScreen(
        userId: row.userId, fallbackName: row.name)));
  }

  Future<void> _play(Battle b) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BattleScreen(battle: b)));
    if (mounted) {
      ref.invalidate(pendingInvitesProvider);
      refreshAll(ref);
    }
  }

  /// Battle rounds are built from the shared dictionary at the learner's
  /// level, mirroring ArenaScreen's own question set so a direct friend
  /// challenge is exactly as fair as the code-based one.
  Future<List<Question>> _buildQuestions() async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    final cefr = profile?.cefrLevel ?? 'A1';
    final lang = ref.read(nativeLangProvider);

    var pool = ref.read(levelPoolProvider).valueOrNull ?? const <DictEntry>[];
    if (pool.length < 12) {
      pool = await ref.read(dictRepoProvider)
          .pool(cefr: visibleCefrFor(cefr), limit: 120)
          .catchError((_) => <DictEntry>[]);
    }

    final words = ref.read(myWordsProvider).valueOrNull ?? const <Word>[];
    final items = <PlayItem>[
      ...words.take(30).map(PlayItem.fromWord),
      ...pool.map(PlayItem.fromDict),
    ];

    return QuestionFactory.build(
      items: items, pool: pool, kinds: kindsFor(cefr),
      count: 10, nativeLang: lang,
      // Head-to-head play excludes audio for the same reason ranked does.
      exclude: const {QKind.listening});
  }

  /// Starts a battle against this friend directly — no invite code changes
  /// hands, it simply appears in both people's pending invites.
  Future<void> _challenge(BoardRow row) async {
    if (!await requireAccount(context, ref, GuestFeature.friends)) return;
    if (!mounted || _challenging != null) return;
    setState(() => _challenging = row.userId);
    try {
      final questions = await _buildQuestions();
      if (questions.length < 5) {
        throw Exception(tr('Баттл үшін сөз жетпейді'));
      }
      final cefr = ref.read(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
      final battle = await ref.read(battleRepoProvider).createFriendBattle(
        questions: questions, cefr: cefr, targetUserId: row.userId);
      if (mounted) await _play(battle);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _challenging = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final friends = ref.watch(friendsProvider);
    final worn = {
      ...ref.watch(_friendsWornProvider).valueOrNull ?? const <String, WornCosmetics>{},
      ..._resultWorn,
    };
    final invites = ref.watch(pendingInvitesProvider).valueOrNull ?? const <Battle>[];
    final friendIds = {
      for (final f in friends.valueOrNull ?? const <BoardRow>[]) f.userId
    };
    // People already asked, so a search result offers "sent" rather than a
    // second request button.
    final sentIds = {
      for (final r in ref.watch(sentRequestsProvider).valueOrNull
          ?? const <BoardRow>[]) r.userId
    };
    final list = friends.valueOrNull ?? const <BoardRow>[];

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(friendsProvider);
        ref.invalidate(pendingInvitesProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Достар'),
          eyebrow: trp('{p1} дос · {p2} шақыру', {'p1': '${list.length}', 'p2': '${invites.length}'}),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        for (final b in invites) ...[
          SqPanel(
            radius: 20,
            padding: const EdgeInsets.all(15),
            fill: AppColors.soft(AppColors.red, d),
            border: AppColors.line(AppColors.red, d),
            child: Row(
              children: [
                const SqTintBox(PhosphorIconsFill.sword,
                  tint: AppColors.red, size: 40, solid: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Баттл шақыруы'),
                        style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800,
                          color: AppColors.text(d))),
                      Text('Код: ${b.inviteCode ?? '—'}',
                        style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600,
                          color: AppColors.redInk)),
                    ],
                  ),
                ),
                SqLip(
                  fill: AppColors.red,
                  lip: AppColors.redDeep,
                  depth: 3,
                  radius: 12,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 10),
                  onTap: () => _play(b),
                  child: Text(tr('Ойнау'),
                    style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.card(d),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.border(d)),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsBold.magnifyingGlass,
                size: 17, color: AppColors.text4(d)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _find(),
                  style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600,
                    color: AppColors.text(d)),
                  decoration: InputDecoration(
                    hintText: tr('Логин немесе есім'),
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    hintStyle: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600,
                      color: AppColors.text4(d)),
                  ),
                ),
              ),
              if (_searching)
                const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2))
              else
                GestureDetector(
                  onTap: _find,
                  child: const Icon(PhosphorIconsBold.arrowRight,
                    size: 17, color: AppColors.primary)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: _shareUsername,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.shareNetwork,
                  size: 14, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(tr('Логиныңды бөліс'),
                  style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_results.isNotEmpty) ...[
          SqSection(tr('Іздеу нәтижесі')),
          SqGroup(children: [
            for (final r in _results)
              _PersonRow(
                row: r,
                worn: worn[r.userId],
                isFriend: friendIds.contains(r.userId),
                requested: sentIds.contains(r.userId),
                challenging: _challenging == r.userId,
                onAdd: () => _add(r),
                onRemove: () => _remove(r),
                onOpen: () => _openProfile(r),
                onChallenge: () => _challenge(r)),
          ]),
          const SizedBox(height: 20),
        ] else if (_searched && !_searching) ...[
          SqEmpty(
            icon: PhosphorIconsFill.magnifyingGlass,
            title: tr('Ешкім табылмады'),
            subtitle: tr('Тек тіркелген аккаунттар табылады'),
            tint: AppColors.sky),
          const SizedBox(height: 20),
        ],

        // EN-15 / KK-2: a list of everybody who has an account used to sit
        // here, which is both a privacy problem and the reason nobody ever
        // used the search box. Finding a person is a deliberate act now — you
        // need their handle. What replaces the list is the thing that
        // genuinely belongs on this screen: requests waiting on an answer.
        ...(() {
          final incoming = ref.watch(friendRequestsProvider).valueOrNull
              ?? const <BoardRow>[];
          if (incoming.isEmpty) return const <Widget>[];
          return [
            SqSection(tr('Сұраныстар'),
              trailingWidget: SqNum('${incoming.length}',
                size: 11, color: AppColors.text3(isDark(context)))),
            SqGroup(children: [
              for (final r in incoming)
                _RequestRow(
                  row: r,
                  worn: worn[r.userId],
                  onAccept: () => _respond(r, accept: true),
                  onDecline: () => _respond(r, accept: false)),
            ]),
            const SizedBox(height: 20),
          ];
        })(),

        // Who I have asked and who has not answered yet.
        //
        // Without this the request vanished the moment it was sent: the
        // search box forgets, and there was nowhere to see that you HAD
        // asked — so the only way to find out was to search the handle again
        // and read the greyed-out button. A pending request is a thing you
        // are waiting on, and things you are waiting on belong on the screen.
        ...(() {
          final outgoing = ref.watch(sentRequestsProvider).valueOrNull
              ?? const <BoardRow>[];
          if (outgoing.isEmpty) return const <Widget>[];
          return [
            SqSection(tr('Жіберілген сұраныстар'),
              trailingWidget: SqNum('${outgoing.length}',
                size: 11, color: AppColors.text3(isDark(context)))),
            SqGroup(children: [
              for (final r in outgoing)
                SqTile(
                  leading: WornAvatar(
                    name: r.displayName.isEmpty ? r.username : r.displayName,
                    worn: worn[r.userId],
                    size: 38),
                  title: r.displayName.isEmpty ? r.username : r.displayName,
                  subtitle: tr('Жауабын күтудеміз'),
                  trailing: SqBadge(tr('Жіберілді'), tint: AppColors.amber),
                ),
            ]),
            const SizedBox(height: 20),
          ];
        })(),

        SqSection(tr('Достарым'),
          trailingWidget: SqNum('${list.length}',
            size: 11, color: AppColors.text3(d))),
        friends.when(
          loading: () => const Column(children: [SqShimmer(), SqShimmer()]),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Тізім жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.red),
          data: (rows) {
            if (rows.isEmpty) {
              return SqEmpty(
                icon: PhosphorIconsFill.handshake,
                title: tr('Әзірге дос жоқ'),
                subtitle: tr('Логин бойынша тауып қос — сосын баттлға шақыр'),
                tint: AppColors.sky);
            }
            return SqGroup(children: [
              for (final f in rows)
                _PersonRow(
                  row: f, isFriend: true,
                  worn: worn[f.userId],
                  challenging: _challenging == f.userId,
                  onAdd: () {}, onRemove: () => _remove(f),
                  onOpen: () => _openProfile(f),
                  onChallenge: () => _challenge(f)),
            ]);
          },
        ),
      ],
    );
  }
}

/// An incoming friend request: accept or decline, both one tap (EN-15).
///
/// Deliberately not a notification the app nags about. It is a row that stays
/// on this screen until it is answered, which is what the PRD asks for —
/// shown once, then waiting here rather than interrupting again.
class _RequestRow extends StatelessWidget {
  final BoardRow row;
  final WornCosmetics? worn;
  final VoidCallback onAccept, onDecline;

  const _RequestRow({
    required this.row,
    required this.onAccept,
    required this.onDecline,
    this.worn,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqTile(
      fill: wornRowFill(worn, d),
      leading: WornAvatar(
        name: row.name, worn: worn, size: 38, emoji: row.avatarEmoji),
      title: row.name,
      subtitle: tr('Досқа қосылғысы келеді'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SqSquareButton(PhosphorIconsBold.check,
            size: 34,
            fill: AppColors.soft(AppColors.green, d),
            border: Colors.transparent,
            iconColor: AppColors.greenDeep,
            onTap: onAccept),
          const SizedBox(width: 8),
          SqSquareButton(PhosphorIconsBold.x,
            size: 34,
            fill: AppColors.soft(AppColors.red, d),
            border: Colors.transparent,
            iconColor: AppColors.red,
            onTap: onDecline),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final BoardRow row;
  final bool isFriend;
  final bool challenging;
  /// A request has already gone to this person and is still unanswered, so
  /// the row says so rather than offering to send a second one.
  final bool requested;
  final VoidCallback onAdd, onRemove;
  final VoidCallback? onChallenge;
  final VoidCallback? onOpen;

  /// What this person is wearing, once the cosmetics for the list have
  /// arrived. Null renders the plain row, as before.
  final WornCosmetics? worn;

  const _PersonRow({
    required this.row, required this.isFriend,
    this.challenging = false,
    this.requested = false,
    required this.onAdd, required this.onRemove,
    this.onChallenge, this.worn, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final title = worn?.title;
    return SqTile(
      fill: wornRowFill(worn, d),
      leading: WornAvatar(
        name: row.name, worn: worn, size: 38, emoji: row.avatarEmoji),
      title: row.name,
      subtitle: title == null
          ? '${row.cefrLevel} · ${row.value} XP'
          : '${row.cefrLevel} · ${row.value} XP · $title',
      // EN-17: the row opens the person. Cosmetics are bought to be seen and
      // until now the only person who could see them was their owner.
      onTap: onOpen,
      trailing: isFriend
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onChallenge != null) ...[
                  challenging
                      ? const SizedBox(
                          width: 34, height: 34,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2.2)))
                      : SqSquareButton(PhosphorIconsFill.sword,
                          size: 34,
                          fill: AppColors.soft(AppColors.primary, d),
                          border: Colors.transparent,
                          iconColor: AppColors.primaryDeep,
                          onTap: onChallenge),
                  const SizedBox(width: 8),
                ],
                SqSquareButton(PhosphorIconsBold.userMinus,
                  size: 34,
                  fill: AppColors.soft(AppColors.red, d),
                  border: Colors.transparent,
                  iconColor: AppColors.red,
                  onTap: onRemove),
              ],
            )
          : requested
          ? SqBadge(tr('Жіберілді'), tint: AppColors.amber)
          : SqSquareButton(PhosphorIconsBold.userPlus,
              size: 34,
              fill: AppColors.soft(AppColors.primary, d),
              border: Colors.transparent,
              iconColor: AppColors.primaryDeep,
              onTap: onAdd),
    );
  }
}
