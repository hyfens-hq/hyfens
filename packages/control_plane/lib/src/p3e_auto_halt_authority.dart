import 'domain.dart';
import 'p3e_auto_halt.dart';
import 'p3e_claim.dart';

/// Structural proof that future P3E5-4 application code received both
/// independent authorities. It performs no work transition or rollout call.
final class AutomaticHaltAuthority {
  AutomaticHaltAuthority({
    required this.lease,
    required this.principal,
    required DateTime authoritativeNow,
  }) {
    validateAt(authoritativeNow);
  }

  void validateAt(DateTime authoritativeNow) {
    final now = authoritativeNow.toUtc();
    if (principal.kind != CredentialKind.autoHalt ||
        principal.revoked ||
        (principal.expiresAt != null &&
            !principal.expiresAt!.toUtc().isAfter(now)) ||
        principal.scopes.length != autoHaltScopes.length ||
        !principal.scopes.containsAll(autoHaltScopes) ||
        principal.organizationId != lease.scope.organizationId ||
        principal.applicationId != lease.scope.applicationId ||
        principal.environmentId != lease.scope.environmentId) {
      throw const FormatException(
        'Automatic-halt authorities are invalid or do not share exact scope',
      );
    }
  }

  final P3e5LeaseMutation lease;
  final CredentialRecord principal;

  String get workId => lease.workId;
  int get expectedWorkVersion => lease.expectedWorkVersion;
  String get leaseOwner => lease.leaseOwner;
  String get leaseTokenDigest => lease.tokenDigest;
  String get principalId => principal.id;
}

final class P3e5AutomaticHaltIntentAdvance {
  P3e5AutomaticHaltIntentAdvance({
    required this.authority,
    required this.intent,
  }) {
    if (authority.workId != intent.workId ||
        authority.principalId != intent.authorizedPrincipalId) {
      throw const FormatException(
        'Automatic-halt intent does not match both authorities',
      );
    }
  }

  final AutomaticHaltAuthority authority;
  final AutomaticHaltIntent intent;
}
