import 'package:conformance/waypoint/domain/waypoint_activity.dart';
import 'package:conformance/waypoint/domain/waypoint_checklist_item.dart';
import 'package:conformance/waypoint/domain/waypoint_destination.dart';
import 'package:conformance/waypoint/domain/waypoint_discover_category.dart';
import 'package:conformance/waypoint/domain/waypoint_discover_collection.dart';
import 'package:conformance/waypoint/domain/waypoint_home_data.dart';
import 'package:conformance/waypoint/domain/waypoint_home_hero.dart';
import 'package:conformance/waypoint/domain/waypoint_itinerary_item.dart';
import 'package:conformance/waypoint/domain/waypoint_offer.dart';
import 'package:conformance/waypoint/domain/waypoint_note_field.dart';
import 'package:conformance/waypoint/domain/waypoint_permission_action.dart';
import 'package:conformance/waypoint/domain/waypoint_planner_field.dart';
import 'package:conformance/waypoint/domain/waypoint_test_action.dart';
import 'package:conformance/waypoint/domain/waypoint_trip.dart';
import 'package:conformance/waypoint/domain/waypoint_trip_document.dart';

final class WaypointJsonDecoder {
  const WaypointJsonDecoder._();

  static WaypointHomeData decodeHome(Object? value) {
    final map = _asMap(value);
    final destinationValues = map['destinations'] ?? map['places'];
    final offerValue = map['offer'] ?? map['banner'];
    return WaypointHomeData(
      destinations: _asList(destinationValues)
          .map(decodeDestination)
          .toList(growable: false),
      categories: _decodeCategories(map['categories']),
      collections: _decodeCollections(map['collections']),
      searchSuggestions: _searchSuggestions(map['searchSuggestions']),
      trips: _asList(map['trips']).map(decodeTrip).toList(growable: false),
      activities: _asList(map['activities'])
          .map(decodeActivity)
          .toList(growable: false),
      offer: offerValue == null ? null : decodeOffer(offerValue),
      actions: _decodeActions(map['actions']),
      permissionActions: _decodePermissionActions(map['permissionActions']),
      greeting: map['greeting'] is String ? map['greeting'] as String : null,
      discoverTitle: _optionalString(map['discoverTitle']),
      hero: map['hero'] == null ? null : decodeHomeHero(map['hero']),
    );
  }

  static WaypointHomeHero decodeHomeHero(Object? value) {
    final map = _asMap(value);
    return WaypointHomeHero(
      eyebrow: _string(map['eyebrow']),
      title: _string(map['title']),
      subtitle: _string(map['subtitle']),
      imageAsset: _string(map['imageAsset'] ?? map['image']),
      videoAsset: _string(map['videoAsset'] ?? map['video']),
      action: _string(map['action']),
      actionLabel: _string(map['actionLabel'] ?? map['cta']),
    );
  }

  static List<WaypointDiscoverCollection> _decodeCollections(Object? value) {
    if (value == null) {
      return const <WaypointDiscoverCollection>[];
    }
    return _asList(value).map(_decodeCollection).toList(growable: false);
  }

  static List<WaypointDiscoverCategory> _decodeCategories(Object? value) {
    if (value is! List) {
      return const <WaypointDiscoverCategory>[];
    }
    return value
        .map(_tryDecodeCategory)
        .whereType<WaypointDiscoverCategory>()
        .toList(growable: false);
  }

  static WaypointDiscoverCategory? _tryDecodeCategory(Object? value) {
    if (value is! Map) {
      return null;
    }
    final map = _asMap(value);
    final id = map['id'];
    final label = map['label'];
    final icon = map['icon'];
    if (id is! String ||
        id.trim().isEmpty ||
        label is! String ||
        label.trim().isEmpty ||
        icon is! String ||
        icon.trim().isEmpty) {
      return null;
    }
    return WaypointDiscoverCategory(id: id, label: label, icon: icon);
  }

  static WaypointDiscoverCollection _decodeCollection(Object? value) {
    final map = _asMap(value);
    return WaypointDiscoverCollection(
      id: _string(map['id']),
      title: _string(map['title']),
      subtitle: _string(map['subtitle']),
      imageAsset: _string(map['imageAsset']),
    );
  }

  static List<WaypointDestination> decodeDestinations(Object? value) {
    final map = _asMap(value);
    return _asList(map['destinations'] ?? map['places'])
        .map(decodeDestination)
        .toList(growable: false);
  }

