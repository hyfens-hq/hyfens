import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'billing.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const String notificationEventCollection = 'notification_events';
const String notificationDeliveryCollection = 'notification_deliveries';

enum NotificationCategory {
  authentication,
  security,
  billing,
  organization,
  operational,
  account,
}

enum NotificationDeliveryState {
  pending,
  processing,
  accepted,
  delivered,
  softFailed,
  hardFailed,
  bounced,
  complained,
  suppressed,
  cancelled,
}

extension NotificationDeliveryStateWire on NotificationDeliveryState {
  String get wireValue => switch (this) {
    NotificationDeliveryState.pending => 'pending',
    NotificationDeliveryState.processing => 'processing',
    NotificationDeliveryState.accepted => 'accepted',
    NotificationDeliveryState.delivered => 'delivered',
    NotificationDeliveryState.softFailed => 'soft_failed',
    NotificationDeliveryState.hardFailed => 'hard_failed',
    NotificationDeliveryState.bounced => 'bounced',
    NotificationDeliveryState.complained => 'complained',
    NotificationDeliveryState.suppressed => 'suppressed',
    NotificationDeliveryState.cancelled => 'cancelled',
  };
}

final class NotificationSenderIdentity {
  const NotificationSenderIdentity({
    required this.from,
    required this.displayName,
    this.replyTo,
  });

  final String from;
  final String displayName;
  final String? replyTo;
}

/// Hyfens sender policy is centralized so templates cannot accidentally pick
/// a different address for the same class of communication.
final class HyfensSenderPolicy {
  const HyfensSenderPolicy._();

  static const NotificationSenderIdentity transactional =
      NotificationSenderIdentity(
        from: 'no-reply@hyfens.com',
        displayName: 'Hyfens',
      );
  static const NotificationSenderIdentity support = NotificationSenderIdentity(
    from: 'no-reply@hyfens.com',
    displayName: 'Hyfens Support',
    replyTo: 'support@hyfens.com',
  );
  static const NotificationSenderIdentity security = NotificationSenderIdentity(
    from: 'no-reply@hyfens.com',
    displayName: 'Hyfens Security',
  );
  static const NotificationSenderIdentity team = NotificationSenderIdentity(
    from: 'team@hyfens.com',
    displayName: 'Hyfens Team',
  );

  static NotificationSenderIdentity forEvent(String key) {
    if (key.startsWith('security.') || key.startsWith('auth.')) {
      return security;
    }
    if (key.startsWith('billing.') ||
        key.startsWith('account.deletion') ||
        key.startsWith('organization.deletion')) {
      return support;
    }
    if (key.startsWith('organization.')) return transactional;
    return transactional;
  }
}

final class NotificationDefinition {
  const NotificationDefinition({
    required this.key,
    required this.version,
    required this.category,
    required this.purpose,
    required this.template,
    required this.subject,
    required this.preheader,
    required this.priority,
    required this.userCanDisable,
    required this.deduplication,
    this.retention = 'transactional_metadata',
    this.sender = HyfensSenderPolicy.transactional,
  });

  final String key;
  final int version;
  final NotificationCategory category;
  final String purpose;
  final String template;
  final String subject;
  final String preheader;
  final String priority;
  final bool userCanDisable;
  final String deduplication;
  final String retention;
  final NotificationSenderIdentity sender;

  String get versionedKey => '$key:v$version';

  String get classification => switch (category) {
    NotificationCategory.security => 'security',
    NotificationCategory.operational => 'operational',
    _ => 'transactional',
  };

  /// Variables required for a meaningful render. Optional context (such as a
  /// provider reference) intentionally remains outside this set and uses a
  /// safe fallback in the renderer.
  Set<String> get requiredVariables => switch (template) {
    'welcome' => const <String>{'organization'},
    'verification_code' ||
    'recovery_code' => const <String>{'token', 'expires_at'},
    'billing_summary' => const <String>{'plan', 'amount', 'currency'},
    'billing_warning' => const <String>{'message'},
    'plan_change' => const <String>{'old_plan', 'new_plan', 'effective_at'},
    'cancellation' => const <String>{'plan', 'effective_at'},
    'refund' => const <String>{'amount', 'status'},
    'destructive_notice' || 'security_notice' => const <String>{'message'},
    'invitation' => const <String>{'organization'},
    'enterprise_inquiry' => const <String>{'inquiry_id', 'contact'},
    _ => const <String>{'message'},
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'version': version,
    'category': category.name,
    'classification': classification,
    'purpose': purpose,
    'template': template,
    'priority': priority,
    'user_can_disable': userCanDisable,
    'deduplication': deduplication,
    'retention': retention,
    'required_variables': requiredVariables.toList(growable: false),
    'sender': sender.from,
    'reply_to': sender.replyTo,
  };
}

/// The catalogue is deliberately provider-neutral. Razorpay event names are
/// translated into these keys before a customer message is considered.
final class NotificationCatalog {
  const NotificationCatalog._();

