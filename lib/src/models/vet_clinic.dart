class VetClinic {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String? phoneNumber;
  final double? rating;
  final String? googleMapsUri;
  final OpeningHours? openingHours;

  VetClinic({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.phoneNumber,
    this.rating,
    this.googleMapsUri,
    this.openingHours,
  });

  factory VetClinic.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>;
    final displayName = json['displayName'] as Map<String, dynamic>?;

    return VetClinic(
      id: json['id'] as String,
      name: displayName != null ? (displayName['text'] as String? ?? 'Unnamed Clinic') : 'Unnamed Clinic',
      address: json['formattedAddress'] as String? ?? 'Address not available',
      latitude: (location['latitude'] as num).toDouble(),
      longitude: (location['longitude'] as num).toDouble(),
      phoneNumber: json['internationalPhoneNumber'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      googleMapsUri: json['googleMapsUri'] as String?,
      openingHours: json['regularOpeningHours'] != null
          ? OpeningHours.fromJson(json['regularOpeningHours'] as Map<String, dynamic>)
          : null,
    );
  }
}

class OpeningHours {
  final List<String> weekdayDescriptions;
  final bool? openNow;

  OpeningHours({
    required this.weekdayDescriptions,
    this.openNow,
  });

  factory OpeningHours.fromJson(Map<String, dynamic> json) {
    return OpeningHours(
      weekdayDescriptions: (json['weekdayDescriptions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      openNow: json['openNow'] as bool?,
    );
  }
}
