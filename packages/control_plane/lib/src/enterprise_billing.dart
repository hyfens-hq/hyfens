import 'dart:async';
import 'dart:convert';

import 'cloud_plans.dart';
import 'encoding.dart';
import 'errors.dart';
import 'persistence.dart';

const String enterpriseQuoteCollection = 'enterprise_quotes';
const String enterpriseQuoteVersionCollection = 'enterprise_quote_versions';
const String enterpriseContractCollection = 'enterprise_contracts';
const String enterpriseProviderMappingCollection =
    'enterprise_provider_mappings';
const String enterpriseApprovedCurrency = 'USD';

const Set<String> _providerStatuses = <String>{
  'created',
  'authenticated',
  'active',
  'pending',
  'halted',
  'cancel_requested',
  'cancelled',
  'paused',
  'completed',
  'expired',
};

enum EnterpriseQuoteStatus {
  draft,
  issued,
  viewed,
  accepted,
  rejected,
  expired,
  withdrawn,
  superseded,
}

extension EnterpriseQuoteStatusWire on EnterpriseQuoteStatus {
  String get wireValue => name;
}

enum EnterpriseContractStatus {
  pendingPayment,
  active,
  cancellationScheduled,
  expired,
  cancelled,
  superseded,
}

extension EnterpriseContractStatusWire on EnterpriseContractStatus {
  String get wireValue => switch (this) {
    EnterpriseContractStatus.pendingPayment => 'pending_payment',
    EnterpriseContractStatus.active => 'active',
    EnterpriseContractStatus.cancellationScheduled => 'cancellation_scheduled',
    EnterpriseContractStatus.expired => 'expired',
    EnterpriseContractStatus.cancelled => 'cancelled',
    EnterpriseContractStatus.superseded => 'superseded',
  };
}

/// Only existing Cloud countable dimensions may be customized by an
/// Enterprise contract. Unknown keys are rejected instead of becoming an
/// unreviewed entitlement surface.
final class EnterpriseEntitlementSnapshot {
  EnterpriseEntitlementSnapshot(Map<String, CloudLimit> limits)
    : limits = Map.unmodifiable(<String, CloudLimit>{...limits}) {
    if (this.limits.keys.any((key) => !_supportedLimitKeys.contains(key))) {
      throw const FormatException('Unsupported Enterprise entitlement key');
    }
  }

  final Map<String, CloudLimit> limits;

  Map<String, Object?> toJson() => <String, Object?>{
    'limits': <String, Object?>{
      for (final entry in limits.entries) entry.key: entry.value.toJson(),
    },
  };

  static EnterpriseEntitlementSnapshot fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Enterprise entitlement snapshot is invalid');
    }
    final rawLimits = value['limits'];
    if (rawLimits is! Map) {
      throw const FormatException('Enterprise entitlement limits are invalid');
    }
    final limits = <String, CloudLimit>{};
    for (final entry in rawLimits.entries) {
      if (entry.key is! String || !_supportedLimitKeys.contains(entry.key)) {
        throw const FormatException('Unsupported Enterprise entitlement key');
      }
      limits[entry.key as String] = CloudLimit.fromJson(entry.value);
    }
    return EnterpriseEntitlementSnapshot(limits);
  }
}

const Set<String> _supportedLimitKeys = <String>{
  cloudApplicationsLimitKey,
  cloudEnvironmentsPerApplicationLimitKey,
  cloudMembersLimitKey,
};

/// Commercial terms supplied by an authorized operator. Amounts are always
/// integer minor units; the browser never supplies these terms as authority.
final class EnterpriseQuoteTerms {
  EnterpriseQuoteTerms({
    required this.currency,
    required this.recurringAmountMinor,
    required this.interval,
    required this.validUntil,
    required this.entitlements,
    this.contactName,
    this.contactEmail,
    this.termMonths,
    this.totalCount,
    this.upfrontAmountMinor,
    this.supportLevel,
    this.customerNotes,
    this.internalNotes,
  }) {
    _validate();
  }

  final String currency;
  final int recurringAmountMinor;
  final String interval;
  final DateTime validUntil;
  final EnterpriseEntitlementSnapshot entitlements;
  final String? contactName;
  final String? contactEmail;
  final int? termMonths;
  final int? totalCount;
  final int? upfrontAmountMinor;
  final String? supportLevel;
  final String? customerNotes;
  final String? internalNotes;

  Map<String, Object?> toJson() => <String, Object?>{
    'currency': currency,
    'recurringAmountMinor': recurringAmountMinor,
    'interval': interval,
    'validUntil': validUntil.toUtc().toIso8601String(),
    'entitlementSnapshot': entitlements.toJson(),
    if (contactName != null) 'contactName': contactName,
    if (contactEmail != null) 'contactEmail': contactEmail,
    if (termMonths != null) 'termMonths': termMonths,
    if (totalCount != null) 'totalCount': totalCount,
    if (upfrontAmountMinor != null) 'upfrontAmountMinor': upfrontAmountMinor,
    if (supportLevel != null) 'supportLevel': supportLevel,
    if (customerNotes != null) 'customerNotes': customerNotes,
    if (internalNotes != null) 'internalNotes': internalNotes,
  };

  void _validate() {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_CURRENCY',
        'Enterprise quote currency must be a three-letter uppercase code',
        statusCode: 422,
      );
    }
    if (currency != enterpriseApprovedCurrency) {
      throw const ControlPlaneException(
        'INVALID_BILLING_CURRENCY',
        'Enterprise quotes currently support the approved USD Cloud currency only',
        statusCode: 422,
      );
    }
    if (recurringAmountMinor <= 0 || recurringAmountMinor > 100000000000) {
      throw const ControlPlaneException(
        'INVALID_BILLING_AMOUNT',
        'Enterprise recurring amount is outside the supported range',
        statusCode: 422,
      );
    }
    if (interval != 'monthly') {
      throw const ControlPlaneException(
        'INVALID_BILLING_INTERVAL',
        'Enterprise quotes currently support monthly billing only',
        statusCode: 422,
      );
    }
    if (!validUntil.toUtc().isAfter(DateTime.fromMillisecondsSinceEpoch(0))) {
      throw const ControlPlaneException(
        'INVALID_QUOTE_VALIDITY',
        'Enterprise quote validity must be a real future date',
        statusCode: 422,
      );
    }
    _optionalPositive(termMonths, 'Enterprise contract term');
    _optionalPositive(totalCount, 'Enterprise billing cycle count');
    if (termMonths != null && totalCount != null && totalCount != termMonths) {
      throw const ControlPlaneException(
        'INVALID_QUOTE_TERM',
        'Enterprise term and billing cycle count must agree',
        statusCode: 422,
      );
    }
    if (upfrontAmountMinor != null &&
        (upfrontAmountMinor! < 0 || upfrontAmountMinor! > 100000000000)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_AMOUNT',
        'Enterprise upfront amount is outside the supported range',
        statusCode: 422,
      );
    }
    _optionalText(contactName, 'Enterprise contact name', 160);
    if (contactEmail != null &&
        (!contactEmail!.contains('@') || contactEmail!.length > 320)) {
      throw const ControlPlaneException(
        'INVALID_QUOTE_CONTACT',
        'Enterprise contact email is invalid',
        statusCode: 422,
      );
    }
    _optionalText(contactEmail, 'Enterprise contact email', 320);
    _optionalText(supportLevel, 'Enterprise support level', 120);
    _optionalText(customerNotes, 'Enterprise customer notes', 4000);
    _optionalText(internalNotes, 'Enterprise internal notes', 4000);
  }

  void _optionalPositive(int? value, String field) {
    if (value != null && (value <= 0 || value > 1200)) {
      throw ControlPlaneException(
        'INVALID_QUOTE_TERM',
        '$field is invalid',
        statusCode: 422,
      );
    }
  }

  void _optionalText(String? value, String field, int maxLength) {
    if (value != null &&
        (value.isEmpty ||
            value.length > maxLength ||
            value.contains(RegExp(r'[\u0000\r\n]')))) {
      throw ControlPlaneException(
        'INVALID_QUOTE_FIELD',
        '$field is invalid',
        statusCode: 422,
      );
    }
  }
}