  static const List<NotificationDefinition>
  definitions = <NotificationDefinition>[
    NotificationDefinition(
      key: 'auth.registration.completed',
      version: 1,
      category: NotificationCategory.authentication,
      purpose: 'welcome',
      template: 'welcome',
      subject: 'Welcome to Hyfens Cloud',
      preheader: 'Your workspace is ready for the next release.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'user_once',
      sender: HyfensSenderPolicy.team,
    ),
    NotificationDefinition(
      key: 'auth.email.verification_requested',
      version: 1,
      category: NotificationCategory.authentication,
      purpose: 'email_verification',
      template: 'verification_code',
      subject: 'Verify your Hyfens Cloud account',
      preheader: 'Use this one-time code to finish setting up your account.',
      priority: 'instant',
      userCanDisable: false,
      deduplication: 'token_issue',
      sender: HyfensSenderPolicy.security,
    ),
    NotificationDefinition(
      key: 'auth.password.recovery_requested',
      version: 1,
      category: NotificationCategory.authentication,
      purpose: 'password_recovery',
      template: 'recovery_code',
      subject: 'Recover your Hyfens Cloud account',
      preheader: 'Use this one-time code to choose a new password.',
      priority: 'instant',
      userCanDisable: false,
      deduplication: 'token_issue',
      sender: HyfensSenderPolicy.security,
    ),
    NotificationDefinition(
      key: 'auth.password.changed',
      version: 1,
      category: NotificationCategory.security,
      purpose: 'password_change',
      template: 'security_notice',
      subject: 'Your Hyfens password was changed',
      preheader: 'A security-sensitive change was made to your account.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'action',
      sender: HyfensSenderPolicy.security,
    ),
    NotificationDefinition(
      key: 'security.new_device_detected',
      version: 1,
      category: NotificationCategory.security,
      purpose: 'new_device',
      template: 'security_notice',
      subject: 'New sign-in to your Hyfens account',
      preheader: 'Review a recent sign-in to your account.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'security_event',
      sender: HyfensSenderPolicy.security,
    ),
    NotificationDefinition(
      key: 'organization.member.invited',
      version: 1,
      category: NotificationCategory.organization,
      purpose: 'member_invitation',
      template: 'invitation',
      subject: 'You have been invited to a Hyfens workspace',
      preheader: 'Join a workspace and collaborate on safer releases.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'invitation',
      sender: HyfensSenderPolicy.transactional,
    ),
    NotificationDefinition(
      key: 'organization.owner_changed',
      version: 1,
      category: NotificationCategory.security,
      purpose: 'ownership_change',
      template: 'security_notice',
      subject: 'Hyfens workspace ownership changed',
      preheader: 'A security-sensitive workspace change was completed.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'action',
      sender: HyfensSenderPolicy.security,
    ),
    NotificationDefinition(
      key: 'billing.checkout.initiated',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'checkout_initiated',
      template: 'billing_summary',
      subject: 'Your Hyfens checkout is ready',
      preheader: 'Continue securely to authorize your selected plan.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'checkout',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.plan_change.requested',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'plan_change_requested',
      template: 'plan_change',
      subject: 'Your Hyfens plan change was requested',
      preheader: 'We are confirming the requested billing change.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'transition',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.plan_change.cancelled',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'plan_change_cancelled',
      template: 'plan_change',
      subject: 'Your scheduled Hyfens plan change was cancelled',
      preheader: 'Your current plan will continue unchanged.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'transition',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.refund.requested',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'refund_requested',
      template: 'refund',
      subject: 'Your Hyfens refund request was received',
      preheader:
          'Your request will be reviewed according to the Refund Policy.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'refund_request',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.activated',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'subscription_activation',
      template: 'billing_summary',
      subject: 'Your Hyfens subscription is active',
      preheader: 'Your new plan and entitlements are now available.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.renewed',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'subscription_renewal',
      template: 'billing_summary',
      subject: 'Your Hyfens subscription renewed',
      preheader: 'Your payment was received and your plan remains active.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.payment.succeeded',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'payment_receipt',
      template: 'billing_summary',
      subject: 'Payment received for Hyfens Cloud',
      preheader: 'Your Hyfens payment was captured successfully.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.payment.failed',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'payment_failure',
      template: 'billing_warning',
      subject: 'Action may be needed for your Hyfens payment',
      preheader: 'Your plan remains protected while we reconcile the payment.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.payment.action_required',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'payment_action',
      template: 'billing_warning',
      subject: 'Payment action required for Hyfens Cloud',
      preheader:
          'Complete the requested billing action to keep service active.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.upcoming_renewal',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'upcoming_renewal',
      template: 'billing_summary',
      subject: 'Your Hyfens renewal is coming up',
      preheader: 'Review the plan and date for your next renewal.',
      priority: 'schedule',
      userCanDisable: false,
      deduplication: 'renewal_window',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.upgrade_applied',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'plan_upgrade',
      template: 'plan_change',
      subject: 'Your Hyfens plan was upgraded',
      preheader: 'Your higher plan capabilities are now effective.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'transition',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.downgrade_scheduled',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'plan_downgrade_scheduled',
      template: 'plan_change',
      subject: 'Your Hyfens downgrade is scheduled',
      preheader:
          'Your current paid plan remains active until the effective date.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'transition',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.downgrade_applied',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'plan_downgrade_applied',
      template: 'plan_change',
      subject: 'Your Hyfens plan changed',
      preheader: 'Your scheduled plan change is now effective.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'transition',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.cancellation_scheduled',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'cancellation_scheduled',
      template: 'cancellation',
      subject: 'Your Hyfens subscription cancellation is scheduled',
      preheader: 'Your paid access continues through the current period.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'transition',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.cancelled',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'subscription_cancelled',
      template: 'cancellation',
      subject: 'Your Hyfens subscription has ended',
      preheader: 'Your subscription is no longer renewing.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.subscription.reactivated',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'subscription_reactivated',
      template: 'billing_summary',
      subject: 'Your Hyfens subscription is active again',
      preheader: 'Your plan and paid capabilities are available again.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'transition',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.refund.initiated',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'refund_initiated',
      template: 'refund',
      subject: 'Your Hyfens refund is being processed',
      preheader: 'We have started the reviewed refund process.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.refund.completed',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'refund_completed',
      template: 'refund',
      subject: 'Your Hyfens refund was processed',
      preheader:
          'The approved refund has been accepted by the payment provider.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'billing.refund.failed',
      version: 1,
      category: NotificationCategory.billing,
      purpose: 'refund_failed',
      template: 'billing_warning',
      subject: 'Your Hyfens refund needs attention',
      preheader: 'The approved refund could not be completed automatically.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'provider_event',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'account.deletion.requested',
      version: 1,
      category: NotificationCategory.account,
      purpose: 'account_deletion',
      template: 'destructive_notice',
      subject: 'Your Hyfens account deletion is scheduled',
      preheader:
          'Review the request and cancel it during the grace period if needed.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'deletion_request',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'account.deletion.cancelled',
      version: 1,
      category: NotificationCategory.account,
      purpose: 'account_deletion_cancelled',
      template: 'security_notice',
      subject: 'Your Hyfens account deletion was cancelled',
      preheader: 'Your account remains active.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'deletion_request',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'account.deleted',
      version: 1,
      category: NotificationCategory.account,
      purpose: 'account_deleted',
      template: 'destructive_notice',
      subject: 'Your Hyfens account was deleted',
      preheader: 'Your account lifecycle request has completed.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'deletion_request',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'organization.deletion.requested',
      version: 1,
      category: NotificationCategory.account,
      purpose: 'organization_deletion',
      template: 'destructive_notice',
      subject: 'Your Hyfens organization deletion is scheduled',
      preheader: 'Customer-owned organization data remains available during the grace period.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'organization_deletion_request',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'organization.deletion.cancelled',
      version: 1,
      category: NotificationCategory.account,
      purpose: 'organization_deletion_cancelled',
      template: 'security_notice',
      subject: 'Your Hyfens organization deletion was cancelled',
      preheader: 'Your organization remains available.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'organization_deletion_request',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'organization.deleted',
      version: 1,
      category: NotificationCategory.account,
      purpose: 'organization_deleted',
      template: 'destructive_notice',
      subject: 'Your Hyfens organization was deleted',
      preheader: 'The organization lifecycle request has completed.',
      priority: 'async',
      userCanDisable: false,
      deduplication: 'organization_deletion_request',
      sender: HyfensSenderPolicy.support,
    ),
    NotificationDefinition(
      key: 'ops.enterprise.inquiry_received',
      version: 1,
      category: NotificationCategory.operational,
      purpose: 'enterprise_inquiry',
      template: 'enterprise_inquiry',
      subject: 'New Hyfens Enterprise inquiry',
      preheader: 'A customer inquiry is waiting in the operator workspace.',
      priority: 'high',
      userCanDisable: false,
      deduplication: 'inquiry',
      sender: HyfensSenderPolicy.team,
    ),
  ];

  static final Map<String, NotificationDefinition> _byKey =
      <String, NotificationDefinition>{
        for (final definition in definitions) definition.key: definition,
      };

  static NotificationDefinition forKey(String key) {
    final definition = _byKey[key];
    if (definition == null) {
      throw ArgumentError.value(
        key,
        'key',
        'is not in the notification catalogue',
      );
    }
    return definition;
  }
}

final class NotificationEvent {
  NotificationEvent({
    required this.key,
    required String stableKey,
    String? idOverride,
    required Iterable<String> recipientEmails,
    required Map<String, Object?> variables,
    required this.occurredAt,
    this.organizationId,
    this.entityType,
    this.entityId,
    this.source = 'hyfens',
    this.correlationId,
    this.causationId,
    this.provider,
    this.providerEventId,
    this.sensitive = false,
    int version = 1,
  }) : version = version,
       id =
           idOverride ??
           'nev_${sha256Hex(utf8.encode('$key:$version:$stableKey')).substring(0, 32)}',
       recipientEmails = List.unmodifiable(
         recipientEmails.map(_normalizeEmail).toSet(),
       ),
       variables = Map.unmodifiable(variables) {
    NotificationCatalog.forKey(key);
    if (this.recipientEmails.isEmpty) {
      throw ArgumentError.value(
        recipientEmails,
        'recipientEmails',
        'must not be empty',
      );
    }
    if (this.recipientEmails.any((email) => !email.contains('@'))) {
      throw ArgumentError.value(
        recipientEmails,
        'recipientEmails',
        'contains an invalid address',
      );
    }
  }

  final String id;
  final String key;
  final int version;
  final List<String> recipientEmails;
  final Map<String, Object?> variables;
  final DateTime occurredAt;
  final String? organizationId;
  final String? entityType;
  final String? entityId;
  final String source;
  final String? correlationId;
  final String? causationId;
  final String? provider;
  final String? providerEventId;
  final bool sensitive;
}

final class NotificationMessage {
  const NotificationMessage({
    required this.to,
    required this.subject,
    required this.preheader,
    required this.html,
    required this.text,
    required this.sender,
    required this.priority,
    required this.eventId,
    this.replyTo,
  });

  final String to;
  final String subject;
  final String preheader;
  final String html;
  final String text;
  final NotificationSenderIdentity sender;
  final String priority;
  final String eventId;
  final String? replyTo;
}

final class NotificationProviderResult {
  const NotificationProviderResult({
    required this.state,
    this.providerMessageId,
  });

  final NotificationDeliveryState state;
  final String? providerMessageId;
}

final class NotificationProviderException implements Exception {
  const NotificationProviderException(
    this.message, {
    this.statusCode,
    this.retryable = true,
    this.failureClass = 'provider_error',
  });

  final String message;
  final int? statusCode;
  final bool retryable;
  final String failureClass;

  @override
  String toString() => 'NotificationProviderException($message)';
}

abstract interface class NotificationProvider {
  Future<NotificationProviderResult> send(
    NotificationMessage message, {
    required String idempotencyKey,
  });
}

