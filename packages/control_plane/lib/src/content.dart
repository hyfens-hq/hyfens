import 'dart:convert';

import 'encoding.dart';

/// Storage collection for typed editorial records.
///
/// Editorial authorization uses `contentAdminScope` from `domain.dart`; it is
/// intentionally separate from release, rollout, and delivery authority.
const String contentCollection = 'content';
const int contentMarkdownMaxBytes = 64 * 1024;

enum ContentKind { blog, news }

enum ContentStatus { draft, published, archived }

ContentKind parseContentKind(String value) => switch (value) {
  'blog' => ContentKind.blog,
  'news' => ContentKind.news,
  _ => throw const FormatException('Invalid content kind'),
};

ContentStatus parseContentStatus(String value) => switch (value) {
  'draft' => ContentStatus.draft,
  'published' => ContentStatus.published,
  'archived' => ContentStatus.archived,
  _ => throw const FormatException('Invalid content status'),
};

/// Metadata displayed with an editorial entry's byline.
final class ContentAuthorMetadata {
  ContentAuthorMetadata({
    required String id,
    required String name,
    String? avatarUrl,
    String? bio,
  }) : id = requireNonEmpty(id, 'content author ID', maxLength: 128),
       name = _text(name, 'content author name', 128),
       avatarUrl = _optionalUrl(avatarUrl, 'content author avatar URL'),
       bio = _optionalText(bio, 'content author bio', 512);

  final String id;
  final String name;
  final String? avatarUrl;
  final String? bio;

  ContentAuthorMetadata copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? bio,
  }) => ContentAuthorMetadata(
    id: id ?? this.id,
    name: name ?? this.name,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    bio: bio ?? this.bio,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'bio': bio,
  };

  static ContentAuthorMetadata fromJson(Map<String, Object?> value) =>
      ContentAuthorMetadata(
        id: _requiredString(value, 'id', 'content author ID'),
        name: _requiredString(value, 'name', 'content author name'),
        avatarUrl: _optionalString(value, 'avatarUrl'),
        bio: _optionalString(value, 'bio'),
      );
}

/// Non-rendering hero information. The client decides how to render the URL;
/// the API never turns this metadata into HTML.
final class ContentHeroMetadata {
  ContentHeroMetadata({String? url, String? alt, String? credit})
    : url = _optionalUrl(url, 'content hero URL'),
      alt = _optionalText(alt, 'content hero alt text', 256),
      credit = _optionalText(credit, 'content hero credit', 128);

  final String? url;
  final String? alt;
  final String? credit;

  Map<String, Object?> toJson() => <String, Object?>{
    'url': url,
    'alt': alt,
    'credit': credit,
  };

  static ContentHeroMetadata fromJson(Map<String, Object?> value) =>
      ContentHeroMetadata(
        url: _optionalString(value, 'url'),
        alt: _optionalString(value, 'alt'),
        credit: _optionalString(value, 'credit'),
      );
}

/// Search/social metadata kept as data, never interpolated into a document.
final class ContentSeoMetadata {
  ContentSeoMetadata({
    String? title,
    String? description,
    String? canonicalUrl,
    bool noIndex = false,
  }) : title = _optionalText(title, 'content SEO title', 200),
       description = _optionalText(description, 'content SEO description', 320),
       canonicalUrl = _optionalUrl(
         canonicalUrl,
         'content SEO canonical URL',
         allowRelative: false,
       ),
       noIndex = noIndex;

  final String? title;
  final String? description;
  final String? canonicalUrl;
  final bool noIndex;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'description': description,
    'canonicalUrl': canonicalUrl,
    'noIndex': noIndex,
  };

  static ContentSeoMetadata fromJson(Map<String, Object?> value) =>
      ContentSeoMetadata(
        title: _optionalString(value, 'title'),
        description: _optionalString(value, 'description'),
        canonicalUrl: _optionalString(value, 'canonicalUrl'),
        noIndex: _optionalBool(value, 'noIndex') ?? false,
      );
}

/// Fields accepted from an editorial client. Identity, organization, status,
/// and lifecycle timestamps are owned by [ControlPlaneService].
final class ContentWrite {
  ContentWrite({
    required String title,
    required String slug,
    required String excerpt,
    required String body,
    this.kind,
    Iterable<String>? tags,
    this.author,
    this.hero,
    this.seo,
  }) : title = _text(title, 'content title', 200),
       slug = slug.trim(),
       excerpt = _text(excerpt, 'content excerpt', 600, allowEmpty: true),
       body = _markdown(body),
       tags = tags == null ? null : _tags(tags);