  static WaypointDestination decodeDestination(Object? value) {
    final map = _asMap(value);
    return WaypointDestination(
      id: _string(map['id']),
      name: _string(map['name']),
      country: _string(map['country'] ?? map['location']),
      summary: _string(map['summary'] ?? map['description']),
      category: _string(map['category']),
      kind: _destinationKind(_string(map['kind'])),
      locationLabel: _string(map['locationLabel'] ?? map['location']),
      rating: _number(map['rating']),
      durationLabel: _string(map['durationLabel'] ?? map['duration']),
      imageAsset: _string(map['imageAsset'] ?? map['image']),
      accentColor: _string(map['accentColor'] ?? map['accent']),
      tags: _strings(map['tags']),
      emoji: _optionalString(map['emoji']),
      distance: _optionalString(map['distance']),
      isSaved: map['saved'] == true || map['isSaved'] == true,
    );
  }

  static WaypointTrip decodeTrip(Object? value) {
    final map = _asMap(value);
    final documentValues = map['documents'];
    return WaypointTrip(
      id: _string(map['id']),
      title: _string(map['title']),
      destination: _string(map['destination']),
      dateRange: _string(map['dateRange']),
      durationLabel: _string(map['durationLabel'] ?? map['duration']),
      imageAsset: _string(map['imageAsset'] ?? map['coverAsset']),
      progress: _number(map['progress']),
      itinerary: _asList(map['itinerary'])
          .map(decodeItinerary)
          .toList(growable: false),
      checklist: _asList(map['checklist'])
          .map(_decodeChecklistItem)
          .toList(growable: false),
      coverLabel: _optionalString(map['coverLabel']),
      accentColor: _optionalString(map['accentColor'] ?? map['accent']),
      documents: documentValues == null
          ? const <WaypointTripDocument>[]
          : _asList(documentValues).map(decodeDocument).toList(growable: false),
    );
  }

  static WaypointTripDocument decodeDocument(Object? value) {
    final map = _asMap(value);
    return WaypointTripDocument(
      name: _string(map['name']),
      kind: _string(map['kind']),
      sizeLabel: _string(map['sizeLabel']),
      icon: map['icon'] is String ? map['icon'] as String : null,
    );
  }

  static WaypointItineraryItem decodeItinerary(Object? value) {
    final map = _asMap(value);
    return WaypointItineraryItem(
      timeLabel: _string(map['timeLabel'] ?? map['time']),
      title: _string(map['title']),
      detail: _string(map['detail']),
      category: _string(map['category']),
      isComplete: map['isComplete'] == true || map['done'] == true,
    );
  }

  static WaypointActivity decodeActivity(Object? value) {
    final map = _asMap(value);
    final title = _string(map['title']);
    return WaypointActivity(
      id: _string(map['id'] ?? title),
      title: title,
      detail: _string(map['detail']),
      timeLabel: _string(map['timeLabel'] ?? map['time']),
      iconName: _string(map['iconName'] ?? map['icon']),
      accentColor: _string(map['accentColor'] ?? map['accent']),
    );
  }

  static WaypointOffer decodeOffer(Object? value) {
    final map = _asMap(value);
    return WaypointOffer(
      id: _string(map['id']),
      title: _string(map['title']),
      message: _string(map['message'] ?? map['body']),
      actionLabel: _string(map['actionLabel'] ?? map['cta']),
      action: _optionalString(map['action']),
      expiresAt: DateTime.parse(_string(map['expiresAt'])),
      accentColor: _string(map['accentColor'] ?? map['accent']),
      isDismissible: map['dismissible'] is bool
          ? map['dismissible'] as bool
          : true,
    );
  }

  static WaypointTestAction decodeAction(Object? value) {
    final map = _asMap(value);
    final id = _string(map['id']);
    final isOpenPlanner = id == 'open_planner';
    final type = isOpenPlanner
        ? _requiredOpenPlannerType(map['type'])
        : _string(map['type']);
    final title = isOpenPlanner
        ? _requiredNonBlankString(map['title'])
        : _string(map['title']);
    final subtitle = isOpenPlanner
        ? _requiredNonBlankString(map['subtitle'])
        : _string(map['subtitle']);
    final submitLabelValue = map['submitLabel'] ?? map['actionLabel'];
    final submitLabel = isOpenPlanner
        ? _requiredNonBlankString(submitLabelValue)
        : _string(submitLabelValue);
    final plannerFields = isOpenPlanner
        ? _decodePlannerFields(map['fields'])
        : const <WaypointPlannerField>[];
    return WaypointTestAction(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      submitLabel: submitLabel,
      noteField: _decodeNoteField(map['fields']),
      assetPath: map['asset'] is String ? map['asset'] as String : null,
      plannerFields: plannerFields,
    );
  }

  static List<WaypointTestAction> _decodeActions(Object? value) {
    if (value is! List) {
      return const <WaypointTestAction>[];
    }
    return value
        .map(_tryDecodeAction)
        .whereType<WaypointTestAction>()
        .toList(growable: false);
  }

