import Foundation

/// Base32 geohash encoder.
///
/// Must stay byte-identical to `geoflutterfire_plus`'s Dart implementation
/// (`lib/src/math.dart`), because the notification fan-out finds nearby users
/// with a geohash *range* query over `userLocations`. A geohash produced with a
/// different alphabet or precision would sort into the wrong range and the user
/// would silently never match — no error, just no notifications.
///
/// This is the standard algorithm: interleave longitude and latitude bits,
/// most-significant first, and emit a base32 character every 5 bits.
enum Geohash {
  /// Alphabet used by geoflutterfire_plus (note: no a, i, l or o).
  private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

  /// Precision used by `GeoFirePoint.geohash`, whose default is 9.
  static let defaultPrecision = 9

  static func encode(
    latitude: Double,
    longitude: Double,
    precision: Int = defaultPrecision
  ) -> String {
    var characters = ""
    characters.reserveCapacity(precision)

    var isLongitude = true
    var bits = 0
    var hashValue = 0

    var minLatitude = -90.0
    var maxLatitude = 90.0
    var minLongitude = -180.0
    var maxLongitude = 180.0

    while characters.count < precision {
      if isLongitude {
        let middle = (minLongitude + maxLongitude) / 2
        if longitude > middle {
          hashValue = (hashValue << 1) + 1
          minLongitude = middle
        } else {
          hashValue = (hashValue << 1) + 0
          maxLongitude = middle
        }
      } else {
        let middle = (minLatitude + maxLatitude) / 2
        if latitude > middle {
          hashValue = (hashValue << 1) + 1
          minLatitude = middle
        } else {
          hashValue = (hashValue << 1) + 0
          maxLatitude = middle
        }
      }

      isLongitude.toggle()
      bits += 1

      if bits == 5 {
        characters.append(base32[hashValue])
        bits = 0
        hashValue = 0
      }
    }

    return characters
  }
}