/// Keplars is an adapter, not part of the billing or authentication domain.
/// The HTML body follows the documented raw-email API; the text representation
/// remains available for providers that support multipart delivery.
final class KeplarsNotificationProvider implements NotificationProvider {
  KeplarsNotificationProvider({
    required String apiKey,
    this.from = 'no-reply@hyfens.com',
    this.fromName = 'Hyfens',
    Uri? apiBase,
    HttpClient Function()? clientFactory,
  }) : _apiKey = apiKey,
       apiBase =
           apiBase ??
           Uri(scheme: 'https', host: 'api.keplars.com', path: '/api/v1'),
       _clientFactory = clientFactory ?? HttpClient.new {
    if (_apiKey.trim().isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'must not be empty');
    }
    _requireHeaderValue(from, 'from');
    _requireHeaderValue(fromName, 'fromName');
  }

  final String _apiKey;
  final String from;
  final String fromName;
  final Uri apiBase;
  final HttpClient Function() _clientFactory;

  static KeplarsNotificationProvider? fromEnvironment(
    Map<String, String> values,
  ) {
    final apiKey = values['KEPLARS_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) return null;
    final configuredFrom = values['HYFENS_EMAIL_FROM']?.trim();
    if (configuredFrom != null &&
        configuredFrom.isNotEmpty &&
        configuredFrom != HyfensSenderPolicy.transactional.from &&
        configuredFrom != HyfensSenderPolicy.team.from) {
      throw ArgumentError(
        'HYFENS_EMAIL_FROM must be no-reply@hyfens.com or team@hyfens.com',
      );
    }
    return KeplarsNotificationProvider(
      apiKey: apiKey,
      from: configuredFrom?.isNotEmpty == true
          ? configuredFrom!
          : 'no-reply@hyfens.com',
      fromName: values['HYFENS_EMAIL_FROM_NAME']?.trim().isNotEmpty == true
          ? values['HYFENS_EMAIL_FROM_NAME']!.trim()
          : 'Hyfens',
    );
  }

  @override
  Future<NotificationProviderResult> send(
    NotificationMessage message, {
    required String idempotencyKey,
  }) async {
    final client = _clientFactory();
    try {
      final request = await client.postUrl(
        apiBase.replace(path: '${apiBase.path}/send-email/${message.priority}'),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey')
        ..set('Idempotency-Key', idempotencyKey)
        ..contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'to': <String>[message.to],
            'subject': message.subject,
            'body': message.html,
            // The notification definition owns the sender identity. The
            // environment value is validated at startup but cannot override
            // a security or billing message into the wrong mailbox.
            'from': message.sender.from,
            'from_name': message.sender.displayName.isEmpty
                ? fromName
                : message.sender.displayName,
            if (message.replyTo ?? message.sender.replyTo case final replyTo?)
              'reply_to': replyTo,
          }),
        ),
      );
      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NotificationProviderException(
          'Keplars rejected notification (${response.statusCode})',
          statusCode: response.statusCode,
          retryable: response.statusCode == 429 || response.statusCode >= 500,
          failureClass: response.statusCode == 429
              ? 'rate_limited'
              : 'provider_rejected',
        );
      }
      String? messageId;
      try {
        final decoded = jsonDecode(responseText);
        if (decoded is Map && decoded['email_id'] is String) {
          messageId = decoded['email_id'] as String;
        }
      } on Object {
        // A successful provider response without JSON is still accepted.
      }
      return NotificationProviderResult(
        state: NotificationDeliveryState.accepted,
        providerMessageId: messageId,
      );
    } on NotificationProviderException {
      rethrow;
    } on Object catch (error) {
      throw NotificationProviderException(
        'Keplars request failed: ${error.runtimeType}',
        failureClass: 'transport_error',
      );
    } finally {
      client.close(force: true);
    }
  }

  static void _requireHeaderValue(String value, String label) {
    if (value.trim().isEmpty || value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('$label contains an invalid value');
    }
  }
}

final class NotificationRenderResult {
  const NotificationRenderResult({
    required this.subject,
    required this.preheader,
    required this.html,
    required this.text,
  });

  final String subject;
  final String preheader;
  final String html;
  final String text;
}

/// A small table-based system keeps important messages readable when images
/// are disabled and avoids relying on mail-client-specific layout features.
final class NotificationRenderer {
  NotificationRenderer({
    required this.dashboardOrigin,
    required this.marketingOrigin,
  }) {
    _requireHttps(dashboardOrigin, 'dashboardOrigin');
    _requireHttps(marketingOrigin, 'marketingOrigin');
  }

  final Uri dashboardOrigin;
  final Uri marketingOrigin;

  NotificationRenderResult render(NotificationEvent event) {
    final definition = NotificationCatalog.forKey(event.key);
    final content = _content(definition, event.variables);
    final action = _action(event.variables);
    final htmlContent = StringBuffer(content.html);
    final textContent = StringBuffer(content.text);
    if (action != null) {
      htmlContent.write(_cta(action.label, action.url));
      textContent
        ..writeln()
        ..writeln('${action.label}: ${action.url}');
    }
    return NotificationRenderResult(
      subject: definition.subject,
      preheader: definition.preheader,
      html: _shell(
        title: _title(definition, event.variables),
        preheader: definition.preheader,
        content: htmlContent.toString(),
      ),
      text:
          '${_title(definition, event.variables)}\n\n${textContent.toString().trim()}\n\nHyfens Cloud\n${marketingOrigin.toString()}',
    );
  }

  NotificationMessage messageFor(NotificationEvent event, String recipient) {
    final definition = NotificationCatalog.forKey(event.key);
    final rendered = render(event);
    final sender = definition.sender;
    return NotificationMessage(
      to: recipient,
      subject: rendered.subject,
      preheader: rendered.preheader,
      html: rendered.html,
      text: rendered.text,
      sender: sender,
      replyTo: sender.replyTo,
      priority: definition.priority,
      eventId: event.id,
    );
  }

