import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Somebody's profile picture, or a glyph when there isn't one.
///
/// Three screens drew this by hand — the drawer, your own profile, and now
/// somebody else's — and only the newest of them handled a URL that fails to
/// load. That is the worst way for the copies to differ: the *same* avatar
/// rendered as a person icon on one screen and a blank grey disc on another,
/// with nothing to say why.
///
/// [CachedNetworkImage] with an `errorWidget` rather than
/// `CircleAvatar.backgroundImage` + `onBackgroundImageError`: the provider form
/// reports failure through a callback that fires *during* image resolution, so
/// recovering from it means a state field and a post-frame callback to escape
/// the build that started it. The widget form simply swaps in the fallback, and
/// it is what `signal_info_card` and the signal photo carousel already use.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.url,
    this.radius = 20,
    this.fallbackIcon = Icons.person,
  });

  /// The picture, or null for an account that has none.
  final String? url;

  /// Matches [CircleAvatar.radius], whose default this repeats.
  final double radius;

  /// Drawn when there is no picture, or the one there is cannot be loaded.
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final source = url;
    return CircleAvatar(
      radius: radius,
      child: source == null || source.isEmpty
          ? Icon(fallbackIcon, size: radius)
          : ClipOval(
              child: CachedNetworkImage(
                imageUrl: source,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(fallbackIcon, size: radius),
              ),
            ),
    );
  }
}