final class EnterpriseProviderEventResult {
  const EnterpriseProviderEventResult({
    required this.organizationId,
    required this.contract,
    required this.subscription,
  });

  final String organizationId;
  final Map<String, Object?> contract;
  final Map<String, Object?> subscription;
}

/// Owns Enterprise commercial records while leaving outbound Razorpay calls
/// in the existing private Cloud web adapter. Provider identifiers are
/// accepted only after a server-created contract is resolved.
final class EnterpriseBillingService {
  EnterpriseBillingService(
    this.store, {
    DateTime Function()? clock,
    this.deploymentModel = DeploymentModel.selfHosted,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final DateTime Function() _clock;
  final DeploymentModel deploymentModel;
  Future<void> _writeTail = Future<void>.value();

  Future<Map<String, Object?>> createQuote({
    required String organizationId,
    required EnterpriseQuoteTerms terms,
    required String idempotencyKey,
    String? inquiryId,
  }) => _serialized(() async {
    _requireCloud();
    _organization(organizationId);
    final normalizedIdempotency = _text(
      idempotencyKey,
      'Enterprise quote idempotency key',
      256,
    );
    await _requireOrganization(organizationId);
    final normalizedInquiryId = inquiryId == null
        ? null
        : requireOpaqueId(inquiryId, 'Enterprise inquiry ID');
    if (normalizedInquiryId != null) {
      final inquiry = await store.readJson(
        'enterprise_inquiries',
        normalizedInquiryId,
      );
      if (inquiry == null) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Enterprise inquiry was not found',
          statusCode: 404,
        );
      }
      final inquiryOrganizationId = inquiry['organizationId'];
      if (inquiryOrganizationId is String &&
          inquiryOrganizationId != organizationId) {
        throw const ControlPlaneException(
          'ENTERPRISE_QUOTE_SCOPE_MISMATCH',
          'Enterprise inquiry belongs to another organization',
          statusCode: 409,
        );
      }
    }
    final quoteId =
        'eqt_${sha256Hex(utf8.encode('$organizationId:$normalizedIdempotency')).substring(0, 32)}';
    final existing = await store.readJson(enterpriseQuoteCollection, quoteId);
    if (existing != null) {
      if (existing['organizationId'] != organizationId ||
          existing['idempotencyKey'] != normalizedIdempotency) {
        throw const ControlPlaneException(
          'ENTERPRISE_QUOTE_CONFLICT',
          'The quote idempotency key was already used for another quote',
          statusCode: 409,
        );
      }
      final versionId = existing['currentVersionId'];
      if (versionId is! String)
        _stateCorrupt('Enterprise quote has no version');
      final version = await store.readJson(
        enterpriseQuoteVersionCollection,
        versionId,
      );
      if (version == null ||
          canonicalJson(version['terms']) != canonicalJson(terms.toJson())) {
        throw const ControlPlaneException(
          'ENTERPRISE_QUOTE_CONFLICT',
          'The quote idempotency key was reused with different terms',
          statusCode: 409,
        );
      }
      return _envelope(existing, version);
    }

    final now = _clock().toUtc();
    final digest = sha256Hex(
      utf8.encode('$organizationId:$normalizedIdempotency'),
    );
    final versionId = 'eqv_${digest.substring(0, 32)}_v1';
    final version = <String, Object?>{
      'id': versionId,
      'quoteId': quoteId,
      'version': 1,
      'status': EnterpriseQuoteStatus.draft.wireValue,
      'terms': terms.toJson(),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    final quote = <String, Object?>{
      'id': quoteId,
      'quoteNumber': 'HYF-${now.year}-${digest.substring(0, 8).toUpperCase()}',
      'organizationId': organizationId,
      if (normalizedInquiryId != null) 'inquiryId': normalizedInquiryId,
      'idempotencyKey': normalizedIdempotency,
      'currentVersionId': versionId,
      'currentVersion': 1,
      'status': EnterpriseQuoteStatus.draft.wireValue,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    try {
      await store.createJson(enterpriseQuoteCollection, quoteId, quote);
      await store.createJson(
        enterpriseQuoteVersionCollection,
        versionId,
        version,
      );
    } on StorageConflict {
      final concurrent = await store.readJson(
        enterpriseQuoteCollection,
        quoteId,
      );
      if (concurrent == null) rethrow;
      final concurrentVersionId = concurrent['currentVersionId'];
      final concurrentVersion = concurrentVersionId is String
          ? await store.readJson(
              enterpriseQuoteVersionCollection,
              concurrentVersionId,
            )
          : null;
      if (concurrent['organizationId'] != organizationId ||
          concurrentVersion == null ||
          canonicalJson(concurrentVersion['terms']) !=
              canonicalJson(terms.toJson())) {
        throw const ControlPlaneException(
          'ENTERPRISE_QUOTE_CONFLICT',
          'Concurrent Enterprise quote creation conflicted with the request',
          statusCode: 409,
        );
      }
      return _envelope(concurrent, concurrentVersion);
    }
    return _envelope(quote, version);
  });

  Future<Map<String, Object?>> issueQuote({required String quoteId}) =>
      _serialized(() async {
        _requireCloud();
        final quote = await _quote(quoteId);
        final version = await _currentVersion(quote);
        final status = version['status'];
        if (status == EnterpriseQuoteStatus.issued.wireValue ||
            status == EnterpriseQuoteStatus.viewed.wireValue) {
          return _envelope(quote, version);
        }
        if (status != EnterpriseQuoteStatus.draft.wireValue) {
          throw const ControlPlaneException(
            'ENTERPRISE_QUOTE_NOT_ISSUABLE',
            'Only a draft Enterprise quote can be issued',
            statusCode: 409,
          );
        }
        final now = _clock().toUtc().toIso8601String();
        final issuedVersion = <String, Object?>{
          ...version,
          'status': EnterpriseQuoteStatus.issued.wireValue,
          'issuedAt': now,
          'updatedAt': now,
        };
        final updatedQuote = <String, Object?>{
          ...quote,
          'status': EnterpriseQuoteStatus.issued.wireValue,
          'updatedAt': now,
        };
        await store.replaceJson(
          enterpriseQuoteVersionCollection,
          version['id']! as String,
          issuedVersion,
        );
        await store.replaceJson(
          enterpriseQuoteCollection,
          quote['id']! as String,
          updatedQuote,
        );
        return _envelope(updatedQuote, issuedVersion);
      });

  /// Revising an issued quote supersedes its current version and creates a
  /// fresh draft. An accepted version remains an immutable commercial record
  /// while a new draft is attached to the same quote for an amendment. Draft
  /// edits remain mutable until issue; issued terms never change in place.
  Future<Map<String, Object?>> reviseQuote({
    required String quoteId,
    required EnterpriseQuoteTerms terms,
  }) => _serialized(() async {
    _requireCloud();
    final quote = await _quote(quoteId);
    final current = await _currentVersion(quote);
    final currentStatus = current['status'];
    if (currentStatus == EnterpriseQuoteStatus.draft.wireValue) {
      final updated = <String, Object?>{
        ...current,
        'terms': terms.toJson(),
        'updatedAt': _clock().toUtc().toIso8601String(),
      };
      await store.replaceJson(
        enterpriseQuoteVersionCollection,
        current['id']! as String,
        updated,
      );
      return _envelope(quote, updated);
    }
    final keepAcceptedVersion =
        currentStatus == EnterpriseQuoteStatus.accepted.wireValue;
    if (currentStatus != EnterpriseQuoteStatus.issued.wireValue &&
        currentStatus != EnterpriseQuoteStatus.viewed.wireValue &&
        !keepAcceptedVersion) {
      throw const ControlPlaneException(
        'ENTERPRISE_QUOTE_NOT_REVISIONABLE',
        'The current Enterprise quote version cannot be revised',
        statusCode: 409,
      );
    }
    final now = _clock().toUtc();
    final nextVersionNumber = (current['version'] as int? ?? 0) + 1;
    final nextId =
        'eqv_${sha256Hex(utf8.encode('${quote['id']}:$nextVersionNumber:${canonicalJson(terms.toJson())}')).substring(0, 32)}_v$nextVersionNumber';
    final previous = keepAcceptedVersion
        ? current
        : <String, Object?>{
            ...current,
            'status': EnterpriseQuoteStatus.superseded.wireValue,
            'supersededAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          };
    final next = <String, Object?>{
      'id': nextId,
      'quoteId': quote['id'],
      'version': nextVersionNumber,
      'status': EnterpriseQuoteStatus.draft.wireValue,
      'terms': terms.toJson(),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    if (!keepAcceptedVersion) {
      await store.replaceJson(
        enterpriseQuoteVersionCollection,
        current['id']! as String,
        previous,
      );
    }
    await store.createJson(enterpriseQuoteVersionCollection, nextId, next);
    final updatedQuote = <String, Object?>{
      ...quote,
      'currentVersionId': nextId,
      'currentVersion': nextVersionNumber,
      'status': EnterpriseQuoteStatus.draft.wireValue,
      'updatedAt': now.toIso8601String(),
    };
    await store.replaceJson(
      enterpriseQuoteCollection,
      quote['id']! as String,
      updatedQuote,
    );
    return _envelope(updatedQuote, next);
  });

  Future<Map<String, Object?>> withdrawQuote({required String quoteId}) =>
      _serialized(() async {
        _requireCloud();
        final quote = await _quote(quoteId);
        final version = await _currentVersion(quote);
        if (version['status'] == EnterpriseQuoteStatus.withdrawn.wireValue) {
          return _envelope(quote, version);
        }
        if (version['status'] != EnterpriseQuoteStatus.issued.wireValue &&
            version['status'] != EnterpriseQuoteStatus.viewed.wireValue) {
          throw const ControlPlaneException(
            'ENTERPRISE_QUOTE_NOT_WITHDRAWABLE',
            'Only an issued Enterprise quote can be withdrawn',
            statusCode: 409,
          );
        }
        return _setQuoteStatus(quote, version, EnterpriseQuoteStatus.withdrawn);
      });

  Future<Map<String, Object?>> rejectQuote({
    required String organizationId,
    required String quoteId,
    required String versionId,
  }) => _serialized(() async {
    _requireCloud();
    final quote = await _quote(quoteId);
    _requireQuoteOrganization(quote, organizationId);
    final version = await _version(versionId);
    _requireCurrentVersion(quote, version);
    _ensureAcceptableVersion(version);
    final result = await _setQuoteStatus(
      quote,
      version,
      EnterpriseQuoteStatus.rejected,
    );
    return _customerEnvelope(
      result['quote']! as Map<String, Object?>,
      result['version']! as Map<String, Object?>,
    );
  });

  Future<Map<String, Object?>> readCustomerQuote({
    required String organizationId,
    required String quoteId,
  }) => _serialized(() async {
    _requireCloud();
    final quote = await _quote(quoteId);
    _requireQuoteOrganization(quote, organizationId);
    final version = await _currentVersion(quote);
    final status = version['status'];
    if (status == EnterpriseQuoteStatus.issued.wireValue) {
      final now = _clock().toUtc().toIso8601String();
      final viewed = <String, Object?>{
        ...version,
        'status': EnterpriseQuoteStatus.viewed.wireValue,
        'viewedAt': now,
        'updatedAt': now,
      };
      final viewedQuote = <String, Object?>{
        ...quote,
        'status': EnterpriseQuoteStatus.viewed.wireValue,
        'updatedAt': now,
      };
      await store.replaceJson(
        enterpriseQuoteVersionCollection,
        version['id']! as String,
        viewed,
      );
      await store.replaceJson(
        enterpriseQuoteCollection,
        quote['id']! as String,
        viewedQuote,
      );
      return _customerEnvelope(viewedQuote, viewed);
    }
    return _customerEnvelope(quote, version);
  });

  Future<List<Map<String, Object?>>> listCustomerQuotes({
    required String organizationId,
  }) async {
    _requireCloud();
    final result = <Map<String, Object?>>[];
    for (final quote in await _quotesFor(organizationId)) {
      final version = await _currentVersion(quote);
      if (version['status'] == EnterpriseQuoteStatus.issued.wireValue ||
          version['status'] == EnterpriseQuoteStatus.viewed.wireValue ||
          version['status'] == EnterpriseQuoteStatus.accepted.wireValue) {
        result.add(_customerEnvelope(quote, version));
      }
    }
    return List.unmodifiable(result);
  }

  Future<List<Map<String, Object?>>> listOperatorQuotes() async {
    _requireCloud();
    final result = <Map<String, Object?>>[];
    for (final quote in await store.listJson(enterpriseQuoteCollection)) {
      final versionId = quote['currentVersionId'];
      if (versionId is! String)
        _stateCorrupt('Enterprise quote has no version');
      final version = await store.readJson(
        enterpriseQuoteVersionCollection,
        versionId,
      );
      if (version == null) _stateCorrupt('Enterprise quote version is missing');
      result.add(_envelope(quote, version));
    }
    result.sort(
      (left, right) =>
          '${right['updatedAt']}'.compareTo('${left['updatedAt']}'),
    );
    return List.unmodifiable(result);
  }

  Future<Map<String, Object?>> acceptQuote({
    required String organizationId,
    required String quoteId,
    required String versionId,
    required String actorId,
  }) => _serialized(() async {
    _requireCloud();
    _organization(organizationId);
    final quote = await _quote(quoteId);
    _requireQuoteOrganization(quote, organizationId);
    final version = await _version(versionId);
    _requireCurrentVersion(quote, version);
    if (version['status'] == EnterpriseQuoteStatus.accepted.wireValue) {
      final contract = await _contractForQuoteVersion(versionId);
      if (contract == null) _stateCorrupt('Accepted quote has no contract');
      return <String, Object?>{
        'quote': _customerEnvelope(quote, version),
        'contract': _customerContract(contract),
      };
    }
    _ensureAcceptableVersion(version);
    final terms = _terms(version);
    if (!terms.validUntil.toUtc().isAfter(_clock().toUtc())) {
      final expired = <String, Object?>{
        ...version,
        'status': EnterpriseQuoteStatus.expired.wireValue,
        'updatedAt': _clock().toUtc().toIso8601String(),
      };
      await store.replaceJson(
        enterpriseQuoteVersionCollection,
        version['id']! as String,
        expired,
      );
      await store.replaceJson(
        enterpriseQuoteCollection,
        quote['id']! as String,
        <String, Object?>{
          ...quote,
          'status': EnterpriseQuoteStatus.expired.wireValue,
          'updatedAt': _clock().toUtc().toIso8601String(),
        },
      );
      throw const ControlPlaneException(
        'ENTERPRISE_QUOTE_EXPIRED',
        'This Enterprise quote has expired and cannot be accepted',
        statusCode: 409,
      );
    }
    final now = _clock().toUtc();
    final accepted = <String, Object?>{
      ...version,
      'status': EnterpriseQuoteStatus.accepted.wireValue,
      'acceptedAt': now.toIso8601String(),
      'acceptedByUserId': _text(actorId, 'quote acceptance actor', 128),
      'updatedAt': now.toIso8601String(),
    };
    final acceptedQuote = <String, Object?>{
      ...quote,
      'status': EnterpriseQuoteStatus.accepted.wireValue,
      'updatedAt': now.toIso8601String(),
    };
    await store.replaceJson(
      enterpriseQuoteVersionCollection,
      version['id']! as String,
      accepted,
    );
    await store.replaceJson(
      enterpriseQuoteCollection,
      quote['id']! as String,
      acceptedQuote,
    );
    final contractId =
        'econ_${sha256Hex(utf8.encode('${quote['id']}:$versionId')).substring(0, 32)}';
    final contract = <String, Object?>{
      'id': contractId,
      'organizationId': organizationId,
      'quoteId': quoteId,
      'quoteVersionId': versionId,
      'status': EnterpriseContractStatus.pendingPayment.wireValue,
      'commercialSnapshot': terms.toJson(),
      'entitlementSnapshot': terms.entitlements.toJson(),
      'provider': 'razorpay',
      'providerPlanId': null,
      'providerSubscriptionId': null,
      'providerStatus': null,
      'providerCancelAtCycleEnd': false,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    final existingContract = await store.readJson(
      enterpriseContractCollection,
      contractId,
    );
    if (existingContract != null &&
        canonicalJson(existingContract['commercialSnapshot']) !=
            canonicalJson(contract['commercialSnapshot'])) {
      throw const ControlPlaneException(
        'ENTERPRISE_CONTRACT_CONFLICT',
        'The accepted quote already has a different contract snapshot',
        statusCode: 409,
      );
    }
    if (existingContract == null) {
      await store.createJson(
        enterpriseContractCollection,
        contractId,
        contract,
      );
    }
    final effectiveContract = existingContract ?? contract;
    return <String, Object?>{
      'quote': _customerEnvelope(acceptedQuote, accepted),
      'contract': _customerContract(effectiveContract),
    };
  });

  Future<Map<String, Object?>> linkProviderSubscription({
    required String contractId,
    required String providerSubscriptionId,
    required String providerPlanId,
    required String providerStatus,
    required int amountMinor,
    required String currency,
    required String interval,
    int? totalCount,
    int? paidCount,
    int? remainingCount,
    String? currentStartAt,
    String? currentEndAt,
    bool? cancelAtCycleEnd,
  }) => _serialized(() async {
    _requireCloud();
    final contract = await _contract(contractId);
    final status = _text(providerStatus, 'provider subscription status', 64);
    if (!<String>{'created', 'authenticated', 'pending'}.contains(status)) {
      throw const ControlPlaneException(
        'ENTERPRISE_PROVIDER_EVENT_REQUIRED',
        'Enterprise activation requires a verified provider event',
        statusCode: 409,
      );
    }
    final terms = _contractTerms(contract);
    _validateProviderTerms(
      terms: terms,
      amountMinor: amountMinor,
      currency: currency,
      interval: interval,
    );
    final normalizedSubscriptionId = _text(
      providerSubscriptionId,
      'provider subscription ID',
      128,
    );
    final normalizedPlanId = _text(providerPlanId, 'provider plan ID', 128);
    final contractPlanId = contract['providerPlanId'];
    if (contractPlanId is! String || contractPlanId != normalizedPlanId) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'The provider subscription plan does not match the Enterprise contract',
        statusCode: 409,
      );
    }
    final existingMapping = await _mapping(normalizedSubscriptionId);
    if (existingMapping != null) {
      if (existingMapping['contractId'] != contractId ||
          existingMapping['providerPlanId'] != normalizedPlanId) {
        throw const ControlPlaneException(
          'BILLING_PROVIDER_MAPPING_CONFLICT',
          'The provider subscription is already linked to another contract',
          statusCode: 409,
        );
      }
      final existingSubscription = await _subscription(
        normalizedSubscriptionId,
      );
      if (existingSubscription == null) {
        _stateCorrupt('Enterprise provider mapping has no subscription');
      }
      return <String, Object?>{
        'subscription': existingSubscription,
        'contract': _customerContract(contract),
      };
    }
    final linkedProviderSubscriptionId = contract['providerSubscriptionId'];
    if (linkedProviderSubscriptionId is String &&
        linkedProviderSubscriptionId != normalizedSubscriptionId) {
      throw const ControlPlaneException(
        'ENTERPRISE_CONTRACT_CONFLICT',
        'The Enterprise contract is already linked to another subscription',
        statusCode: 409,
      );
    }
    final organizationId = contract['organizationId'];
    if (organizationId is! String)
      _stateCorrupt('Enterprise contract has no organization');
    final now = _clock().toUtc().toIso8601String();
    final mappingId = _providerMappingId(normalizedSubscriptionId);
    final mapping = <String, Object?>{
      'id': mappingId,
      'organizationId': organizationId,
      'contractId': contractId,
      'provider': 'razorpay',
      'providerSubscriptionId': normalizedSubscriptionId,
      'providerPlanId': normalizedPlanId,
      'amountMinor': amountMinor,
      'currency': currency,
      'interval': interval,
      'createdAt': now,
      'updatedAt': now,
    };
    final subscription = <String, Object?>{
      'id': _subscriptionId(organizationId, normalizedSubscriptionId),
      'organizationId': organizationId,
      'provider': 'razorpay',
      'providerSubscriptionId': normalizedSubscriptionId,
      'providerPlanId': normalizedPlanId,
      'planId': null,
      'cloudPlanKey': cloudPlanEnterpriseKey,
      'enterpriseContractId': contractId,
      'deploymentModel': DeploymentModel.cloud.wireValue,
      'billingStatus': 'provider_managed',
      'status': status,
      'totalCount': totalCount,
      'paidCount': paidCount,
      'remainingCount': remainingCount,
      'currentStartAt': currentStartAt,
      'currentEndAt': currentEndAt,
      'cancelAtCycleEnd': cancelAtCycleEnd ?? false,
      'createdAt': now,
      'updatedAt': now,
    };
    await store.createJson(
      enterpriseProviderMappingCollection,
      mappingId,
      mapping,
    );
    await store.createJson(
      'billing_subscriptions',
      subscription['id']! as String,
      subscription,
    );
    final updatedContract = <String, Object?>{
      ...contract,
      'providerPlanId': normalizedPlanId,
      'providerSubscriptionId': normalizedSubscriptionId,
      'providerStatus': status,
      'providerAmountMinor': amountMinor,
      'providerCurrency': currency,
      'providerInterval': interval,
      'providerCancelAtCycleEnd': cancelAtCycleEnd ?? false,
      'updatedAt': now,
    };
    await store.replaceJson(
      enterpriseContractCollection,
      contractId,
      updatedContract,
    );
    return <String, Object?>{
      'subscription': subscription,
      'contract': _customerContract(updatedContract),
    };
  });

  /// Persists the exact Razorpay Plan selected for an accepted contract before
  /// a Subscription is created. This gives retries a durable provider-plan
  /// anchor and prevents a transient link failure from creating duplicates.
  Future<Map<String, Object?>> linkProviderPlan({
    required String contractId,
    required String providerPlanId,
    required int amountMinor,
    required String currency,
    required String interval,
  }) => _serialized(() async {
    _requireCloud();
    final contract = await _contract(contractId);
    final status = contract['status'];
    if (status != EnterpriseContractStatus.pendingPayment.wireValue) {
      final currentPlanId = contract['providerPlanId'];
      if (currentPlanId == providerPlanId) return contract;
      throw const ControlPlaneException(
        'ENTERPRISE_CONTRACT_NOT_PROVISIONABLE',
        'The Enterprise contract is not awaiting provider provisioning',
        statusCode: 409,
      );
    }
    final terms = _contractTerms(contract);
    _validateProviderTerms(
      terms: terms,
      amountMinor: amountMinor,
      currency: currency,
      interval: interval,
    );
    final normalizedPlanId = _text(providerPlanId, 'provider plan ID', 128);
    final existingPlanId = contract['providerPlanId'];
    if (existingPlanId is String && existingPlanId != normalizedPlanId) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MAPPING_CONFLICT',
        'The Enterprise contract is already linked to another provider plan',
        statusCode: 409,
      );
    }
    final now = _clock().toUtc().toIso8601String();
    final updated = <String, Object?>{
      ...contract,
      'providerPlanId': normalizedPlanId,
      'providerAmountMinor': amountMinor,
      'providerCurrency': currency,
      'providerInterval': interval,
      'updatedAt': now,
    };
    if (existingPlanId == normalizedPlanId) return updated;
    await store.replaceJson(enterpriseContractCollection, contractId, updated);
    return updated;
  });

  Future<Map<String, Object?>> syncProviderSubscription({
    required String providerSubscriptionId,
    required String providerPlanId,
    String? providerStatus,
    int? totalCount,
    int? paidCount,
    int? remainingCount,
    String? currentStartAt,
    String? currentEndAt,
    bool? cancelAtCycleEnd,
  }) => _serialized(() async {
    _requireCloud();
    final mapping = await _mapping(providerSubscriptionId);
    if (mapping == null) {
      throw const ControlPlaneException(
        'BILLING_SUBSCRIPTION_UNMAPPED',
        'Razorpay subscription is not linked to an Enterprise contract',
        statusCode: 404,
      );
    }
    if (mapping['providerPlanId'] != providerPlanId) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'The provider subscription plan does not match its Enterprise contract',
        statusCode: 409,
      );
    }
    final subscription = await _subscription(providerSubscriptionId);
    final contractId = mapping['contractId'];
    if (subscription == null || contractId is! String) {
      _stateCorrupt('Enterprise provider mapping is incomplete');
    }
    final now = _clock().toUtc().toIso8601String();
    final updatedSubscription = <String, Object?>{
      ...subscription,
      if (providerStatus != null) 'providerStatus': providerStatus,
      'totalCount': totalCount ?? subscription['totalCount'],
      'paidCount': paidCount ?? subscription['paidCount'],
      'remainingCount': remainingCount ?? subscription['remainingCount'],
      'currentStartAt': currentStartAt ?? subscription['currentStartAt'],
      'currentEndAt': currentEndAt ?? subscription['currentEndAt'],
      'cancelAtCycleEnd': cancelAtCycleEnd ?? subscription['cancelAtCycleEnd'],
      'updatedAt': now,
    };
    await store.replaceJson(
      'billing_subscriptions',
      subscription['id']! as String,
      updatedSubscription,
    );
    final contract = await _contract(contractId);
    final updatedContract = <String, Object?>{
      ...contract,
      if (providerStatus != null) 'providerStatus': providerStatus,
      'providerCancelAtCycleEnd':
          cancelAtCycleEnd ?? contract['providerCancelAtCycleEnd'] ?? false,
      'updatedAt': now,
    };
    await store.replaceJson(
      enterpriseContractCollection,
      contractId,
      updatedContract,
    );
    return updatedSubscription;
  });

  Future<Map<String, Object?>> requestCancellation({
    required String organizationId,
  }) => _serialized(() async {
    _requireCloud();
    _organization(organizationId);
    final contract = await activeContract(organizationId: organizationId);
    if (contract == null) {
      return <String, Object?>{'status': 'not_active'};
    }
    if (contract['status'] ==
        EnterpriseContractStatus.cancellationScheduled.wireValue) {
      return _customerContract(contract);
    }
    final now = _clock().toUtc().toIso8601String();
    final updated = <String, Object?>{
      ...contract,
      'status': EnterpriseContractStatus.cancellationScheduled.wireValue,
      'cancellationStatus': 'scheduled',
      'cancellationRequestedAt': now,
      'providerCancelAtCycleEnd': true,
      'updatedAt': now,
    };
    await store.replaceJson(
      enterpriseContractCollection,
      contract['id']! as String,
      updated,
    );
    final subscriptionId = contract['providerSubscriptionId'];
    if (subscriptionId is String) {
      final subscription = await _subscription(subscriptionId);
      if (subscription != null) {
        await store.replaceJson(
          'billing_subscriptions',
          subscription['id']! as String,
          <String, Object?>{
            ...subscription,
            'cancelAtCycleEnd': true,
            'updatedAt': now,
          },
        );
      }
      final cancellationId =
          'bcancel_${sha256Hex(utf8.encode('$organizationId:${contract['id']}')).substring(0, 32)}';
      final cancellation = <String, Object?>{
        'id': cancellationId,
        'organizationId': organizationId,
        'subscriptionId': subscription?['id'],
        'enterpriseContractId': contract['id'],
        'provider': 'razorpay',
        'status': 'scheduled',
        'effectiveAt': subscription?['currentEndAt'],
        'createdAt': now,
        'updatedAt': now,
      };
      final existing = await store.readJson(
        'billing_cancellations',
        cancellationId,
      );
      if (existing == null) {
        await store.createJson(
          'billing_cancellations',
          cancellationId,
          cancellation,
        );
      } else {
        await store.replaceJson(
          'billing_cancellations',
          cancellationId,
          <String, Object?>{
            ...existing,
            ...cancellation,
            'createdAt': existing['createdAt'],
          },
        );
      }
    }
    return _customerContract(updated);
  });

  Future<Map<String, Object?>?> activeContract({
    required String organizationId,
  }) async {
    _requireCloud();
    _organization(organizationId);
    Map<String, Object?>? result;
    for (final contract in await _contractsFor(organizationId)) {
      final status = contract['status'];
      if (status != EnterpriseContractStatus.active.wireValue &&
          status != EnterpriseContractStatus.cancellationScheduled.wireValue) {
        continue;
      }
      if (result != null)
        _stateCorrupt('Multiple active Enterprise contracts exist');
      result = contract;
    }
    return result;
  }

  /// Returns the customer-visible current contract, including a pending
  /// payment contract. Pending state is intentionally not treated as an
  /// active entitlement by [activeContract] or the Cloud resolver.
  Future<Map<String, Object?>?> currentContract({
    required String organizationId,
  }) async {
    _requireCloud();
    _organization(organizationId);
    final active = await activeContract(organizationId: organizationId);
    if (active != null) return active;
    final contracts = await _contractsFor(organizationId);
    contracts.sort((left, right) {
      final leftAt = DateTime.tryParse('${left['updatedAt']}');
      final rightAt = DateTime.tryParse('${right['updatedAt']}');
      return (rightAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        leftAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    for (final contract in contracts) {
      if (contract['status'] ==
          EnterpriseContractStatus.pendingPayment.wireValue) {
        return contract;
      }
    }
    return null;
  }

  Future<Map<String, CloudLimit>?> activeEntitlementLimits({
    required String organizationId,
  }) async {
    final contract = await activeContract(organizationId: organizationId);
    if (contract == null) return null;
    final overrides = _entitlementSnapshot(contract).limits;
    return Map.unmodifiable(<String, CloudLimit>{
      ...cloudPlanDefinition(cloudPlanEnterpriseKey).limits,
      ...overrides,
    });
  }

  Future<Map<String, Object?>?> providerMapping(
    String providerSubscriptionId,
  ) => _mapping(providerSubscriptionId);

  Future<Map<String, Object?>?> providerSubscription(
    String providerSubscriptionId,
  ) => _subscription(providerSubscriptionId);

  Future<Map<String, Object?>> providerContract(String contractId) async =>
      _contract(contractId);

  Future<EnterpriseProviderEventResult> applyProviderEvent({
    required String providerSubscriptionId,
    required String providerPlanId,
    required String status,
    required String eventId,
    required String? occurredAt,
    int? totalCount,
    int? paidCount,
    int? remainingCount,
    String? currentStartAt,
    String? currentEndAt,
    bool? cancelAtCycleEnd,
  }) => _serialized(() async {
    _requireCloud();
    if (!_providerStatuses.contains(status)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_PROVIDER_STATUS',
        'The Enterprise provider status is unsupported',
        statusCode: 422,
      );
    }
    final mapping = await _mapping(providerSubscriptionId);
    if (mapping == null) {
      throw const ControlPlaneException(
        'BILLING_SUBSCRIPTION_UNMAPPED',
        'Razorpay subscription is not linked to an Enterprise contract',
        statusCode: 422,
      );
    }
    if (mapping['providerPlanId'] != providerPlanId) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay subscription does not match the accepted Enterprise contract',
        statusCode: 422,
      );
    }
    final contractId = mapping['contractId'];
    final organizationId = mapping['organizationId'];
    if (contractId is! String || organizationId is! String) {
      _stateCorrupt('Enterprise provider mapping is incomplete');
    }
    final contract = await _contract(contractId);
    final current = await _subscription(providerSubscriptionId);
    if (current == null)
      _stateCorrupt('Enterprise provider subscription is missing');
    final now = _clock().toUtc().toIso8601String();
    final updatedSubscription = <String, Object?>{
      ...current,
      'status': status,
      'lastProviderEventId': eventId,
      'lastProviderEventAt': occurredAt,
      'totalCount': totalCount ?? current['totalCount'],
      'paidCount': paidCount ?? current['paidCount'],
      'remainingCount': remainingCount ?? current['remainingCount'],
      'currentStartAt': currentStartAt ?? current['currentStartAt'],
      'currentEndAt': currentEndAt ?? current['currentEndAt'],
      'cancelAtCycleEnd': cancelAtCycleEnd ?? current['cancelAtCycleEnd'],
      'updatedAt': now,
    };
    await store.replaceJson(
      'billing_subscriptions',
      current['id']! as String,
      updatedSubscription,
    );
    final terminal = <String>{
      'cancelled',
      'completed',
      'expired',
      'halted',
    }.contains(status);
    final contractStatus = status == 'active'
        ? (contract['status'] ==
                      EnterpriseContractStatus
                          .cancellationScheduled
                          .wireValue ||
                  contract['providerCancelAtCycleEnd'] == true
              ? EnterpriseContractStatus.cancellationScheduled.wireValue
              : EnterpriseContractStatus.active.wireValue)
        : terminal
        ? (status == 'expired' || status == 'completed'
              ? EnterpriseContractStatus.expired.wireValue
              : EnterpriseContractStatus.cancelled.wireValue)
        : contract['status'] ==
              EnterpriseContractStatus.cancellationScheduled.wireValue
        ? EnterpriseContractStatus.cancellationScheduled.wireValue
        : EnterpriseContractStatus.pendingPayment.wireValue;
    final updatedContract = <String, Object?>{
      ...contract,
      'status': contractStatus,
      'providerStatus': status,
      'providerCancelAtCycleEnd':
          cancelAtCycleEnd ?? contract['providerCancelAtCycleEnd'] ?? false,
      if (status == 'active') 'activatedAt': contract['activatedAt'] ?? now,
      if (terminal) 'terminatedAt': now,
      'updatedAt': now,
    };
    await store.replaceJson(
      enterpriseContractCollection,
      contractId,
      updatedContract,
    );
    if (status == 'active') {
      for (final other in await _contractsFor(organizationId)) {
        final otherId = other['id'];
        if (otherId is! String || otherId == contractId) continue;
        final otherStatus = other['status'];
        if (otherStatus != EnterpriseContractStatus.active.wireValue &&
            otherStatus !=
                EnterpriseContractStatus.cancellationScheduled.wireValue) {
          continue;
        }
        await store.replaceJson(
          enterpriseContractCollection,
          otherId,
          <String, Object?>{
            ...other,
            'status': EnterpriseContractStatus.superseded.wireValue,
            'supersededBy': contractId,
            'updatedAt': now,
          },
        );
      }
    }
    if (terminal) {
      final cancellationId =
          'bcancel_${sha256Hex(utf8.encode('$organizationId:$contractId')).substring(0, 32)}';
      final existingCancellation = await store.readJson(
        'billing_cancellations',
        cancellationId,
      );
      if (existingCancellation != null) {
        await store.replaceJson(
          'billing_cancellations',
          cancellationId,
          <String, Object?>{
            ...existingCancellation,
            'status': 'effective',
            'updatedAt': now,
          },
        );
      }
    }
    return EnterpriseProviderEventResult(
      organizationId: organizationId,
      contract: updatedContract,
      subscription: updatedSubscription,
    );
  });

  Map<String, Object?> customerContract(Map<String, Object?> contract) =>
      _customerContract(contract);

  EnterpriseEntitlementSnapshot entitlementSnapshot(
    Map<String, Object?> contract,
  ) => _entitlementSnapshot(contract);

  EnterpriseQuoteTerms quoteTerms(Map<String, Object?> version) =>
      _terms(version);

  Map<String, Object?> _customerContract(Map<String, Object?> contract) {
    final commercial = contract['commercialSnapshot'];
    final entitlement = contract['entitlementSnapshot'];
    return <String, Object?>{
      'id': contract['id'],
      'organizationId': contract['organizationId'],
      'quoteId': contract['quoteId'],
      'quoteVersionId': contract['quoteVersionId'],
      'status': contract['status'],
      'commercialSnapshot': commercial,
      'entitlementSnapshot': entitlement,
      'provider': contract['provider'],
      'providerStatus': contract['providerStatus'],
      'providerCancelAtCycleEnd': contract['providerCancelAtCycleEnd'],
      'activatedAt': contract['activatedAt'],
      'terminatedAt': contract['terminatedAt'],
      'cancellationRequestedAt': contract['cancellationRequestedAt'],
      'createdAt': contract['createdAt'],
      'updatedAt': contract['updatedAt'],
    };
  }

  Future<Map<String, Object?>> _setQuoteStatus(
    Map<String, Object?> quote,
    Map<String, Object?> version,
    EnterpriseQuoteStatus status,
  ) async {
    final now = _clock().toUtc().toIso8601String();
    final updatedVersion = <String, Object?>{
      ...version,
      'status': status.wireValue,
      'updatedAt': now,
      if (status == EnterpriseQuoteStatus.rejected) 'rejectedAt': now,
      if (status == EnterpriseQuoteStatus.withdrawn) 'withdrawnAt': now,
    };
    final updatedQuote = <String, Object?>{
      ...quote,
      'status': status.wireValue,
      'updatedAt': now,
    };
    await store.replaceJson(
      enterpriseQuoteVersionCollection,
      version['id']! as String,
      updatedVersion,
    );
    await store.replaceJson(
      enterpriseQuoteCollection,
      quote['id']! as String,
      updatedQuote,
    );
    return <String, Object?>{'quote': updatedQuote, 'version': updatedVersion};
  }

  void _ensureAcceptableVersion(Map<String, Object?> version) {
    final status = version['status'];
    if (status != EnterpriseQuoteStatus.issued.wireValue &&
        status != EnterpriseQuoteStatus.viewed.wireValue) {
      throw const ControlPlaneException(
        'ENTERPRISE_QUOTE_NOT_ACCEPTABLE',
        'This Enterprise quote version is not available for acceptance',
        statusCode: 409,
      );
    }
  }

  void _validateProviderTerms({
    required EnterpriseQuoteTerms terms,
    required int amountMinor,
    required String currency,
    required String interval,
  }) {
    if (amountMinor != terms.recurringAmountMinor ||
        currency != terms.currency ||
        interval != terms.interval) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Provider commercial terms do not match the accepted Enterprise contract',
        statusCode: 409,
      );
    }
  }

  EnterpriseEntitlementSnapshot _entitlementSnapshot(
    Map<String, Object?> contract,
  ) => EnterpriseEntitlementSnapshot.fromJson(contract['entitlementSnapshot']);

  EnterpriseQuoteTerms _terms(Map<String, Object?> version) {
    final raw = version['terms'];
    if (raw is! Map) _stateCorrupt('Enterprise quote version has no terms');
    final terms = <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final rawValidUntil = terms['validUntil'];
    final rawEntitlements = terms['entitlementSnapshot'];
    if (rawValidUntil is! String || rawEntitlements == null) {
      _stateCorrupt('Enterprise quote terms are incomplete');
    }
    final validUntil = DateTime.tryParse(rawValidUntil);
    if (validUntil == null)
      _stateCorrupt('Enterprise quote validity is invalid');
    return EnterpriseQuoteTerms(
      currency: _mapString(terms, 'currency'),
      recurringAmountMinor: _mapInt(terms, 'recurringAmountMinor'),
      interval: _mapString(terms, 'interval'),
      validUntil: validUntil.toUtc(),
      entitlements: EnterpriseEntitlementSnapshot.fromJson(rawEntitlements),
      contactName: _mapNullableString(terms, 'contactName'),
      contactEmail: _mapNullableString(terms, 'contactEmail'),
      termMonths: _mapNullableInt(terms, 'termMonths'),
      totalCount: _mapNullableInt(terms, 'totalCount'),
      upfrontAmountMinor: _mapNullableInt(terms, 'upfrontAmountMinor'),
      supportLevel: _mapNullableString(terms, 'supportLevel'),
      customerNotes: _mapNullableString(terms, 'customerNotes'),
      internalNotes: _mapNullableString(terms, 'internalNotes'),
    );
  }

  EnterpriseQuoteTerms _contractTerms(Map<String, Object?> contract) {
    final commercial = contract['commercialSnapshot'];
    if (commercial is! Map)
      _stateCorrupt('Enterprise contract has no commercial snapshot');
    final version = <String, Object?>{
      'terms': <String, Object?>{
        for (final entry in commercial.entries)
          if (entry.key is String) entry.key as String: entry.value,
      },
    };
    return _terms(version);
  }

  Future<Map<String, Object?>> _quote(String quoteId) async {
    final normalized = requireOpaqueId(quoteId, 'Enterprise quote ID');
    final quote = await store.readJson(enterpriseQuoteCollection, normalized);
    if (quote == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Enterprise quote was not found',
        statusCode: 404,
      );
    }
    return quote;
  }

  Future<Map<String, Object?>> _version(String versionId) async {
    final normalized = requireOpaqueId(
      versionId,
      'Enterprise quote version ID',
    );
    final version = await store.readJson(
      enterpriseQuoteVersionCollection,
      normalized,
    );
    if (version == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Enterprise quote version was not found',
        statusCode: 404,
      );
    }
    return version;
  }

  Future<Map<String, Object?>> _currentVersion(
    Map<String, Object?> quote,
  ) async {
    final versionId = quote['currentVersionId'];
    if (versionId is! String)
      _stateCorrupt('Enterprise quote has no current version');
    final version = await store.readJson(
      enterpriseQuoteVersionCollection,
      versionId,
    );
    if (version == null)
      _stateCorrupt('Enterprise quote current version is missing');
    return version;
  }

  Future<List<Map<String, Object?>>> _quotesFor(String organizationId) async =>
      (await store.listJson(enterpriseQuoteCollection))
          .where((value) => value['organizationId'] == organizationId)
          .toList(growable: false);

  Future<List<Map<String, Object?>>> _contractsFor(
    String organizationId,
  ) async =>
      (await store.listJson(enterpriseContractCollection))
          .where((value) => value['organizationId'] == organizationId)
          .toList(growable: false);

  Future<Map<String, Object?>?> _contractForQuoteVersion(
    String versionId,
  ) async {
    for (final contract in await store.listJson(enterpriseContractCollection)) {
      if (contract['quoteVersionId'] == versionId) return contract;
    }
    return null;
  }

  Future<Map<String, Object?>> _contract(String contractId) async {
    final normalized = requireOpaqueId(contractId, 'Enterprise contract ID');
    final contract = await store.readJson(
      enterpriseContractCollection,
      normalized,
    );
    if (contract == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Enterprise contract was not found',
        statusCode: 404,
      );
    }
    return contract;
  }

  Future<Map<String, Object?>?> _mapping(String providerSubscriptionId) async {
    final normalized = _text(
      providerSubscriptionId,
      'provider subscription ID',
      128,
    );
    final mapping = await store.readJson(
      enterpriseProviderMappingCollection,
      _providerMappingId(normalized),
    );
    if (mapping == null) return null;
    if (mapping['provider'] != 'razorpay' ||
        mapping['providerSubscriptionId'] != normalized) {
      _stateCorrupt('Enterprise provider mapping is invalid');
    }
    return mapping;
  }

  Future<Map<String, Object?>?> _subscription(
    String providerSubscriptionId,
  ) async {
    Map<String, Object?>? result;
    for (final row in await store.listJson('billing_subscriptions')) {
      if (row['provider'] != 'razorpay' ||
          row['providerSubscriptionId'] != providerSubscriptionId) {
        continue;
      }
      if (result != null)
        _stateCorrupt('Provider subscription has duplicate billing rows');
      result = row;
    }
    return result;
  }

  Map<String, Object?> _envelope(
    Map<String, Object?> quote,
    Map<String, Object?> version,
  ) => <String, Object?>{...quote, 'version': version};

  Map<String, Object?> _customerEnvelope(
    Map<String, Object?> quote,
    Map<String, Object?> version,
  ) {
    final rawTerms = version['terms'];
    final terms = rawTerms is Map
        ? <String, Object?>{
            for (final entry in rawTerms.entries)
              if (entry.key is String && entry.key != 'internalNotes')
                entry.key as String: entry.value,
          }
        : const <String, Object?>{};
    return <String, Object?>{
      'id': quote['id'],
      'quoteNumber': quote['quoteNumber'],
      'organizationId': quote['organizationId'],
      'inquiryId': quote['inquiryId'],
      'status': quote['status'],
      'currentVersionId': quote['currentVersionId'],
      'currentVersion': quote['currentVersion'],
      'version': <String, Object?>{
        'id': version['id'],
        'quoteId': version['quoteId'],
        'version': version['version'],
        'status': version['status'],
        'terms': terms,
        'issuedAt': version['issuedAt'],
        'viewedAt': version['viewedAt'],
        'acceptedAt': version['acceptedAt'],
        'createdAt': version['createdAt'],
        'updatedAt': version['updatedAt'],
      },
      'createdAt': quote['createdAt'],
      'updatedAt': quote['updatedAt'],
    };
  }

  void _requireCurrentVersion(
    Map<String, Object?> quote,
    Map<String, Object?> version,
  ) {
    if (quote['currentVersionId'] != version['id'] ||
        quote['currentVersion'] != version['version']) {
      throw const ControlPlaneException(
        'ENTERPRISE_QUOTE_VERSION_CONFLICT',
        'The requested Enterprise quote version is no longer current',
        statusCode: 409,
      );
    }
  }

  void _requireQuoteOrganization(
    Map<String, Object?> quote,
    String organizationId,
  ) {
    if (quote['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Enterprise quote was not found',
        statusCode: 404,
      );
    }
  }

  Future<void> _requireOrganization(String organizationId) async {
    if (await store.readJson('organizations', organizationId) == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Organization was not found',
        statusCode: 404,
      );
    }
  }

  void _requireCloud() {
    if (deploymentModel != DeploymentModel.cloud) {
      throw const ControlPlaneException(
        'INVALID_DEPLOYMENT_MODEL',
        'Enterprise Cloud billing is unavailable on self-hosted deployments',
        statusCode: 409,
      );
    }
  }

  void _organization(String value) => requireOpaqueId(value, 'organization ID');

  String _text(String value, String field, int maxLength) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > maxLength ||
        normalized.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ControlPlaneException(
        'INVALID_QUOTE_FIELD',
        '$field is invalid',
        statusCode: 422,
      );
    }
    return normalized;
  }

  String _mapString(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is! String) _stateCorrupt('Enterprise term $key is invalid');
    return raw;
  }

  String? _mapNullableString(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw == null) return null;
    if (raw is! String) _stateCorrupt('Enterprise term $key is invalid');
    return raw;
  }

  int _mapInt(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is! int) _stateCorrupt('Enterprise term $key is invalid');
    return raw;
  }

  int? _mapNullableInt(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw == null) return null;
    if (raw is! int) _stateCorrupt('Enterprise term $key is invalid');
    return raw;
  }

  String _providerMappingId(String providerSubscriptionId) =>
      'epmap_${sha256Hex(utf8.encode('razorpay:$providerSubscriptionId')).substring(0, 32)}';

  String _subscriptionId(
    String organizationId,
    String providerSubscriptionId,
  ) =>
      'bsub_${sha256Hex(utf8.encode('$organizationId:razorpay:$providerSubscriptionId')).substring(0, 32)}';

  Never _stateCorrupt(String message) => throw ControlPlaneException(
    'ENTERPRISE_BILLING_STATE_CORRUPT',
    message,
    statusCode: 500,
  );

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _writeTail;
    final gate = Completer<void>();
    _writeTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }
}