  _RenderedContent _content(
    NotificationDefinition definition,
    Map<String, Object?> values,
  ) {
    final plan = _value(values, 'plan', fallback: 'Hyfens Cloud');
    final organization = _value(
      values,
      'organization',
      fallback: 'your workspace',
    );
    final amount = _value(
      values,
      'amount',
      fallback: 'See your billing workspace',
    );
    final effectiveAt = _value(
      values,
      'effective_at',
      fallback: 'the next billing boundary',
    );
    final message = _value(
      values,
      'message',
      fallback:
          'This message records an important change to your Hyfens account.',
    );
    switch (definition.template) {
      case 'welcome':
        return _RenderedContent(
          html:
              '<p>Your Hyfens Cloud workspace is ready.</p><p>Use the Cloud dashboard to review releases, environments, billing, and the service boundary for <strong>${_escape(organization)}</strong>.</p>',
          text:
              'Your Hyfens Cloud workspace is ready.\n\nReview releases, environments, billing, and the service boundary for $organization.',
        );
      case 'verification_code':
      case 'recovery_code':
        final token = _value(values, 'token', fallback: 'Unavailable');
        final purpose = definition.template == 'verification_code'
            ? 'Finish creating your account with this one-time verification code:'
            : 'Use this one-time recovery code to choose a new password:';
        return _RenderedContent(
          html:
              '<p>${_escape(purpose)}</p><div style="margin:24px 0;padding:18px 20px;border:1px solid #d8d3cb;background:#f8f6f2;font:700 24px/1.2 monospace;letter-spacing:.12em;color:#121212">${_escape(token)}</div><p>This code expires at <strong>${_escape(_value(values, 'expires_at', fallback: 'the time shown in your account'))}</strong>.</p>',
          text:
              '$purpose\n\n$token\n\nThis code expires at ${_value(values, 'expires_at', fallback: 'the time shown in your account')}.',
        );
      case 'billing_summary':
        return _billingContent(
          organization: organization,
          plan: plan,
          amount: amount,
          values: values,
          message: message,
        );
      case 'billing_warning':
        return _RenderedContent(
          html:
              '<div style="margin:20px 0;padding:16px 18px;border-left:3px solid #d85a2a;background:#fff4ed"><strong>${_escape(message)}</strong></div><p>Your current entitlement is governed by Hyfens billing state. If action is required, use the billing workspace or contact support.</p>',
          text:
              '$message\n\nYour current entitlement is governed by Hyfens billing state. If action is required, use the billing workspace or contact support.',
        );
      case 'plan_change':
        final oldPlan = _value(values, 'old_plan', fallback: 'Current plan');
        final newPlan = _value(values, 'new_plan', fallback: plan);
        return _RenderedContent(
          html:
              '<p>${_escape(message)}</p>${_summaryTable(<String, String>{'Current plan': oldPlan, 'Next plan': newPlan, 'Effective': effectiveAt, 'Workspace': organization})}',
          text:
              '$message\n\nCurrent plan: $oldPlan\nNext plan: $newPlan\nEffective: $effectiveAt\nWorkspace: $organization',
        );
      case 'cancellation':
        return _RenderedContent(
          html:
              '<p>${_escape(message.isEmpty ? 'Renewal has been stopped for this subscription.' : message)}</p>${_summaryTable(<String, String>{'Plan': plan, 'Access through': effectiveAt, 'Refunds': 'No automatic refund for the current paid period', 'Workspace': organization})}',
          text:
              '${message.isEmpty ? 'Renewal has been stopped for this subscription.' : message}\n\nPlan: $plan\nAccess through: $effectiveAt\nRefunds: No automatic refund for the current paid period\nWorkspace: $organization',
        );
      case 'refund':
        return _RenderedContent(
          html:
              '<p>${_escape(message)}</p>${_summaryTable(<String, String>{'Amount': amount, 'Payment': _value(values, 'payment_id', fallback: 'Hyfens payment'), 'Status': _value(values, 'status', fallback: 'Under review'), 'Workspace': organization})}<p>Refund processing is separate from subscription state. A refund does not by itself cancel a subscription.</p>',
          text:
              '$message\n\nAmount: $amount\nPayment: ${_value(values, 'payment_id', fallback: 'Hyfens payment')}\nStatus: ${_value(values, 'status', fallback: 'Under review')}\nWorkspace: $organization\n\nRefund processing is separate from subscription state. A refund does not by itself cancel a subscription.',
        );
      case 'destructive_notice':
        return _RenderedContent(
          html:
              '<div style="margin:20px 0;padding:16px 18px;border-left:3px solid #b42318;background:#fff1f0"><strong>${_escape(message)}</strong></div><p>Account deletion is separate from subscription cancellation. Required billing, security, and audit evidence may be retained according to Hyfens policy.</p>',
          text:
              '$message\n\nAccount deletion is separate from subscription cancellation. Required billing, security, and audit evidence may be retained according to Hyfens policy.',
        );
      case 'invitation':
        return _RenderedContent(
          html:
              '<p>${_escape(message)}</p>${_summaryTable(<String, String>{'Workspace': organization, 'Invited by': _value(values, 'invited_by', fallback: 'A workspace administrator')})}',
          text:
              '$message\n\nWorkspace: $organization\nInvited by: ${_value(values, 'invited_by', fallback: 'A workspace administrator')}',
        );
      case 'security_notice':
        return _RenderedContent(
          html:
              '<div style="margin:20px 0;padding:16px 18px;border:1px solid #ded9d1;background:#f8f6f2"><strong>${_escape(message)}</strong></div>${_summaryTable(<String, String>{'Time': _value(values, 'occurred_at', fallback: 'Recently'), 'Location': _value(values, 'location', fallback: 'Not available'), 'Workspace': organization})}<p>If you do not recognize this change, secure your account and contact support.</p>',
          text:
              '$message\n\nTime: ${_value(values, 'occurred_at', fallback: 'Recently')}\nLocation: ${_value(values, 'location', fallback: 'Not available')}\nWorkspace: $organization\n\nIf you do not recognize this change, secure your account and contact support.',
        );
      case 'enterprise_inquiry':
        return _RenderedContent(
          html:
              '<p>A new Enterprise inquiry is waiting in the operator workspace.</p>${_summaryTable(<String, String>{'Reference': _value(values, 'inquiry_id', fallback: 'Not available'), 'Contact': _value(values, 'contact', fallback: 'Not available'), 'Organization': organization})}<p>${_escape(message)}</p>',
          text:
              'A new Enterprise inquiry is waiting in the operator workspace.\n\nReference: ${_value(values, 'inquiry_id', fallback: 'Not available')}\nContact: ${_value(values, 'contact', fallback: 'Not available')}\nOrganization: $organization\n\n$message',
        );
      default:
        return _RenderedContent(
          html: '<p>${_escape(message)}</p>',
          text: message,
        );
    }
  }

  _RenderedContent _billingContent({
    required String organization,
    required String plan,
    required String amount,
    required Map<String, Object?> values,
    required String message,
  }) => _RenderedContent(
    html:
        '<p>${_escape(message)}</p>${_summaryTable(<String, String>{'Workspace': organization, 'Plan': plan, 'Amount': amount, 'Billing period': _value(values, 'billing_period', fallback: 'Current period'), 'Next billing date': _value(values, 'next_billing_at', fallback: 'See your billing workspace'), if (values['currency'] != null) 'Currency': _value(values, 'currency')})}',
    text:
        '$message\n\nWorkspace: $organization\nPlan: $plan\nAmount: $amount\nBilling period: ${_value(values, 'billing_period', fallback: 'Current period')}\nNext billing date: ${_value(values, 'next_billing_at', fallback: 'See your billing workspace')}',
  );

  String _title(
    NotificationDefinition definition,
    Map<String, Object?> values,
  ) => _value(values, 'title', fallback: definition.subject);

  _Action? _action(Map<String, Object?> values) {
    final raw = values['action_url'];
    if (raw is! String) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    final allowedOrigins = <Uri>[dashboardOrigin, marketingOrigin];
    final isAllowed = allowedOrigins.any(
      (origin) =>
          origin.scheme == uri.scheme &&
          origin.host == uri.host &&
          origin.port == uri.port,
    );
    if (!isAllowed) return null;
    return _Action(
      label: _value(values, 'action_label', fallback: 'Open Hyfens Cloud'),
      url: uri.toString(),
    );
  }

  String _shell({
    required String title,
    required String preheader,
    required String content,
  }) =>
      '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${_escape(title)}</title><style>body{margin:0;background:#efede8;color:#171717;font-family:Arial,Helvetica,sans-serif}a{color:#171717}p{font-size:16px;line-height:1.6;margin:0 0 16px}strong{font-weight:700}@media(max-width:620px){.outer{padding:20px 12px!important}.panel{padding:28px 22px!important}}</style></head><body><div style="display:none;max-height:0;overflow:hidden;opacity:0">${_escape(preheader)}</div><table class="outer" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#efede8;padding:44px 20px"><tr><td align="center"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:620px;background:#ffffff;border:1px solid #d8d3cb"><tr><td class="panel" style="padding:38px 42px"><div style="font-size:18px;font-weight:700;letter-spacing:-.02em;margin-bottom:38px"><span aria-hidden="true" style="display:inline-block;width:9px;height:9px;margin-right:8px;background:#fd5510"></span>hyfens</div><div style="color:#716d67;font-size:12px;letter-spacing:.12em;text-transform:uppercase;margin-bottom:12px">Hyfens Cloud</div><h1 style="font-size:30px;line-height:1.12;letter-spacing:-.04em;margin:0 0 22px;color:#171717">${_escape(title)}</h1>$content</td></tr><tr><td style="padding:18px 42px;border-top:1px solid #e5e1db;color:#716d67;font-size:12px;line-height:1.5">Hyfens Cloud · Secure product communication<br><a href="${_escape(marketingOrigin.toString())}">hyfens.com</a> · <a href="mailto:support@hyfens.com">support@hyfens.com</a></td></tr></table></td></tr></table></body></html>''';

  String _cta(String label, String url) =>
      '<table role="presentation" cellspacing="0" cellpadding="0" border="0" style="margin:26px 0"><tr><td style="background:#171717"><a href="${_escape(url)}" style="display:inline-block;padding:13px 18px;color:#ffffff;text-decoration:none;font-weight:700;font-size:14px">${_escape(label)} ↗</a></td></tr></table><p style="font-size:12px;color:#716d67;word-break:break-word">If the button does not work, use this link:<br><a href="${_escape(url)}">${_escape(url)}</a></p>';

  String _summaryTable(Map<String, String> rows) =>
      '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin:24px 0;border-top:1px solid #ded9d1">${rows.entries.map((entry) => '<tr><td style="padding:11px 0;border-bottom:1px solid #ded9d1;color:#716d67;font-size:13px">${_escape(entry.key)}</td><td align="right" style="padding:11px 0;border-bottom:1px solid #ded9d1;color:#171717;font-size:13px;font-weight:700">${_escape(entry.value)}</td></tr>').join()}</table>';

  static String _value(
    Map<String, Object?> values,
    String key, {
    String fallback = '',
  }) {
    final value = values[key];
    return value == null ? fallback : '$value';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static void _requireHttps(Uri value, String label) {
    if (value.scheme != 'https' || value.host.isEmpty) {
      throw ArgumentError('$label must be an HTTPS origin');
    }
  }
}

final class _RenderedContent {
  const _RenderedContent({required this.html, required this.text});