  final String title;
  final String slug;
  final String excerpt;
  final String body;
  final ContentKind? kind;
  final Set<String>? tags;
  final ContentAuthorMetadata? author;
  final ContentHeroMetadata? hero;
  final ContentSeoMetadata? seo;
}

/// The durable, organization-scoped editorial record.
final class ContentRecord {
  ContentRecord({
    required String id,
    required String organizationId,
    required ContentKind kind,
    required String slug,
    required ContentStatus status,
    required String title,
    required String excerpt,
    required String body,
    required Iterable<String> tags,
    required ContentAuthorMetadata author,
    required ContentHeroMetadata hero,
    required ContentSeoMetadata seo,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime? publishedAt,
    required DateTime? archivedAt,
  }) : id = requireOpaqueId(id, 'content ID'),
       organizationId = requireOpaqueId(
         organizationId,
         'content organization ID',
       ),
       slug = normalizeContentSlug(slug),
       title = _text(title, 'content title', 200),
       excerpt = _text(excerpt, 'content excerpt', 600, allowEmpty: true),
       body = _markdown(body),
       tags = _tags(tags),
       kind = kind,
       status = status,
       author = author,
       hero = hero,
       seo = seo,
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       publishedAt = publishedAt?.toUtc(),
       archivedAt = archivedAt?.toUtc() {
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw const FormatException(
        'Content updated timestamp precedes creation',
      );
    }
    if (status == ContentStatus.published && this.publishedAt == null) {
      throw const FormatException('Published content is missing publishedAt');
    }
    if (status == ContentStatus.archived && this.archivedAt == null) {
      throw const FormatException('Archived content is missing archivedAt');
    }
    if (this.publishedAt != null &&
        this.publishedAt!.isBefore(this.createdAt)) {
      throw const FormatException('Content published timestamp is invalid');
    }
    if (this.archivedAt != null && this.archivedAt!.isBefore(this.createdAt)) {
      throw const FormatException('Content archived timestamp is invalid');
    }
  }

  final String id;
  final String organizationId;
  final ContentKind kind;
  final String slug;
  final ContentStatus status;
  final String title;
  final String excerpt;
  final String body;
  final Set<String> tags;
  final ContentAuthorMetadata author;
  final ContentHeroMetadata hero;
  final ContentSeoMetadata seo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final DateTime? archivedAt;

  /// Alias that makes the Markdown storage contract explicit to Dart callers.
  String get markdownBody => body;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'kind': kind.name,
    'slug': slug,
    'status': status.name,
    'title': title,
    'excerpt': excerpt,
    'body': body,
    'tags': tags.toList()..sort(),
    'author': author.toJson(),
    'hero': hero.toJson(),
    'seo': seo.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'publishedAt': publishedAt?.toIso8601String(),
    'archivedAt': archivedAt?.toIso8601String(),
  };

  /// Public projection used by the unauthenticated publication endpoint.
  /// Tenant and internal storage identifiers are deliberately omitted.
  Map<String, Object?> toPublicJson() => <String, Object?>{
    'kind': kind.name,
    'slug': slug,
    'status': status.name,
    'title': title,
    'excerpt': excerpt,
    'body': body,
    'tags': tags.toList()..sort(),
    'author': author.toJson(),
    'hero': hero.toJson(),
    'seo': seo.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'publishedAt': publishedAt?.toIso8601String(),
  };

  static ContentRecord fromJson(Map<String, Object?> value) {
    final tags = value['tags'];
    if (tags is! List<Object?> || tags.any((item) => item is! String)) {
      throw const FormatException('Invalid content tags');
    }
    return ContentRecord(
      id: _requiredString(value, 'id', 'content ID'),
      organizationId: _requiredString(
        value,
        'organizationId',
        'content organization ID',
      ),
      kind: parseContentKind(_requiredString(value, 'kind', 'content kind')),
      slug: _requiredString(value, 'slug', 'content slug'),
      status: parseContentStatus(
        _requiredString(value, 'status', 'content status'),
      ),
      title: _requiredString(value, 'title', 'content title'),
      excerpt: _requiredString(value, 'excerpt', 'content excerpt'),
      body: _requiredString(value, 'body', 'content body'),
      tags: tags.cast<String>(),
      author: ContentAuthorMetadata.fromJson(
        _requiredObject(value, 'author', 'content author'),
      ),
      hero: ContentHeroMetadata.fromJson(
        _requiredObject(value, 'hero', 'content hero'),
      ),
      seo: ContentSeoMetadata.fromJson(
        _requiredObject(value, 'seo', 'content SEO'),
      ),
      createdAt: _requiredTime(value, 'createdAt', 'content createdAt'),
      updatedAt: _requiredTime(value, 'updatedAt', 'content updatedAt'),
      publishedAt: _optionalTime(value, 'publishedAt', 'content publishedAt'),
      archivedAt: _optionalTime(value, 'archivedAt', 'content archivedAt'),
    );
  }
}

