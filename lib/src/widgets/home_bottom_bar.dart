import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

/// The app's five destinations.
///
/// Replaces the navigation drawer, which put every destination behind a
/// hamburger on the map's app bar and so made the map the only screen anyone
/// ever found.
///
/// Deliberately dumb — it takes [unreadCount] rather than opening its own
/// listener. The badge's stream has to be keyed on the account *and* the test
/// mode, and that bookkeeping belongs with the shell that outlives a tab switch.
/// Keeping it out of here is also what lets the Bulgarian layout test pump the
/// bar on its own, without Firebase.
class HomeBottomBar extends StatelessWidget {
  const HomeBottomBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.unreadCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The bar is chrome, not content. Past ~1.2 five labels have nowhere left
    // to go and it starts eating the map rather than helping anyone read it.
    // Everything above this line keeps scaling normally.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: [
          _destination(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
            label: l10n.tabMap,
            fullName: l10n.tabMap,
          ),
          _destination(
            icon: Icons.pin_drop_outlined,
            selectedIcon: Icons.pin_drop,
            // The visible labels are deliberately short — five of them share a
            // phone's width, and the Bulgarian names do not fit. The full name
            // rides along as the tooltip, for a long-press and for the screen's
            // own app bar to agree with.
            label: l10n.tabMySignals,
            fullName: l10n.mySignals,
          ),
          _destination(
            icon: Icons.visibility_outlined,
            selectedIcon: Icons.visibility,
            label: l10n.tabWatching,
            fullName: l10n.watching,
          ),
          _destination(
            icon: Icons.inbox_outlined,
            selectedIcon: Icons.inbox,
            label: l10n.tabInbox,
            fullName: unreadCount > 0
                ? '${l10n.myNotifications}, '
                    '${l10n.unreadNotificationsCount(unreadCount)}'
                : l10n.myNotifications,
            badgeCount: unreadCount,
          ),
          _destination(
            icon: Icons.menu,
            selectedIcon: Icons.menu,
            label: l10n.tabMenu,
            fullName: l10n.menu,
          ),
        ],
      ),
    );
  }

  NavigationDestination _destination({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required String fullName,
    int badgeCount = 0,
  }) {
    Widget glyph(IconData data) => badgeCount > 0
        ? Badge.count(count: badgeCount, child: Icon(data))
        : Icon(data);

    return NavigationDestination(
      icon: glyph(icon),
      selectedIcon: glyph(selectedIcon),
      // NB: this is also the accessibility name — `NavigationBar` builds each
      // destination's semantics from the visible label, **not** from the
      // tooltip (verified on device 2026-09-11: the node reads "Мои, Раздел 2
      // от 5"). So the short form is what a screen reader announces and what
      // element-based device testing matches on. That is acceptable because
      // every short form is a real word in its own right; it would not be if
      // one were ever abbreviated to something unreadable.
      label: label,
      tooltip: fullName,
    );
  }
}