  final String html;
  final String text;
}

final class _Action {
  const _Action({required this.label, required this.url});

  final String label;
  final String url;
}

/// Deterministic, provider-free fixtures for local template review. This
/// helper intentionally does not persist an event or accept a provider.
final class NotificationPreview {
  const NotificationPreview._();

  static NotificationRenderResult render({
    required String key,
    Uri? dashboardOrigin,
    Uri? marketingOrigin,
  }) => NotificationRenderer(
    dashboardOrigin: dashboardOrigin ?? Uri.parse('https://app.hyfens.com'),
    marketingOrigin: marketingOrigin ?? Uri.parse('https://hyfens.com'),
  ).render(fixture(key));

  static NotificationEvent fixture(String key) {
    NotificationCatalog.forKey(key);
    final variables = <String, Object?>{
      'organization': 'Example workspace',
      'plan': 'Starter',
      'amount': 'USD 49.00',
      'currency': 'USD',
      'billing_period': 'Monthly',
      'next_billing_at': '2026-10-08',
      'old_plan': 'Starter',
      'new_plan': 'Team',
      'effective_at': '2026-10-08',
      'payment_id': 'payment_preview',
      'status': 'Preview',
      'message': 'This is deterministic local preview content.',
      'occurred_at': '2026-09-09T12:00:00Z',
      'token': '123456',
      'expires_at': '2026-09-09T12:30:00Z',
      'action_url': 'https://app.hyfens.com/dashboard/billing',
      'action_label': 'Open billing',
    };
    return NotificationEvent(
      key: key,
      stableKey: 'preview:$key',
      recipientEmails: const <String>['preview@example.invalid'],
      variables: variables,
      occurredAt: DateTime.utc(2026, 9, 9, 12),
      source: 'preview',
    );
  }
}

/// Raw authentication tokens are never stored in plaintext in an outbox
/// event. This optional queue mode requires a protected 256-bit deployment
/// key. Self-hosted deployments without the key retain the existing direct
/// delivery seam rather than persisting a token unsafely.
final class NotificationPayloadProtector {
  NotificationPayloadProtector(List<int> keyBytes)
    : _secretKey = SecretKeyData(List<int>.from(keyBytes)) {
    if (keyBytes.length != 32) {
      throw ArgumentError.value(keyBytes, 'keyBytes', 'must contain 32 bytes');
    }
  }

  final SecretKey _secretKey;
  final AesGcm _algorithm = AesGcm.with256bits();

  static NotificationPayloadProtector? fromEnvironment(
    Map<String, String> values,
  ) {
    final raw = values['HYFENS_NOTIFICATION_PAYLOAD_KEY']?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64.decode(raw);
      return NotificationPayloadProtector(bytes);
    } on Object {
      throw ArgumentError(
        'HYFENS_NOTIFICATION_PAYLOAD_KEY must be base64 for 32 bytes',
      );
    }
  }

  Future<String> seal(Map<String, Object?> payload) async {
    final box = await _algorithm.encrypt(
      utf8.encode(canonicalJson(payload)),
      secretKey: _secretKey,
    );
    return base64UrlEncode(
      utf8.encode(
        jsonEncode(<String, String>{
          'nonce': base64UrlEncode(box.nonce),
          'ciphertext': base64UrlEncode(box.cipherText),
          'mac': base64UrlEncode(box.mac.bytes),
        }),
      ),
    );
  }

  Future<Map<String, Object?>> open(String encoded) async {
    try {
      final envelope = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (envelope is! Map ||
          envelope['nonce'] is! String ||
          envelope['ciphertext'] is! String ||
          envelope['mac'] is! String) {
        throw const FormatException('Invalid notification payload envelope');
      }
      final box = SecretBox(
        base64Url.decode(envelope['ciphertext'] as String),
        nonce: base64Url.decode(envelope['nonce'] as String),
        mac: Mac(base64Url.decode(envelope['mac'] as String)),
      );
      final decoded = jsonDecode(
        utf8.decode(await _algorithm.decrypt(box, secretKey: _secretKey)),
      );
      if (decoded is! Map)
        throw const FormatException('Payload is not an object');
      return <String, Object?>{
        for (final entry in decoded.entries) '${entry.key}': entry.value,
      };
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'Notification payload could not be decrypted',
      );
    }
  }
}

