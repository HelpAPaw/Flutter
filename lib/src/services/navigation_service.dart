import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:map_launcher/map_launcher.dart';

class NavigationService {
  static Future<void> navigateTo({
    required BuildContext context,
    required Coords coords,
    required String destinationTitle,
  }) async {
    final l10n = AppLocalizations.of(context);
    final availableMaps = await MapLauncher.installedMaps;

    if (availableMaps.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.cannotNavigate),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (availableMaps.length == 1) {
      await availableMaps.first.showDirections(
        destination: coords,
        destinationTitle: destinationTitle,
      );
      return;
    }

    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    l10n.chooseNavigationApp,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ...availableMaps.map((map) => ListTile(
                      leading: SvgPicture.asset(map.icon, width: 30, height: 30),
                      title: Text(map.mapName),
                      onTap: () {
                        Navigator.pop(context);
                        map.showDirections(
                          destination: coords,
                          destinationTitle: destinationTitle,
                        );
                      },
                    )),
              ],
            ),
          );
        },
      );
    }
  }
}
