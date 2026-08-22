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

/// Claimed accounts to offer before anybody has typed a search.
final _suggestedProvider = FutureProvider<List<BoardRow>>(
    (ref) => ref.watch(boardRepoProvider).suggestedPeople());

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
    final username = ref.read(myProfileProvider).value?.username ?? '';
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

  Future<void> _add(BoardRow row) async {
    try {
      await ref.read(boardRepoProvider).addFriend(row.userId);
      ref.invalidate(friendsProvider);
      ref.invalidate(teamProvider);
      if (mounted) sqSnack(context, trp('{p1} досқа қосылды', {'p1': row.name}));
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
    final profile = ref.read(myProfileProvider).value;
    final cefr = profile?.cefrLevel ?? 'A1';
    final lang = profile?.nativeLang ?? 'kk';

    var pool = ref.read(levelPoolProvider).value ?? const <DictEntry>[];
    if (pool.length < 12) {
      pool = await ref.read(dictRepoProvider)
          .pool(cefr: visibleCefrFor(cefr), limit: 120)
          .catchError((_) => <DictEntry>[]);
    }

    final words = ref.read(myWordsProvider).value ?? const <Word>[];
    final items = <PlayItem>[
      ...words.take(30).map(PlayItem.fromWord),
      ...pool.map(PlayItem.fromDict),
    ];

    return QuestionFactory.build(
      items: items, pool: pool, kinds: kindsFor(cefr),
      count: 10, nativeLang: lang);
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
      final cefr = ref.read(myProfileProvider).value?.cefrLevel ?? 'A1';
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
      ...ref.watch(_friendsWornProvider).value ?? const <String, WornCosmetics>{},
      ..._resultWorn,
    };
    final invites = ref.watch(pendingInvitesProvider).value ?? const <Battle>[];
    final friendIds = {
      for (final f in friends.value ?? const <BoardRow>[]) f.userId
    };
    final list = friends.value ?? const <BoardRow>[];

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
                challenging: _challenging == r.userId,
                onAdd: () => _add(r),
                onRemove: () => _remove(r),
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

        // Somebody to add without having to guess a username first. Only
        // people who are not already friends, and only while the search box
        // is not showing its own answer.
        if (_results.isEmpty && !_searching) ...[
          ...(() {
            final all = ref.watch(_suggestedProvider).value
                ?? const <BoardRow>[];
            final fresh = [
              for (final r in all) if (!friendIds.contains(r.userId)) r,
            ];
            if (fresh.isEmpty) return const <Widget>[];
            return [
              SqSection(tr('Мына адамдарды қосуға болады')),
              SqGroup(children: [
                for (final r in fresh)
                  _PersonRow(
                    row: r,
                    worn: worn[r.userId],
                    isFriend: false,
                    challenging: _challenging == r.userId,
                    onAdd: () => _add(r),
                    onRemove: () => _remove(r),
                    onChallenge: () => _challenge(r)),
              ]),
              const SizedBox(height: 20),
            ];
          })(),
        ],

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
                  onChallenge: () => _challenge(f)),
            ]);
          },
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  final BoardRow row;
  final bool isFriend;
  final bool challenging;
  final VoidCallback onAdd, onRemove;
  final VoidCallback? onChallenge;

  /// What this person is wearing, once the cosmetics for the list have
  /// arrived. Null renders the plain row, as before.
  final WornCosmetics? worn;

  const _PersonRow({
    required this.row, required this.isFriend,
    this.challenging = false,
    required this.onAdd, required this.onRemove,
    this.onChallenge, this.worn});

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
          : SqSquareButton(PhosphorIconsBold.userPlus,
              size: 34,
              fill: AppColors.soft(AppColors.primary, d),
              border: Colors.transparent,
              iconColor: AppColors.primaryDeep,
              onTap: onAdd),
    );
  }
}
