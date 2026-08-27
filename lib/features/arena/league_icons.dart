// lib/features/arena/league_icons.dart
//
// A face for each rung of the ladder.
//
// Every band was an 8-pixel coloured dot, which meant the ladder was seven
// identical rows distinguished only by a name and a number — and the colours
// alone do not survive being looked at quickly, or being looked at by
// somebody who does not separate bronze from gold at a glance.
//
// The shapes climb the way the names do: a plain shield, then a marked one,
// then a medal, then a starred shield, then a stone, then a crown, then the
// summit. Read top to bottom the ladder now has a direction even with the
// text stripped out.
//
// Kept in a file of its own because both the league screen and a public
// profile draw a band, and the league screen already opens profiles — an
// import the other way would close a cycle.

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The badge for a band, by its tier index as `league_bands()` numbers them.
///
/// Falls back rather than throwing: a band added server-side tomorrow draws a
/// shield today instead of crashing the screen it appears on.
IconData leagueIcon(int tier) => switch (tier) {
  0 => PhosphorIconsFill.shield,        // Қола
  1 => PhosphorIconsFill.shieldChevron, // Күміс
  2 => PhosphorIconsFill.medal,         // Алтын
  3 => PhosphorIconsFill.shieldStar,    // Платина
  4 => PhosphorIconsFill.diamond,       // Алмас
  5 => PhosphorIconsFill.crownSimple,   // Шебер
  6 => PhosphorIconsFill.mountains,     // Тұғыр
  _ => PhosphorIconsFill.shield,
};