  static WaypointTestAction? _tryDecodeAction(Object? value) {
    try {
      return decodeAction(value);
    } on FormatException {
      return null;
    }
  }

  static List<WaypointPermissionAction> _decodePermissionActions(
    Object? value,
  ) {
    if (value is! List) {
      return const <WaypointPermissionAction>[];
    }
    return value
        .map(_tryDecodePermissionAction)
        .whereType<WaypointPermissionAction>()
        .toList(growable: false);
  }

  static WaypointPermissionAction? _tryDecodePermissionAction(Object? value) {
    if (value is! Map) {
      return null;
    }
    final map = _asMap(value);
    final id = _optionalString(map['id']);
    final label = _optionalString(map['label']);
    final reason = _optionalString(map['reason']);
    if (id == null || label == null || reason == null) {
      return null;
    }
    return WaypointPermissionAction(id: id, label: label, reason: reason);
  }

  static WaypointNoteField? _decodeNoteField(Object? value) {
    if (value is! List) {
      return null;
    }
    for (final entry in value) {
      if (entry is! Map) {
        continue;
      }
      final map = _asMap(entry);
      if (map['id'] != 'note' ||
          map['type'] != 'multiline' ||
          map['required'] != true ||
          map['label'] is! String ||
          map['placeholder'] is! String) {
        continue;
      }
      return WaypointNoteField(
        id: map['id'] as String,
        type: map['type'] as String,
        label: map['label'] as String,
        placeholder: map['placeholder'] as String,
        isRequired: map['required'] as bool,
      );
    }
    return null;
  }

  static List<WaypointPlannerField> _decodePlannerFields(Object? value) {
    if (value is! List) {
      return const <WaypointPlannerField>[];
    }
    return value
        .map(_tryDecodePlannerField)
        .whereType<WaypointPlannerField>()
        .toList(growable: false);
  }

  static WaypointPlannerField? _tryDecodePlannerField(Object? value) {
    if (value is! Map) {
      return null;
    }
    final map = _asMap(value);
    final id = map['id'];
    final type = map['type'];
    final label = map['label'];
    if (id is! String ||
        id.trim().isEmpty ||
        type is! String ||
        type.trim().isEmpty ||
        label is! String ||
        label.trim().isEmpty ||
        !_isSupportedPlannerField(id, type)) {
      return null;
    }
    return WaypointPlannerField(
      id: id,
      type: type,
      label: label,
      placeholder: map['placeholder'] is String
          ? map['placeholder'] as String
          : null,
      initialValue: _optionalInt(map['initialValue']),
      min: _optionalInt(map['min']),
      max: _optionalInt(map['max']),
    );
  }

  static bool _isSupportedPlannerField(String id, String type) =>
      (id == 'destination' && type == 'text') ||
      (id == 'dates' && type == 'date_range') ||
      (id == 'travellers' && type == 'stepper');

  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('Waypoint response was not an object');
  }

  static List<Object?> _asList(Object? value) {
    if (value is List<Object?>) {
      return value;
    }
    if (value is List) {
      return List<Object?>.from(value);
    }
    throw const FormatException('Waypoint response field was not a list');
  }

  static List<String> _strings(Object? value) => value == null
      ? const <String>[]
      : _asList(value).map((entry) => _string(entry)).toList(growable: false);

  static List<String> _searchSuggestions(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];

  static WaypointChecklistItem _decodeChecklistItem(Object? value) {
    if (value is String) {
      return WaypointChecklistItem(title: value);
    }
    final map = _asMap(value);
    return WaypointChecklistItem(
      title: _string(map['title'] ?? map['label']),
      detail: _optionalString(map['detail']),
      isComplete: map['done'] == true || map['isComplete'] == true,
    );
  }

  static WaypointDestinationKind _destinationKind(String value) =>
      switch (value.toLowerCase()) {
        'coast' || 'beach' => WaypointDestinationKind.coast,
        'mountain' => WaypointDestinationKind.mountain,
        'nature' => WaypointDestinationKind.nature,
        'culture' || 'heritage' => WaypointDestinationKind.culture,
        'stay' => WaypointDestinationKind.stay,
        'food' => WaypointDestinationKind.food,
        _ => WaypointDestinationKind.city,
      };

  static String _string(Object? value) => value is String ? value : '$value';

  static String _requiredNonBlankString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    throw const FormatException('Waypoint planner action metadata was invalid');
  }

  static String _requiredOpenPlannerType(Object? value) {
    if (value is String && value == 'bottom_sheet') {
      return value;
    }
    throw const FormatException('Waypoint planner action type was invalid');
  }

  static String? _optionalString(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static int? _optionalInt(Object? value) => value is int ? value : null;

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.parse('$value');
}