/// Normalizes only ASCII URL-safe slugs. This keeps IDs and public paths
/// deterministic and prevents path separators or control characters entering
/// the storage key or route.
String normalizeContentSlug(String value) {
  var normalized = value.trim().toLowerCase();
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  normalized = normalized.replaceFirst(RegExp(r'^-+'), '');
  normalized = normalized.replaceFirst(RegExp(r'-+$'), '');
  if (normalized.isEmpty || normalized.length > 96) {
    throw const FormatException('Invalid content slug');
  }
  return normalized;
}

String contentRecordId({
  required String organizationId,
  required ContentKind kind,
  required String slug,
}) =>
    'cnt_${sha256Hex(utf8.encode('$organizationId:${kind.name}:$slug')).substring(0, 32)}';

String _text(
  String value,
  String field,
  int maxLength, {
  bool allowEmpty = false,
}) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    if (allowEmpty) return '';
    throw FormatException('Invalid $field');
  }
  return requireNonEmpty(normalized, field, maxLength: maxLength);
}

String _markdown(String value) {
  if (value.trim().isEmpty ||
      utf8.encode(value).length > contentMarkdownMaxBytes) {
    throw const FormatException('Invalid content Markdown body');
  }
  if (value.contains('\u0000') ||
      RegExp(
        r'<\s*/?\s*[A-Za-z][^>]*>',
        caseSensitive: false,
      ).hasMatch(value) ||
      value.contains('<!--') ||
      RegExp(
        r'\b(?:javascript|vbscript|data):',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw const FormatException(
      'Content Markdown must not contain raw HTML or unsafe URL schemes',
    );
  }
  return value;
}

Set<String> _tags(Iterable<String> values) {
  final normalized = <String>{};
  for (final value in values) {
    final tag = value.trim().toLowerCase();
    if (tag.isEmpty ||
        tag.length > 48 ||
        !RegExp(r'^[a-z0-9][a-z0-9 _-]*$').hasMatch(tag)) {
      throw const FormatException('Invalid content tag');
    }
    normalized.add(tag);
  }
  if (normalized.length > 16) {
    throw const FormatException('Content has too many tags');
  }
  return Set.unmodifiable(normalized);
}

String? _optionalText(String? value, String field, int maxLength) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  return requireNonEmpty(normalized, field, maxLength: maxLength);
}

String? _optionalUrl(String? value, String field, {bool allowRelative = true}) {
  final normalized = _optionalText(value, field, 2048);
  if (normalized == null) return null;
  if (normalized.contains(RegExp(r'\s'))) {
    throw FormatException('Invalid $field');
  }
  final parsed = Uri.tryParse(normalized);
  if (parsed == null ||
      parsed.userInfo.isNotEmpty ||
      (parsed.host.isEmpty && parsed.isAbsolute)) {
    throw FormatException('Invalid $field');
  }
  if (parsed.isAbsolute) {
    final loopback =
        parsed.host == 'localhost' ||
        parsed.host == '127.0.0.1' ||
        parsed.host == '::1' ||
        parsed.host == '[::1]';
    if (parsed.scheme != 'https' && !(loopback && parsed.scheme == 'http')) {
      throw FormatException('Invalid $field');
    }
  } else if (!allowRelative ||
      !normalized.startsWith('/') ||
      normalized.startsWith('//')) {
    throw FormatException('Invalid $field');
  }
  return normalized;
}

String _requiredString(Map<String, Object?> value, String key, String field) {
  final item = value[key];
  if (item is! String) throw FormatException('Invalid $field');
  return item;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item == null) return null;
  if (item is! String) throw FormatException('Invalid $key');
  return item;
}

bool? _optionalBool(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item == null) return null;
  if (item is! bool) throw FormatException('Invalid $key');
  return item;
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> value,
  String key,
  String field,
) {
  final item = value[key];
  if (item is! Map) throw FormatException('Invalid $field');
  return <String, Object?>{
    for (final entry in item.entries) '${entry.key}': entry.value,
  };
}

DateTime _requiredTime(Map<String, Object?> value, String key, String field) {
  final item = value[key];
  if (item is! String) throw FormatException('Invalid $field');
  final parsed = DateTime.tryParse(item);
  if (parsed == null) throw FormatException('Invalid $field');
  return parsed;
}

DateTime? _optionalTime(Map<String, Object?> value, String key, String field) {
  final item = value[key];
  if (item == null) return null;
  if (item is! String) throw FormatException('Invalid $field');
  final parsed = DateTime.tryParse(item);
  if (parsed == null) throw FormatException('Invalid $field');
  return parsed;
}