/// Durable event and delivery orchestration. The provider is called only by
/// this dispatcher, never from a Razorpay webhook or HTTP controller.
final class NotificationService implements HumanAuthNotificationSink {
  NotificationService({
    required this.store,
    required this.provider,
    required this.renderer,
    this.payloadProtector,
    DateTime Function()? clock,
    this.maxAttempts = 6,
    this.processingLease = const Duration(minutes: 5),
  }) : _clock = clock ?? (() => DateTime.now().toUtc()) {
    if (maxAttempts < 1 || maxAttempts > 20) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be 1..20');
    }
    if (processingLease < const Duration(seconds: 30) ||
        processingLease > const Duration(hours: 1)) {
      throw ArgumentError.value(
        processingLease,
        'processingLease',
        'must be between 30 seconds and 1 hour',
      );
    }
  }

  final ControlPlaneStore store;
  final NotificationProvider provider;
  final NotificationRenderer renderer;
  final NotificationPayloadProtector? payloadProtector;
  final DateTime Function() _clock;
  final int maxAttempts;
  final Duration processingLease;
  Future<void> _dispatchTail = Future<void>.value();

  static NotificationService? fromEnvironment({
    required ControlPlaneStore store,
    required Map<String, String> values,
  }) {
    final provider = KeplarsNotificationProvider.fromEnvironment(values);
    if (provider == null) return null;
    final origins = (values['HYFENS_WEB_ORIGINS'] ?? '')
        .split(',')
        .map((item) => Uri.tryParse(item.trim()))
        .whereType<Uri>()
        .where((item) => item.scheme == 'https' && item.host.isNotEmpty)
        .map((item) => item.replace(path: '', query: null, fragment: null))
        .toList(growable: false);
    final dashboard = origins.firstWhere(
      (origin) => origin.host == 'app.hyfens.com',
      orElse: () => Uri.parse('https://app.hyfens.com'),
    );
    final marketing = origins.firstWhere(
      (origin) => origin.host == 'hyfens.com',
      orElse: () => Uri.parse('https://hyfens.com'),
    );
    return NotificationService(
      store: store,
      provider: provider,
      renderer: NotificationRenderer(
        dashboardOrigin: dashboard,
        marketingOrigin: marketing,
      ),
      payloadProtector: NotificationPayloadProtector.fromEnvironment(values),
    );
  }

  bool get canQueueSensitiveMessages => payloadProtector != null;

  QueuedHumanMessageDelivery authMessageDelivery() {
    if (!canQueueSensitiveMessages) {
      throw StateError('A protected notification payload key is required');
    }
    return QueuedHumanMessageDelivery(this);
  }

  Future<String> enqueue(NotificationEvent event) async {
    final definition = NotificationCatalog.forKey(event.key);
    if (event.sensitive && payloadProtector == null) {
      throw StateError(
        'Sensitive notification ${definition.key} requires a protected payload key',
      );
    }
    final existing = await store.readJson(
      notificationEventCollection,
      event.id,
    );
    if (existing != null) {
      if (existing['key'] != event.key ||
          existing['version'] != event.version) {
        throw const StorageConflict('Notification event identity conflict');
      }
      await _ensureDeliveries(event, existing);
      await _audit(
        event: event,
        action: 'notification.queued',
        resourceId: event.id,
        metadata: <String, Object?>{
          'notification_key': definition.versionedKey,
          'recipient_count': event.recipientEmails.length,
          'reconciled': true,
        },
      );
      return event.id;
    }
    final record = <String, Object?>{
      'id': event.id,
      'key': event.key,
      'version': event.version,
      'organizationId': event.organizationId,
      'entityType': event.entityType,
      'entityId': event.entityId,
      'source': event.source,
      'correlationId': event.correlationId,
      'causationId': event.causationId,
      'provider': event.provider,
      'providerEventId': event.providerEventId,
      'occurredAt': event.occurredAt.toUtc().toIso8601String(),
      'createdAt': _clock().toUtc().toIso8601String(),
      'sensitive': event.sensitive,
      if (event.sensitive)
        'variablesCiphertext': await payloadProtector!.seal(event.variables)
      else
        'variables': event.variables,
    };
    try {
      await store.createJson(notificationEventCollection, event.id, record);
    } on StorageConflict {
      final concurrent = await store.readJson(
        notificationEventCollection,
        event.id,
      );
      if (concurrent == null ||
          concurrent['key'] != event.key ||
          concurrent['version'] != event.version) {
        rethrow;
      }
    }
    await _ensureDeliveries(event, record);
    await _audit(
      event: event,
      action: 'notification.queued',
      resourceId: event.id,
      metadata: <String, Object?>{
        'notification_key': definition.versionedKey,
        'recipient_count': event.recipientEmails.length,
      },
    );
    return event.id;
  }

  Future<void> _ensureDeliveries(
    NotificationEvent event,
    Map<String, Object?> record,
  ) async {
    for (final recipient in event.recipientEmails) {
      final id = _deliveryId(event.id, recipient);
      final delivery = <String, Object?>{
        'id': id,
        'eventId': event.id,
        'organizationId': event.organizationId,
        'recipient': recipient,
        'recipientDigest': sha256Digest(utf8.encode(recipient)),
        'state': NotificationDeliveryState.pending.wireValue,
        'attempts': 0,
        'queuedAt': _clock().toUtc().toIso8601String(),
        'nextAttemptAt': _clock().toUtc().toIso8601String(),
        'templateKey': '${record['key']}:v${record['version']}',
      };
      try {
        await store.createJson(notificationDeliveryCollection, id, delivery);
      } on StorageConflict {
        // A retry of the same event/recipient is the same delivery.
      }
    }
  }

  Future<int> dispatchPending({int limit = 50}) async {
    if (limit < 1 || limit > 500) throw ArgumentError.value(limit, 'limit');
    final now = _clock().toUtc();
    final rows = await store.listJson(notificationDeliveryCollection);
    final eligible = rows.where((row) => _isDispatchable(row, now)).take(limit);
    var processed = 0;
    for (final row in eligible) {
      final deliveryId = row['id'];
      if (deliveryId is String && await _dispatchOne(deliveryId)) {
        processed++;
      }
    }
    return processed;
  }

  Future<bool> _dispatchOne(String deliveryId) async {
    final previous = _dispatchTail;
    final gate = Completer<void>();
    _dispatchTail = gate.future;
    await previous;
    try {
      final now = _clock().toUtc();
      final claimId = _claimId(deliveryId, now);
      final delivery = await _claimDelivery(
        deliveryId: deliveryId,
        now: now,
        claimId: claimId,
      );
      if (delivery == null) return false;
      final eventId = delivery['eventId'];
      if (eventId is! String) {
        await _markFailed(delivery, 'missing_event_id', retryable: false);
        return true;
      }
      final eventRecord = await store.readJson(
        notificationEventCollection,
        eventId,
      );
      if (eventRecord == null) {
        await _markFailed(delivery, 'missing_event', retryable: false);
        return true;
      }
      final recipient = delivery['recipient'];
      if (recipient is! String) {
        await _markFailed(delivery, 'invalid_recipient', retryable: false);
        return true;
      }
      final attempts = delivery['attempts'] as int? ?? 1;
      late final Map<String, Object?> variables;
      late final NotificationEvent event;
      try {
        variables = eventRecord['sensitive'] == true
            ? await payloadProtector!.open(
                eventRecord['variablesCiphertext']! as String,
              )
            : _map(eventRecord['variables']);
        event = _eventFromRecord(eventRecord, variables);
      } on Object catch (error) {
        await _markFailed(
          delivery,
          'payload_error:${error.runtimeType}',
          retryable: false,
        );
        return true;
      }
      try {
        final result = await provider.send(
          renderer.messageFor(event, recipient),
          idempotencyKey: deliveryId,
        );
        final accepted = <String, Object?>{
          ...delivery,
          'state': result.state.wireValue,
          'attempts': attempts,
          'providerMessageId': result.providerMessageId,
          'acceptedAt': _clock().toUtc().toIso8601String(),
          'claimId': null,
          'processingAt': null,
          'processingLeaseUntil': null,
        };
        final updated = await _updateClaimedDelivery(
          deliveryId: deliveryId,
          claimId: claimId,
          value: accepted,
        );
        if (!updated) return true;
        await _audit(
          event: event,
          action: 'notification.provider_accepted',
          resourceId: deliveryId,
          metadata: <String, Object?>{
            'notification_key': '${event.key}:v${event.version}',
            'recipient_digest': sha256Digest(utf8.encode(recipient)),
            'provider_message_id': result.providerMessageId,
          },
        );
      } on NotificationProviderException catch (error) {
        await _markFailed(
          delivery,
          error.failureClass,
          retryable: error.retryable && attempts < maxAttempts,
          event: event,
        );
      } on Object catch (error) {
        await _markFailed(
          delivery,
          'worker_error:${error.runtimeType}',
          retryable: attempts < maxAttempts,
          event: event,
        );
      }
      return true;
    } finally {
      gate.complete();
    }
  }

  Future<void> _markFailed(
    Map<String, Object?> delivery,
    String failureClass, {
    required bool retryable,
    NotificationEvent? event,
  }) async {
    final attempts = delivery['attempts'] as int? ?? 0;
    final nextState = retryable
        ? NotificationDeliveryState.softFailed.wireValue
        : NotificationDeliveryState.hardFailed.wireValue;
    final delaySeconds = 1 << attempts.clamp(0, 6);
    final value = <String, Object?>{
      ...delivery,
      'state': nextState,
      'failureClass': failureClass,
      'failedAt': _clock().toUtc().toIso8601String(),
      'claimId': null,
      'processingAt': null,
      'processingLeaseUntil': null,
      if (retryable)
        'nextAttemptAt': _clock()
            .toUtc()
            .add(Duration(seconds: delaySeconds))
            .toIso8601String(),
    };
    final claimId = delivery['claimId'];
    final updated = claimId is String
        ? await _updateClaimedDelivery(
            deliveryId: delivery['id']! as String,
            claimId: claimId,
            value: value,
          )
        : await _replaceDelivery(delivery['id']! as String, value);
    if (!updated) return;
    final failedEvent = event;
    if (failedEvent != null) {
      try {
        await _audit(
          event: failedEvent,
          action: 'notification.delivery_failed',
          resourceId: delivery['id']! as String,
          metadata: <String, Object?>{
            'failure_class': failureClass,
            'retryable': retryable,
            'attempts': attempts,
          },
        );
      } on Object {
        // Delivery state remains authoritative if the audit store is briefly
        // unavailable; the next operator inspection can reconcile the row.
      }
    }
  }

  Future<Map<String, Object?>?> _claimDelivery({
    required String deliveryId,
    required DateTime now,
    required String claimId,
  }) async {
    final claimStore = store;
    if (claimStore case final NotificationDeliveryClaimStore durable) {
      return durable.claimNotificationDelivery(
        deliveryId: deliveryId,
        now: now,
        leaseUntil: now.add(processingLease),
        claimId: claimId,
      );
    }
    final current = await store.readJson(
      notificationDeliveryCollection,
      deliveryId,
    );
    if (current == null || !_isDispatchable(current, now)) return null;
    final claimed = <String, Object?>{
      ...current,
      'state': NotificationDeliveryState.processing.wireValue,
      'attempts': (current['attempts'] as int? ?? 0) + 1,
      'claimId': claimId,
      'processingAt': now.toIso8601String(),
      'processingLeaseUntil': now.add(processingLease).toIso8601String(),
    };
    await store.replaceJson(
      notificationDeliveryCollection,
      deliveryId,
      claimed,
    );
    return claimed;
  }

  Future<bool> _updateClaimedDelivery({
    required String deliveryId,
    required String claimId,
    required Map<String, Object?> value,
  }) async {
    final claimStore = store;
    if (claimStore case final NotificationDeliveryClaimStore durable) {
      return durable.updateClaimedNotificationDelivery(
        deliveryId: deliveryId,
        claimId: claimId,
        value: value,
      );
    }
    final current = await store.readJson(
      notificationDeliveryCollection,
      deliveryId,
    );
    if (current == null || current['claimId'] != claimId) return false;
    await store.replaceJson(notificationDeliveryCollection, deliveryId, value);
    return true;
  }

  Future<bool> _replaceDelivery(
    String deliveryId,
    Map<String, Object?> value,
  ) async {
    await store.replaceJson(notificationDeliveryCollection, deliveryId, value);
    return true;
  }

  bool _isDispatchable(Map<String, Object?> row, DateTime now) {
    final state = row['state'];
    if (state == NotificationDeliveryState.pending.wireValue ||
        state == NotificationDeliveryState.softFailed.wireValue) {
      final next = _parseDate(row['nextAttemptAt']);
      return next == null || !next.isAfter(now.toUtc());
    }
    if (state != NotificationDeliveryState.processing.wireValue) {
      return false;
    }
    final lease = _parseDate(row['processingLeaseUntil']);
    return lease == null || !lease.isAfter(now.toUtc());
  }

  static String _claimId(String deliveryId, DateTime now) {
    final entropy = List<int>.generate(
      16,
      (_) => math.Random.secure().nextInt(256),
    );
    return 'ncl_${sha256Hex(<int>[...utf8.encode('$deliveryId:${now.microsecondsSinceEpoch}:'), ...entropy]).substring(0, 32)}';
  }

  Future<String?> enqueueOrganizationEvent({
    required String organizationId,
    required String key,
    required String stableKey,
    required Map<String, Object?> variables,
    String? entityType,
    String? entityId,
    String source = 'hyfens',
    String? correlationId,
    String? causationId,
    String? provider,
    String? providerEventId,
  }) async {
    final definition = NotificationCatalog.forKey(key);
    final recipients = <String>{};
    for (final raw in await store.listJson('users')) {
      if (raw['active'] != true || raw['emailVerified'] != true) continue;
      final memberships = raw['memberships'];
      if (memberships is! List) continue;
      final belongs = memberships.any((item) {
        if (item is! Map || item['organizationId'] != organizationId) {
          return false;
        }
        if (definition.category != NotificationCategory.billing) return true;
        final role = item['role'];
        final rawCapabilities = item['capabilities'];
        final capabilities = rawCapabilities is List
            ? rawCapabilities.whereType<String>().toSet()
            : const <String>{};
        return role == 'owner' || capabilities.contains(billingManageScope);
      });
      if (belongs && raw['email'] is String)
        recipients.add(raw['email'] as String);
    }
    if (recipients.isEmpty) {
      return null;
    }
    return enqueue(
      NotificationEvent(
        key: key,
        stableKey: stableKey,
        organizationId: organizationId,
        entityType: entityType,
        entityId: entityId,
        recipientEmails: recipients.toList(growable: false),
        variables: variables,
        occurredAt: _clock(),
        source: source,
        correlationId: correlationId,
        causationId: causationId,
        provider: provider,
        providerEventId: providerEventId,
      ),
    );
  }

  Future<String?> enqueueBillingProviderResult(
    BillingProviderEventResult result, {
    required String requestId,
  }) async {
    // A provider retry may reach the control plane after the billing mutation
    // was committed but before the notification enqueue completed. Treating a
    // validated duplicate as eligible lets the deterministic notification ID
    // repair that gap without repeating the billing mutation or email.
    if ((result.status != 'applied' && result.status != 'duplicate') ||
        result.eventName == null) {
      return null;
    }
    final key = _billingNotificationKey(result);
    if (key == null) return null;
    final subscription = result.subscription;
    final payment = result.payment;
    final refund = result.refund;
    final variables = <String, Object?>{
      'organization': result.organizationId,
      'plan':
          subscription?['planKey'] ??
          result.checkout?['planKey'] ??
          'Hyfens Cloud',
      'amount': _money(payment?['amountMinor'], payment?['currency']),
      'currency': payment?['currency'],
      'status': refund?['status'] ?? subscription?['status'] ?? result.status,
      'payment_id': payment?['id'] ?? refund?['paymentId'],
      'provider_event_id': result.eventId,
      'effective_at':
          subscription?['currentEndAt'] ??
          result.scheduledPlanChange?['effectiveAt'],
      'message': _billingMessage(key, subscription, refund),
    };
    return enqueueOrganizationEvent(
      organizationId: result.organizationId,
      key: key,
      stableKey: 'razorpay:${result.eventId}',
      variables: variables,
      entityType: refund != null
          ? 'billing_refund'
          : payment != null
          ? 'billing_payment'
          : 'billing_subscription',
      entityId:
          refund?['id'] as String? ??
          payment?['id'] as String? ??
          subscription?['id'] as String?,
      source: 'razorpay_webhook',
      correlationId: requestId,
      provider: 'razorpay',
      providerEventId: result.eventId,
    );
  }

  Future<String> enqueueEnterpriseInquiry({
    required Map<String, Object?> inquiry,
    required Iterable<String> recipients,
  }) => enqueue(
    NotificationEvent(
      key: 'ops.enterprise.inquiry_received',
      stableKey: 'enterprise:${inquiry['id']}',
      recipientEmails: recipients.toList(growable: false),
      variables: <String, Object?>{
        'inquiry_id': inquiry['id'],
        'contact': inquiry['email'],
        'organization': inquiry['organization'],
        'message': inquiry['message'],
      },
      occurredAt: _parseDate(inquiry['createdAt']) ?? _clock(),
      source: 'public_onboarding',
      entityType: 'enterprise_inquiry',
      entityId: inquiry['id'] as String?,
    ),
  );

  @override
  Future<void> sendPasswordChanged({
    required HumanUserRecord user,
    required DateTime occurredAt,
  }) async {
    final organizationId = user.memberships
        .where(
          (membership) => membership.audience == customerAuthorizationAudience,
        )
        .map((membership) => membership.organizationId)
        .firstOrNull;
    await enqueue(
      NotificationEvent(
        key: 'auth.password.changed',
        stableKey:
            'password-changed:${user.id}:${occurredAt.toUtc().toIso8601String()}',
        recipientEmails: <String>[user.email],
        organizationId: organizationId,
        entityType: 'human_user',
        entityId: user.id,
        variables: <String, Object?>{
          'message': 'Your Hyfens password was changed successfully.',
          'occurred_at': occurredAt.toUtc().toIso8601String(),
          'action_url': renderer.dashboardOrigin.toString(),
          'action_label': 'Open Hyfens Cloud',
        },
        occurredAt: occurredAt,
        source: 'human_auth',
      ),
    );
  }

  Future<void> applyProviderDeliveryWebhook({
    required List<int> rawBody,
    required String signature,
    required String secret,
  }) async {
    final expected = crypto.Hmac(
      crypto.sha256,
      utf8.encode(secret),
    ).convert(rawBody).toString();
    if (!_constantTimeEquals(expected, signature)) {
      throw const FormatException('Invalid notification provider signature');
    }
    final decoded = jsonDecode(utf8.decode(rawBody));
    if (decoded is! Map ||
        decoded['email_id'] is! String ||
        decoded['event'] is! String) {
      throw const FormatException('Invalid notification provider event');
    }
    final providerMessageId = decoded['email_id'] as String;
    final providerEvent = decoded['event'] as String;
    final rows = await store.listJson(notificationDeliveryCollection);
    for (final row in rows.where(
      (item) => item['providerMessageId'] == providerMessageId,
    )) {
      final state = _providerDeliveryState(
        providerEvent,
        row['state'] as String?,
      );
      await store.replaceJson(
        notificationDeliveryCollection,
        row['id']! as String,
        <String, Object?>{
          ...row,
          'state': state.wireValue,
          'providerEvent': providerEvent,
          'providerEventAt': _clock().toUtc().toIso8601String(),
          'claimId': null,
          'processingAt': null,
          'processingLeaseUntil': null,
        },
      );
      final eventId = row['eventId'];
      final eventRecord = eventId is String
          ? await store.readJson(notificationEventCollection, eventId)
          : null;
      if (eventRecord == null) continue;
      final event = _eventFromRecord(
        eventRecord,
        eventRecord['sensitive'] == true
            ? const <String, Object?>{}
            : _map(eventRecord['variables']),
      );
      await _audit(
        event: event,
        action: 'notification.provider_status_updated',
        resourceId:
            '${row['id']! as String}:$providerMessageId:${decoded['event']}',
        metadata: <String, Object?>{
          'provider_message_id': providerMessageId,
          'provider_event': providerEvent,
          'delivery_state': state.wireValue,
        },
      );
    }
  }

  static NotificationDeliveryState _providerDeliveryState(
    String event,
    String? existing,
  ) {
    final next = switch (event) {
      'delivered' ||
      'email.delivered' ||
      'opened' ||
      'email.opened' ||
      'clicked' ||
      'email.clicked' => NotificationDeliveryState.delivered,
      'bounced' || 'email.bounced' => NotificationDeliveryState.bounced,
      'complained' ||
      'email.complained' => NotificationDeliveryState.complained,
      'failed' || 'email.failed' => NotificationDeliveryState.hardFailed,
      'cancelled' || 'email.cancelled' => NotificationDeliveryState.cancelled,
      _ => NotificationDeliveryState.accepted,
    };
    // Provider callbacks can arrive out of order. A late queued/sent callback
    // must not regress a terminal delivery result.
    if (next == NotificationDeliveryState.accepted &&
        (existing == NotificationDeliveryState.delivered.wireValue ||
            existing == NotificationDeliveryState.bounced.wireValue ||
            existing == NotificationDeliveryState.complained.wireValue ||
            existing == NotificationDeliveryState.hardFailed.wireValue ||
            existing == NotificationDeliveryState.cancelled.wireValue)) {
      return NotificationDeliveryState.values.firstWhere(
        (value) => value.wireValue == existing,
      );
    }
    return next;
  }

  Future<void> _audit({
    required NotificationEvent event,
    required String action,
    required String resourceId,
    required Map<String, Object?> metadata,
  }) async {
    final organizationId = event.organizationId ?? 'system';
    final id =
        'aud_notification_${sha256Hex(utf8.encode('$organizationId:$action:$resourceId')).substring(0, 32)}';
    final record = <String, Object?>{
      'id': id,
      'requestId': event.correlationId ?? event.id,
      'organizationId': organizationId,
      'actorId': event.source,
      'action': action,
      'resourceType': 'notification',
      'resourceId': resourceId,
      'result': 'SUCCESS',
      'metadata': <String, Object?>{
        ...metadata,
        'causation_id': event.causationId,
        'provider': event.provider,
        'provider_event_id': event.providerEventId,
      },
      'createdAt': _clock().toUtc().toIso8601String(),
    };
    try {
      await store.appendAudit(id, record);
    } on StorageConflict {
      final existing = await store.readJson('audit', id);
      if (existing == null) rethrow;
    }
  }

  NotificationEvent _eventFromRecord(
    Map<String, Object?> record,
    Map<String, Object?> variables,
  ) => NotificationEvent(
    key: record['key']! as String,
    idOverride: record['id']! as String,
    version: record['version'] as int? ?? 1,
    stableKey: record['id']! as String,
    recipientEmails: const <String>['queued@example.invalid'],
    variables: variables,
    occurredAt: _parseDate(record['occurredAt']) ?? _clock(),
    organizationId: record['organizationId'] as String?,
    entityType: record['entityType'] as String?,
    entityId: record['entityId'] as String?,
    source: record['source'] as String? ?? 'hyfens',
    correlationId: record['correlationId'] as String?,
    causationId: record['causationId'] as String?,
    provider: record['provider'] as String?,
    providerEventId: record['providerEventId'] as String?,
    sensitive: record['sensitive'] == true,
  );

  static Map<String, Object?> _map(Object? value) => value is Map
      ? <String, Object?>{
          for (final entry in value.entries) '${entry.key}': entry.value,
        }
      : <String, Object?>{};

  static String _deliveryId(String eventId, String recipient) =>
      'ndl_${sha256Hex(utf8.encode('$eventId:$recipient')).substring(0, 32)}';

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String _money(Object? amountMinor, Object? currency) {
    if (amountMinor is int && currency is String)
      return '$currency ${(amountMinor / 100).toStringAsFixed(2)}';
    return 'See your billing workspace';
  }

  static String _billingMessage(
    String key,
    Map<String, Object?>? subscription,
    Map<String, Object?>? refund,
  ) => switch (key) {
    'billing.subscription.activated' =>
      'Your new Hyfens plan is active after provider confirmation.',
    'billing.subscription.renewed' => 'Your recurring payment was captured and your Hyfens plan remains active.',
    'billing.payment.succeeded' => 'Your payment was captured successfully.',
    'billing.payment.failed' => 'A payment attempt needs attention. Your current paid state is not changed by this message alone.',
    'billing.refund.completed' =>
      'The approved refund was processed by the payment provider.',
    'billing.refund.failed' => 'The payment provider could not complete the approved refund. Hyfens will retry or reconcile it.',
    'billing.subscription.upgrade_applied' =>
      'Your higher Hyfens plan is now effective after provider confirmation.',
    'billing.subscription.downgrade_scheduled' => 'Your current paid plan remains active until the scheduled effective date.',
    'billing.subscription.downgrade_applied' => 'Your scheduled Hyfens plan change is now effective. Existing data remains in place.',
    'billing.subscription.cancelled' =>
      'Your subscription has stopped renewing. Existing data is retained.',
    _ => 'Hyfens recorded a billing update for your workspace.',
  };

  static String? _billingNotificationKey(BillingProviderEventResult result) {
    final eventName = result.eventName;
    if (eventName == null) return null;
    if (eventName == 'subscription.updated') {
      final change = result.scheduledPlanChange;
      if (change == null) return 'billing.subscription.upgrade_applied';
      return change['status'] == 'effective'
          ? 'billing.subscription.downgrade_applied'
          : 'billing.subscription.downgrade_scheduled';
    }
    return switch (eventName) {
      'subscription.activated' => 'billing.subscription.activated',
      'subscription.charged' => 'billing.subscription.renewed',
      'payment.captured' => 'billing.payment.succeeded',
      'subscription.halted' => 'billing.payment.action_required',
      'subscription.pending' => 'billing.payment.action_required',
      'payment.failed' ||
      'subscription.payment_failed' => 'billing.payment.failed',
      'subscription.resumed' => 'billing.subscription.reactivated',
      'subscription.cancelled' => 'billing.subscription.cancelled',
      'subscription.completed' ||
      'subscription.expired' => 'billing.subscription.cancelled',
      'refund.created' => 'billing.refund.initiated',
      'refund.processed' => 'billing.refund.completed',
      'refund.failed' || 'refund.reversed' => 'billing.refund.failed',
      _ => null,
    };
  }

  static bool _constantTimeEquals(String left, String right) {
    final a = utf8.encode(left);
    final b = utf8.encode(right);
    var difference = a.length ^ b.length;
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) difference |= a[i] ^ b[i];
    return difference == 0;
  }
}

