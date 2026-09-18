# Security policy

Status: AUTHORITATIVE reporting guidance for the public repository.

Please do not open a public issue for a suspected vulnerability. Include only
the minimum reproduction, affected version or commit, impact, and a safe
contact path. Do not include credentials, private keys, customer data, or
unredacted logs.

## Private reporting

Use the repository's
[private security advisory form](https://github.com/hyfens-hq/hyfens/security/advisories/new)
when it is available. If the form is not enabled for your account, contact a
Hyfens maintainer through a private channel controlled by the `hyfens-hq`
organization and request a private security contact. Do not publish sensitive
details while waiting for a response.

The project will acknowledge receipt when practical, coordinate a fix and
disclosure plan with the reporter, and credit reporters only with permission.
No response time, severity classification, or disclosure date is promised by
this policy.

## Scope reminders

The public repository is an early, bounded Flutter live-update foundation. It
does not claim arbitrary Dart patching, store-policy approval, production HA,
or protection against a rooted/fully compromised device. Those limitations do
not change the expectation that repository vulnerabilities and accidentally
committed secrets should be reported privately.

See the [security documentation](docs/README.md#security-and-governance) and
[contribution guide](CONTRIBUTING.md) for the broader project boundary.
