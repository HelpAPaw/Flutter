package org.helpapaw.helpapaw

/**
 * Base32 geohash encoder.
 *
 * Must stay byte-identical to `geoflutterfire_plus`'s Dart implementation
 * (`lib/src/math.dart`), because the notification fan-out finds nearby users
 * with a geohash *range* query over `userLocations`. A geohash produced with a
 * different alphabet or precision would sort into the wrong range and the user
 * would silently never match — no error, just no notifications.
 *
 * This is the standard algorithm: interleave longitude and latitude bits,
 * most-significant first, emitting a base32 character every 5 bits.
 */
object Geohash {
    /** Alphabet used by geoflutterfire_plus (note: no a, i, l or o). */
    private const val BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"

    /** Precision used by `GeoFirePoint.geohash`, whose default is 9. */
    const val DEFAULT_PRECISION = 9

    fun encode(
        latitude: Double,
        longitude: Double,
        precision: Int = DEFAULT_PRECISION,
    ): String {
        val characters = StringBuilder(precision)

        var isLongitude = true
        var bits = 0
        var hashValue = 0

        var minLatitude = -90.0
        var maxLatitude = 90.0
        var minLongitude = -180.0
        var maxLongitude = 180.0

        while (characters.length < precision) {
            if (isLongitude) {
                val middle = (minLongitude + maxLongitude) / 2
                if (longitude > middle) {
                    hashValue = (hashValue shl 1) + 1
                    minLongitude = middle
                } else {
                    hashValue = (hashValue shl 1)
                    maxLongitude = middle
                }
            } else {
                val middle = (minLatitude + maxLatitude) / 2
                if (latitude > middle) {
                    hashValue = (hashValue shl 1) + 1
                    minLatitude = middle
                } else {
                    hashValue = (hashValue shl 1)
                    maxLatitude = middle
                }
            }

            isLongitude = !isLongitude
            bits++

            if (bits == 5) {
                characters.append(BASE32[hashValue])
                bits = 0
                hashValue = 0
            }
        }

        return characters.toString()
    }
}