/// Adapts the existing auth service seam to the durable notification queue.
/// The auth domain still owns token generation, hashing, expiry and purpose.
final class QueuedHumanMessageDelivery
    implements HumanAuthMessageDelivery, HumanDeletionMessageDelivery {
  const QueuedHumanMessageDelivery(this.notifications);

  final NotificationService notifications;

  @override
  Future<void> sendVerificationEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) => notifications
      .enqueue(
        NotificationEvent(
          key: 'auth.email.verification_requested',
          stableKey:
              'verification:$email:${expiresAt.toUtc().toIso8601String()}:${sha256Hex(utf8.encode(token))}',
          recipientEmails: <String>[email],
          variables: <String, Object?>{
            'token': token,
            'expires_at': expiresAt.toUtc().toIso8601String(),
            'action_url': notifications.renderer.dashboardOrigin.toString(),
            'action_label': 'Open Hyfens Cloud',
          },
          occurredAt: DateTime.now().toUtc(),
          source: 'human_auth',
          sensitive: true,
        ),
      )
      .then((_) {});

  @override
  Future<void> sendRecoveryEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) => notifications
      .enqueue(
        NotificationEvent(
          key: 'auth.password.recovery_requested',
          stableKey:
              'recovery:$email:${expiresAt.toUtc().toIso8601String()}:${sha256Hex(utf8.encode(token))}',
          recipientEmails: <String>[email],
          variables: <String, Object?>{
            'token': token,
            'expires_at': expiresAt.toUtc().toIso8601String(),
            'action_url': notifications.renderer.dashboardOrigin.toString(),
            'action_label': 'Open Hyfens Cloud',
          },
          occurredAt: DateTime.now().toUtc(),
          source: 'human_auth',
          sensitive: true,
        ),
      )
      .then((_) {});

  @override
  Future<void> sendDeletionEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) => notifications
      .enqueue(
        NotificationEvent(
          key: 'account.deletion.requested',
          stableKey:
              'deletion:$email:${expiresAt.toUtc().toIso8601String()}:${sha256Hex(utf8.encode(token))}',
          recipientEmails: <String>[email],
          variables: <String, Object?>{
            'token': token,
            'expires_at': expiresAt.toUtc().toIso8601String(),
            'action_url': notifications.renderer.marketingOrigin
                .replace(
                  path: '/account-deletion',
                  queryParameters: <String, String>{'token': token},
                )
                .toString(),
            'action_label': 'Review deletion request',
            'message': 'Someone requested deletion of a Hyfens Cloud account associated with this address.',
          },
          occurredAt: DateTime.now().toUtc(),
          source: 'human_auth',
          sensitive: true,
        ),
      )
      .then((_) {});
}

String _normalizeEmail(String value) => value.trim().toLowerCase();
