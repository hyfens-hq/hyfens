import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

final class _RecordingProvider implements NotificationProvider {
  final List<NotificationMessage> messages = <NotificationMessage>[];
  bool fail = false;

  @override
  Future<NotificationProviderResult> send(
    NotificationMessage message, {
    required String idempotencyKey,
  }) async {
    if (fail) {
      throw const NotificationProviderException(
        'temporary test failure',
        retryable: true,
      );
    }
    messages.add(message);
    return NotificationProviderResult(
      state: NotificationDeliveryState.accepted,
      providerMessageId: 'mail_${messages.length}',
    );
  }
}

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late _RecordingProvider provider;
  late NotificationService notifications;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-notifications-');
    store = FileControlPlaneStore(directory);
    await store.initialize();
    provider = _RecordingProvider();
    notifications = NotificationService(
      store: store,
      provider: provider,
      renderer: NotificationRenderer(
        dashboardOrigin: Uri.parse('https://app.hyfens.com'),
        marketingOrigin: Uri.parse('https://hyfens.com'),
        clock: () => DateTime.utc(2026, 9, 9, 12),
      ),
      payloadProtector: NotificationPayloadProtector(List<int>.filled(32, 7)),
      clock: () => DateTime.utc(2026, 9, 9, 12),
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('catalogue and renderer provide a shared accessible message system', () {
    final keys = NotificationCatalog.definitions
        .map((item) => item.key)
        .toSet();
    expect(
      keys,
      containsAll(<String>[
        'auth.registration.completed',
        'auth.email.verification_requested',
        'billing.subscription.activated',
        'billing.payment.failed',
        'billing.subscription.downgrade_scheduled',
        'account.deletion.requested',
        'organization.deletion.requested',
      ]),
    );
    final event = NotificationEvent(
      key: 'billing.subscription.activated',
      stableKey: 'provider-event-1',
      recipientEmails: const <String>['Owner@Example.com'],
      variables: const <String, Object?>{
        'organization': 'Auvana workspace',
        'plan': 'Starter',
        'amount': 'USD 49.00',
        'message': 'Starter is active.',
      },
      occurredAt: DateTime.utc(2026, 9, 9),
      organizationId: 'org_notifications',
      source: 'razorpay_webhook',
    );
    final rendered = notifications.renderer.render(event);
    expect(rendered.html, contains('Auvana workspace'));
    expect(rendered.html, contains('Starter is active.'));
    expect(rendered.text, contains('USD 49.00'));
    expect(rendered.html, isNot(contains('undefined')));
  });

  test('customer emails show the Hyfens mark once in each body format', () {
    final brand = RegExp(r'\bhyfens\b', caseSensitive: false);
    final url = RegExp(r'https?://[^\s"<>]+');
    final tags = RegExp(r'<[^>]*>');

    String visibleHtml(String value) =>
        value.replaceAll(url, '').replaceAll(tags, ' ');
    String visibleText(String value) => value.replaceAll(url, ' ');

    for (final definition in NotificationCatalog.definitions) {
      final rendered = NotificationPreview.render(key: definition.key);
      expect(
        brand.allMatches(visibleHtml(rendered.html)).length,
        1,
        reason: '${definition.key} HTML',
      );
      expect(
        brand.allMatches(visibleText(rendered.text)).length,
        1,
        reason: '${definition.key} text',
      );
    }
  });

  test('Keplars adapter records the current top-level provider id', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/v1/send-email/normal');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-key',
        );
        expect(request.headers.value('Idempotency-Key'), 'delivery-1');
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'id': 'msg_current_provider_shape',
              'object': 'email',
              'status': 'queued',
            }),
          );
        await request.response.close();
      });

      final provider = KeplarsNotificationProvider(
        apiKey: 'test-key',
        apiBase: Uri.parse('http://127.0.0.1:${server.port}/api/v1'),
      );
      final result = await provider.send(
        const NotificationMessage(
          to: 'owner@example.com',
          subject: 'Test notification',
          preheader: 'Test notification',
          html: '<p>Test notification</p>',
          text: 'Test notification',
          sender: HyfensSenderPolicy.transactional,
          priority: 'normal',
          eventId: 'event-1',
        ),
        idempotencyKey: 'delivery-1',
      );

      expect(result.state, NotificationDeliveryState.accepted);
      expect(result.providerMessageId, 'msg_current_provider_shape');
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'Keplars adapter accepts the documented nested data.id response',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      try {
        server.listen((request) async {
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'success': true,
                'data': <String, Object?>{
                  'id': '456',
                  'message': 'Email queued successfully',
                },
              }),
            );
          await request.response.close();
        });

        final provider = KeplarsNotificationProvider(
          apiKey: 'test-key',
          apiBase: Uri.parse('http://127.0.0.1:${server.port}/api/v1'),
        );
        final result = await provider.send(
          const NotificationMessage(
            to: 'owner@example.com',
            subject: 'Test notification',
            preheader: 'Test notification',
            html: '<p>Test notification</p>',
            text: 'Test notification',
            sender: HyfensSenderPolicy.transactional,
            priority: 'normal',
            eventId: 'event-1',
          ),
          idempotencyKey: 'delivery-2',
        );

        expect(result.providerMessageId, '456');
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('enqueue is idempotent and creates one recipient delivery', () async {
    final event = NotificationEvent(
      key: 'billing.subscription.activated',
      stableKey: 'provider-event-2',
      recipientEmails: const <String>['owner@example.com'],
      variables: const <String, Object?>{'plan': 'Starter'},
      occurredAt: DateTime.utc(2026, 9, 9),
      organizationId: 'org_notifications',
    );
    final first = await notifications.enqueue(event);
    final second = await notifications.enqueue(event);

    expect(second, first);
    expect(await store.listJson(notificationEventCollection), hasLength(1));
    expect(await store.listJson(notificationDeliveryCollection), hasLength(1));
    expect(
      (await store.listJson(notificationDeliveryCollection)).single['state'],
      'pending',
    );
  });

  test('dispatcher sends once and records provider acceptance', () async {
    final event = NotificationEvent(
      key: 'billing.payment.succeeded',
      stableKey: 'payment-1',
      recipientEmails: const <String>['owner@example.com'],
      variables: const <String, Object?>{
        'plan': 'Team',
        'amount': 'USD 199.00',
        'message': 'Payment received.',
      },
      occurredAt: DateTime.utc(2026, 9, 9),
      organizationId: 'org_notifications',
    );
    await notifications.enqueue(event);

    expect(await notifications.dispatchPending(), 1);
    expect(await notifications.dispatchPending(), 0);
    expect(provider.messages, hasLength(1));
    expect(provider.messages.single.subject, 'Payment received');
    expect(provider.messages.single.text, contains('USD 199.00'));
    expect(
      (await store.listJson(notificationDeliveryCollection)).single['state'],
      'accepted',
    );
  });

  test(
    'expired processing lease is reclaimed with the same delivery ID',
    () async {
      await notifications.enqueue(
        NotificationEvent(
          key: 'billing.payment.succeeded',
          stableKey: 'lease-recovery-1',
          recipientEmails: const <String>['owner@example.com'],
          variables: const <String, Object?>{'message': 'Payment received.'},
          occurredAt: DateTime.utc(2026, 9, 9),
          organizationId: 'org_notifications',
        ),
      );
      final delivery = (await store.listJson(notificationDeliveryCollection))
          .single;
      await store.replaceJson(
        notificationDeliveryCollection,
        delivery['id']! as String,
        <String, Object?>{
          ...delivery,
          'state': 'processing',
          'attempts': 1,
          'claimId': 'stale-worker',
          'processingLeaseUntil': '2026-09-09T11:59:00Z',
        },
      );

      expect(await notifications.dispatchPending(), 1);
      final recovered = (await store.listJson(notificationDeliveryCollection))
          .single;
      expect(recovered['state'], 'accepted');
      expect(recovered['attempts'], 2);
      expect(provider.messages, hasLength(1));
    },
  );

  test('concurrent workers claim one delivery and send once', () async {
    await notifications.enqueue(
      NotificationEvent(
        key: 'billing.payment.succeeded',
        stableKey: 'concurrent-worker-1',
        recipientEmails: const <String>['owner@example.com'],
        variables: const <String, Object?>{'message': 'Payment received.'},
        occurredAt: DateTime.utc(2026, 9, 9),
        organizationId: 'org_notifications',
      ),
    );
    final secondWorker = NotificationService(
      store: store,
      provider: provider,
      renderer: notifications.renderer,
      payloadProtector: NotificationPayloadProtector(List<int>.filled(32, 7)),
      clock: () => DateTime.utc(2026, 9, 9, 12),
    );

    final results = await Future.wait(<Future<int>>[
      notifications.dispatchPending(),
      secondWorker.dispatchPending(),
    ]);

    expect(results.reduce((left, right) => left + right), 1);
    expect(provider.messages, hasLength(1));
    expect(
      (await store.listJson(notificationDeliveryCollection)).single['state'],
      'accepted',
    );
  });

  test(
    'sensitive auth payloads are encrypted at rest and decrypted only to send',
    () async {
      final delivery = notifications.authMessageDelivery();
      await delivery.sendVerificationEmail(
        email: 'owner@example.com',
        token: 'verification-token',
        expiresAt: DateTime.utc(2026, 9, 9, 13),
      );
      final event = (await store.listJson(notificationEventCollection)).single;
      expect(event['variables'], isNull);
      expect(event['variablesCiphertext'], isA<String>());
      expect(
        event['variablesCiphertext'],
        isNot(contains('verification-token')),
      );

      await notifications.dispatchPending();
      expect(provider.messages.single.html, contains('verification-token'));
    },
  );

  test('provider failure remains retryable without losing the event', () async {
    provider.fail = true;
    await notifications.enqueue(
      NotificationEvent(
        key: 'billing.payment.failed',
        stableKey: 'payment-failed-1',
        recipientEmails: const <String>['owner@example.com'],
        variables: const <String, Object?>{
          'message': 'Payment needs attention.',
        },
        occurredAt: DateTime.utc(2026, 9, 9),
        organizationId: 'org_notifications',
      ),
    );

    await notifications.dispatchPending();
    final delivery = (await store.listJson(notificationDeliveryCollection))
        .single;
    expect(delivery['state'], 'soft_failed');
    expect(delivery['failureClass'], 'provider_error');
    expect(await store.listJson(notificationEventCollection), hasLength(1));
  });

  test(
    'undecryptable sensitive payload is terminal and not left processing',
    () async {
      await store.createJson(
        notificationEventCollection,
        'nev_corrupt',
        <String, Object?>{
          'id': 'nev_corrupt',
          'key': 'auth.email.verification_requested',
          'version': 1,
          'organizationId': null,
          'source': 'human_auth',
          'sensitive': true,
          'variablesCiphertext': 'not-a-valid-envelope',
          'occurredAt': '2026-09-09T12:00:00Z',
          'createdAt': '2026-09-09T12:00:00Z',
        },
      );
      await store.createJson(
        notificationDeliveryCollection,
        'ndl_corrupt',
        <String, Object?>{
          'id': 'ndl_corrupt',
          'eventId': 'nev_corrupt',
          'recipient': 'owner@example.com',
          'state': 'pending',
          'attempts': 0,
        },
      );

      await notifications.dispatchPending();

      final delivery = (await store.listJson(notificationDeliveryCollection))
          .single;
      expect(delivery['state'], 'hard_failed');
      expect(delivery['failureClass'], startsWith('payload_error:'));
    },
  );

  test(
    'duplicate provider result repairs the same notification identity',
    () async {
      await store.createJson('users', 'usr_notifications', <String, Object?>{
        'id': 'usr_notifications',
        'email': 'owner@example.com',
        'active': true,
        'emailVerified': true,
        'memberships': <Map<String, Object?>>[
          <String, Object?>{
            'organizationId': 'org_notifications',
            'role': 'owner',
          },
        ],
      });
      const result = BillingProviderEventResult(
        status: 'duplicate',
        eventId: 'evt-replayed',
        eventName: 'payment.captured',
        organizationId: 'org_notifications',
        payment: <String, Object?>{
          'id': 'pay_replayed',
          'amountMinor': 4900,
          'currency': 'USD',
        },
      );

      final first = await notifications.enqueueBillingProviderResult(
        result,
        requestId: 'request-1',
      );
      final second = await notifications.enqueueBillingProviderResult(
        result,
        requestId: 'request-2',
      );

      expect(second, first);
      expect(await store.listJson(notificationEventCollection), hasLength(1));
      expect(
        await store.listJson(notificationDeliveryCollection),
        hasLength(1),
      );
    },
  );

  test('provider delivery callback normalizes state and is audited', () async {
    await notifications.enqueue(
      NotificationEvent(
        key: 'billing.payment.succeeded',
        stableKey: 'callback-1',
        recipientEmails: const <String>['owner@example.com'],
        variables: const <String, Object?>{'message': 'Captured.'},
        occurredAt: DateTime.utc(2026, 9, 9),
        organizationId: 'org_notifications',
      ),
    );
    await notifications.dispatchPending();
    final delivery = (await store.listJson(notificationDeliveryCollection))
        .single;
    final body = utf8.encode(
      jsonEncode(<String, Object?>{
        'event': 'delivered',
        'email_id': delivery['providerMessageId'],
      }),
    );
    final signature = Hmac(
      sha256,
      utf8.encode('callback-secret'),
    ).convert(body).toString();

    await notifications.applyProviderDeliveryWebhook(
      rawBody: body,
      signature: signature,
      secret: 'callback-secret',
    );

    expect(
      (await store.listJson(notificationDeliveryCollection)).single['state'],
      'delivered',
    );
    expect(
      (await store.listJson('audit')),
      contains(
        predicate<Map<String, Object?>>(
          (value) => value['action'] == 'notification.provider_status_updated',
        ),
      ),
    );

    final lateSentBody = utf8.encode(
      jsonEncode(<String, Object?>{
        'event': 'email.sent',
        'email_id': delivery['providerMessageId'],
      }),
    );
    final lateSentSignature = Hmac(
      sha256,
      utf8.encode('callback-secret'),
    ).convert(lateSentBody).toString();
    await notifications.applyProviderDeliveryWebhook(
      rawBody: lateSentBody,
      signature: lateSentSignature,
      secret: 'callback-secret',
    );
    expect(
      (await store.listJson(notificationDeliveryCollection)).single['state'],
      'delivered',
    );
  });

  test(
    'provider callback accepts the documented Keplars payload and signature',
    () async {
      await notifications.enqueue(
        NotificationEvent(
          key: 'billing.payment.succeeded',
          stableKey: 'keplars-payload-1',
          recipientEmails: const <String>['owner@example.com'],
          variables: const <String, Object?>{'message': 'Captured.'},
          occurredAt: DateTime.utc(2026, 9, 9),
          organizationId: 'org_notifications',
        ),
      );
      await notifications.dispatchPending();
      final body = utf8.encode(
        jsonEncode(<String, Object?>{
          'id': 'evt_keplars_1',
          'event_type': 'email.delivered',
          'email_id': 'mail_1',
          'status': 'delivered',
        }),
      );
      final digest = Hmac(
        sha256,
        utf8.encode('callback-secret'),
      ).convert(body).toString();

      await notifications.applyProviderDeliveryWebhook(
        rawBody: body,
        signature: 'sha256=$digest',
        secret: 'callback-secret',
      );

      expect(
        (await store.listJson(notificationDeliveryCollection)).single['state'],
        'delivered',
      );
    },
  );

  test(
    'late terminal provider callbacks cannot regress a terminal state',
    () async {
      await notifications.enqueue(
        NotificationEvent(
          key: 'billing.payment.succeeded',
          stableKey: 'callback-terminal-order-1',
          recipientEmails: const <String>['owner@example.com'],
          variables: const <String, Object?>{'message': 'Captured.'},
          occurredAt: DateTime.utc(2026, 9, 9),
          organizationId: 'org_notifications',
        ),
      );
      await notifications.dispatchPending();

      Future<void> callback(String eventType) async {
        final body = utf8.encode(
          jsonEncode(<String, Object?>{
            'id': 'evt_terminal_$eventType',
            'event_type': eventType,
            'email_id': 'mail_1',
          }),
        );
        final digest = Hmac(
          sha256,
          utf8.encode('callback-secret'),
        ).convert(body).toString();
        await notifications.applyProviderDeliveryWebhook(
          rawBody: body,
          signature: 'sha256=$digest',
          secret: 'callback-secret',
        );
      }

      await callback('email.delivered');
      await callback('email.bounced');
      await callback('email.sent');

      expect(
        (await store.listJson(notificationDeliveryCollection)).single['state'],
        'delivered',
      );
    },
  );

  test(
    'provider callbacks require the exact provider message identifier',
    () async {
      await notifications.enqueue(
        NotificationEvent(
          key: 'billing.payment.succeeded',
          stableKey: 'callback-no-heuristics-1',
          recipientEmails: const <String>['owner@example.com'],
          variables: const <String, Object?>{'message': 'Captured.'},
          occurredAt: DateTime.utc(2026, 9, 9),
          organizationId: 'org_notifications',
        ),
      );
      await notifications.dispatchPending();
      final delivery = (await store.listJson(notificationDeliveryCollection))
          .single;
      final body = utf8.encode(
        jsonEncode(<String, Object?>{
          'id': 'evt_unrelated',
          'event_type': 'email.delivered',
          'email_id': 'provider-id-for-another-message',
          'recipient': 'owner@example.com',
          'subject': 'Payment received',
        }),
      );
      final digest = Hmac(
        sha256,
        utf8.encode('callback-secret'),
      ).convert(body).toString();

      await notifications.applyProviderDeliveryWebhook(
        rawBody: body,
        signature: 'sha256=$digest',
        secret: 'callback-secret',
      );

      expect(
        delivery['providerMessageId'],
        isNot('provider-id-for-another-message'),
      );
      expect(
        (await store.listJson(notificationDeliveryCollection)).single['state'],
        'accepted',
      );
      final unmatchedAudit = (await store.listJson('audit')).where(
        (record) =>
            record['action'] == 'notification.provider_callback_unmatched',
      );
      expect(unmatchedAudit, hasLength(1));
      final auditJson = jsonEncode(unmatchedAudit.single);
      expect(auditJson, isNot(contains('provider-id-for-another-message')));
      expect(auditJson, isNot(contains('owner@example.com')));
      expect(auditJson, isNot(contains('Payment received')));
    },
  );

  test('custom web origins are used for notification action links', () {
    final configured = NotificationService.fromEnvironment(
      store: store,
      values: <String, String>{
        'KEPLARS_API_KEY': 'test-key',
        'HYFENS_WEB_ORIGINS':
            'https://cloud.example.test,https://www.example.test',
      },
    );

    expect(configured, isNotNull);
    expect(
      configured!.renderer.dashboardOrigin,
      Uri.parse('https://cloud.example.test'),
    );
    expect(
      configured.renderer.marketingOrigin,
      Uri.parse('https://www.example.test'),
    );
  });

  test(
    'token-bearing notification keys require encrypted payload storage',
    () async {
      final unprotected = NotificationService(
        store: store,
        provider: provider,
        renderer: notifications.renderer,
      );

      await expectLater(
        unprotected.enqueue(
          NotificationEvent(
            key: 'auth.password.recovery_requested',
            stableKey: 'unprotected-recovery-1',
            recipientEmails: const <String>['owner@example.com'],
            variables: const <String, Object?>{
              'token': 'hfr_sensitive_token',
              'expires_at': '2026-09-09T12:15:00Z',
            },
            occurredAt: DateTime.utc(2026, 9, 9),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'renderer formats customer dates and keeps long summary values readable',
    () {
      final rendered = notifications.renderer.render(
        NotificationEvent(
          key: 'billing.subscription.cancelled',
          stableKey: 'date-formatting-1',
          recipientEmails: const <String>['owner@example.com'],
          variables: const <String, Object?>{
            'plan': 'Enterprise Annual Contract With A Deliberately Long Name',
            'organization': 'Workspace With A Deliberately Long Customer Name',
            'effective_at': '2026-09-30T18:29:00.000Z',
            'message': 'Renewal has been stopped for this subscription.',
          },
          occurredAt: DateTime.utc(2026, 9, 9, 12),
          organizationId: 'org_notifications',
        ),
      );

      expect(rendered.html, contains('September 30, 2026 at 06:29 PM UTC'));
      expect(rendered.html, contains('summary-row'));
      expect(rendered.html, contains('summary-value'));
      expect(rendered.html, isNot(contains('2026-09-30T18:29:00.000Z')));
      expect(rendered.text, isNot(contains('2026-09-30T18:29:00.000Z')));
    },
  );

  test(
    'recovery notification uses the dedicated reset route and human expiry',
    () async {
      await notifications.authMessageDelivery().sendRecoveryEmail(
        email: 'owner@example.com',
        token: 'hfr_recovery_token',
        expiresAt: DateTime.utc(2026, 9, 9, 12, 15),
      );

      await notifications.dispatchPending();

      final message = provider.messages.single;
      expect(message.html, contains('Reset password'));
      expect(
        message.html,
        contains(
          'https://hyfens.com/auth/reset-password?token=hfr_recovery_token',
        ),
      );
      expect(message.html, contains('Expires in 15 minutes'));
      expect(message.html, isNot(contains('2026-09-09T12:15:00.000Z')));
      expect(message.html, contains('hfr_recovery_token'));
    },
  );

  test('preview renders without persisting or invoking a provider', () {
    final rendered = NotificationPreview.render(
      key: 'billing.subscription.downgrade_scheduled',
    );
    expect(rendered.html, contains('Example workspace'));
    expect(rendered.text, contains('Starter'));
    expect(rendered.html, contains('If the button does not work'));
  });

  test('notification previews do not leak raw ISO customer timestamps', () {
    final isoTimestamp = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');
    for (final definition in NotificationCatalog.definitions) {
      final rendered = NotificationPreview.render(key: definition.key);
      expect(
        rendered.html,
        isNot(matches(isoTimestamp)),
        reason: definition.key,
      );
      expect(
        rendered.text,
        isNot(matches(isoTimestamp)),
        reason: definition.key,
      );
    }
  });

  test(
    'password security notification is queued through shared catalogue',
    () async {
      final user = HumanUserRecord(
        id: 'usr_password',
        email: 'owner@example.com',
        passwordHash: 'hash',
        active: true,
        memberships: <HumanMembership>[
          HumanMembership(
            organizationId: 'org_notifications',
            role: 'owner',
            capabilities: const <String>{'billing:manage'},
            profileName: 'owner',
          ),
        ],
        createdAt: DateTime.utc(2026, 9, 9),
      );
      await notifications.sendPasswordChanged(
        user: user,
        occurredAt: DateTime.utc(2026, 9, 9, 12),
      );
      final event = (await store.listJson(notificationEventCollection)).single;
      expect(event['key'], 'auth.password.changed');
      expect(event['organizationId'], 'org_notifications');
    },
  );

  test(
    'billing provider event resolves the organization from memberships',
    () async {
      await store.createJson('users', 'usr_notifications', <String, Object?>{
        'id': 'usr_notifications',
        'email': 'owner@example.com',
        'active': true,
        'emailVerified': true,
        'memberships': <Map<String, Object?>>[
          <String, Object?>{
            'organizationId': 'org_notifications',
            'role': 'owner',
          },
        ],
      });
      await notifications.enqueueBillingProviderResult(
        const BillingProviderEventResult(
          status: 'applied',
          eventId: 'evt-payment-1',
          eventName: 'payment.captured',
          organizationId: 'org_notifications',
          payment: <String, Object?>{
            'id': 'pay_1',
            'amountMinor': 4900,
            'currency': 'USD',
          },
        ),
        requestId: 'request-1',
      );
      expect(await store.listJson(notificationEventCollection), hasLength(1));
      expect(
        (await store.listJson(notificationEventCollection)).single['key'],
        'billing.payment.succeeded',
      );
    },
  );
}
