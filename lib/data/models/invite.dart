// lib/data/models/invite.dart
//
// The three small rows that make a match an agreement rather than an
// announcement: who is ringing, where a best-of-three stands, and whether the
// person on the other side is still there.

import '../../core/i18n/l10n.dart';

/// A friend battle that is ringing at this user right now.
///
/// Carries the caller's name and rating so the banner can be drawn from one
/// request — an invitation that has to fetch a profile before it can be shown
/// has already spent a second of the fifteen it gets.
class BattleInvite {
  final String battleId, fromUser, username, displayName, avatarEmoji, cefr;
  final int elo;

  /// Counted down by the banner. Reaching zero declines on this user's
  /// behalf, so the caller is never left waiting on somebody who has put
  /// their phone in a pocket.
  final int secondsLeft;

  const BattleInvite({
    required this.battleId,
    required this.fromUser,
    required this.username,
    required this.displayName,
    required this.avatarEmoji,
    required this.cefr,
    required this.elo,
    required this.secondsLeft,
  });

  factory BattleInvite.fromMap(Map<String, dynamic> m) => BattleInvite(
        battleId:    (m['battle_id'] ?? '').toString(),
        fromUser:    (m['from_user'] ?? '').toString(),
        username:    (m['username'] ?? '').toString(),
        displayName: (m['display_name'] ?? '').toString(),
        avatarEmoji: (m['avatar_emoji'] ?? '🦊').toString(),
        cefr:        (m['cefr'] ?? 'A1').toString(),
        elo:         (m['elo'] ?? 1000) as int,
        secondsLeft: (m['seconds_left'] ?? 0) as int,
      );

  String get name => displayName.trim().isNotEmpty ? displayName : username;
}

/// An invitation into a group room. Longer-lived than a battle invitation on
/// purpose: a lobby is a place you drift into, not a bell that rings.
class RoomInvite {
  final String roomId, code, fromUser, username, displayName, avatarEmoji;
  final int players, maxPlayers, secondsLeft;

  const RoomInvite({
    required this.roomId,
    required this.code,
    required this.fromUser,
    required this.username,
    required this.displayName,
    required this.avatarEmoji,
    required this.players,
    required this.maxPlayers,
    required this.secondsLeft,
  });

  factory RoomInvite.fromMap(Map<String, dynamic> m) => RoomInvite(
        roomId:      (m['room_id'] ?? '').toString(),
        code:        (m['code'] ?? '').toString(),
        fromUser:    (m['from_user'] ?? '').toString(),
        username:    (m['username'] ?? '').toString(),
        displayName: (m['display_name'] ?? '').toString(),
        avatarEmoji: (m['avatar_emoji'] ?? '🦊').toString(),
        players:     (m['players'] ?? 1) as int,
        maxPlayers:  (m['max_players'] ?? 4) as int,
        secondsLeft: (m['seconds_left'] ?? 0) as int,
      );

  String get name => displayName.trim().isNotEmpty ? displayName : username;
}

/// Where a rematch series stands. Both clients read this from the same rows,
/// which is why the scoreline agrees on the two phones instead of each device
/// keeping its own count.
class SeriesState {
  final String seriesId;
  final int played, mine, theirs, drawn;
  final bool decided, iOffered, theyOffered;

  const SeriesState({
    required this.seriesId,
    required this.played,
    required this.mine,
    required this.theirs,
    required this.drawn,
    required this.decided,
    required this.iOffered,
    required this.theyOffered,
  });

  factory SeriesState.fromMap(Map<String, dynamic> m) => SeriesState(
        seriesId:    (m['series_id'] ?? '').toString(),
        played:      (m['played'] ?? 0) as int,
        mine:        (m['mine'] ?? 0) as int,
        theirs:      (m['theirs'] ?? 0) as int,
        drawn:       (m['drawn'] ?? 0) as int,
        decided:     (m['decided'] ?? false) as bool,
        iOffered:    (m['i_offered'] ?? false) as bool,
        theyOffered: (m['they_offered'] ?? false) as bool,
      );

  String get scoreline => '$mine–$theirs';

  /// Null while the series is still level or unfinished.
  bool? get iWonSeries {
    if (!decided) return null;
    if (mine == theirs) return null;
    return mine > theirs;
  }

  /// Three games, no more. Asked for a fourth, the server refuses and the
  /// players go back to ordinary matchmaking — which is then a new opponent,
  /// not a rematch.
  int get gamesLeft => (3 - played).clamp(0, 3);
}

/// The answer to the heartbeat: is the other player still on the other end?
class BattlePresence {
  final String status;
  final bool opponentDone, paused, canClaim;

  /// Seconds since the opponent was last seen. Null against a bot, which
  /// never leaves.
  final int? opponentGap;

  const BattlePresence({
    required this.status,
    required this.opponentDone,
    required this.paused,
    required this.canClaim,
    this.opponentGap,
  });

  factory BattlePresence.fromMap(Map<String, dynamic> m) => BattlePresence(
        status:       (m['status'] ?? 'active').toString(),
        opponentDone: (m['opponent_done'] ?? false) as bool,
        paused:       (m['paused'] ?? false) as bool,
        canClaim:     (m['can_claim'] ?? false) as bool,
        opponentGap:  m['opponent_gap'] is int ? m['opponent_gap'] as int : null,
      );
}

/// One of the fixed things a player can say after a match. The list lives on
/// the server so a new phrase needs no app release — and so nothing that is
/// not on the list can ever be sent.
class QuickPhrase {
  final String code, kk, ru;
  const QuickPhrase({required this.code, required this.kk, required this.ru});

  factory QuickPhrase.fromMap(Map<String, dynamic> m) => QuickPhrase(
        code: (m['code'] ?? '').toString(),
        kk:   (m['kk'] ?? '').toString(),
        ru:   (m['ru'] ?? '').toString(),
      );

  /// The phrase in the reader's own language. Both sides are stored, so a
  /// Kazakh player's "Жақсы ойын!" reaches a Russian player as
  /// "Хорошая игра!" rather than as text they cannot read.
  String get text => AppLang.isRu && ru.isNotEmpty ? ru : kk;
}

class QuickMessage {
  final String fromUser, phrase, kk, ru;
  final bool isMine;
  const QuickMessage({
    required this.fromUser,
    required this.phrase,
    required this.kk,
    required this.ru,
    required this.isMine,
  });

  factory QuickMessage.fromMap(Map<String, dynamic> m) => QuickMessage(
        fromUser: (m['from_user'] ?? '').toString(),
        phrase:   (m['phrase'] ?? '').toString(),
        kk:       (m['kk'] ?? '').toString(),
        ru:       (m['ru'] ?? '').toString(),
        isMine:   (m['is_mine'] ?? false) as bool,
      );

  String get text => AppLang.isRu && ru.isNotEmpty ? ru : kk;
}
