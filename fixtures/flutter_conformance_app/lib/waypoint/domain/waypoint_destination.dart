enum WaypointDestinationKind {
  city,
  coast,
  mountain,
  culture,
  stay,
  food,
  nature,
}

final class WaypointDestination {
  const WaypointDestination({
    required this.id,
    required this.name,
    required this.country,
    required this.summary,
    required this.category,
    required this.kind,
    required this.locationLabel,
    required this.rating,
    required this.durationLabel,
    required this.imageAsset,
    required this.accentColor,
    required this.tags,
    this.emoji,
    this.distance,
    this.isSaved = false,
  });

  final String id;
  final String name;
  final String country;
  final String summary;
  final String category;
  final WaypointDestinationKind kind;
  final String locationLabel;
  final double rating;
  final String durationLabel;
  final String imageAsset;
  final String accentColor;
  final List<String> tags;
  final String? emoji;
  final String? distance;
  final bool isSaved;

  WaypointDestination copyWith({bool? isSaved}) => WaypointDestination(
    id: id,
    name: name,
    country: country,
    summary: summary,
    category: category,
    kind: kind,
    locationLabel: locationLabel,
    rating: rating,
    durationLabel: durationLabel,
    imageAsset: imageAsset,
    accentColor: accentColor,
    tags: tags,
    emoji: emoji,
    distance: distance,
    isSaved: isSaved ?? this.isSaved,
  );
}
