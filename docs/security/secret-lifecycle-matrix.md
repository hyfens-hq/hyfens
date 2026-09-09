# Secret lifecycle matrix (P2)

No secret values belong in this repository. The matrix records the intended
owner, boundary, rotation, and incident behavior.

| Secret | Owner / issuer | Use | Storage boundary | Rotation / revocation | Backup / recovery | Incident action | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Patch-signing private key | customer/local release operator | sign Patch Format artifacts | offline signer or operator secret store | rotate by publishing a new trusted public key; replacement trust requires a store release | encrypted offline backup, tested recovery | stop releases, revoke operator access, ship new store release if trust changes | VERIFIED CUSTODY BOUNDARY |
| Audit-export signing key | customer/local evidence operator | sign off-box audit envelopes | offline evidence workstation/secret store | publish new audit key ID; retain old public keys for historical verification | separate encrypted backup | stop exports, mark key compromised, verify history with prior public key | DESIGN ONLY |
| Control credential | control-plane operator | release registration, promotion, audit read | operator secret store / one-time bootstrap output | issue replacement credential, revoke old credential | do not place plaintext in database backups | revoke immediately and review audit chain | VERIFIED LOCALLY |
| Delivery credential | installed app release operator | update-check and artifact fetch | app release configuration / protected delivery channel | issue replacement and ship a store release if embedded credential changes | do not copy into logs | revoke and ship replacement app configuration | VERIFIED LOCALLY |
| PostgreSQL credential | database operator | metadata persistence | database secret store / Compose secret injection | rotate connection credential during a controlled maintenance window | encrypted DB backup without shell history | disable old credential, restore only to approved target | VERIFIED LOCALLY |
| Object-store access key/secret | object-store operator | artifact persistence and inventory | object-store secret store / workload injection | rotate access pair, test read/write, revoke old pair | backup bytes and manifest; never backup secret in same bundle | revoke, quarantine writes, reconcile digests | VERIFIED LOCALLY |
| TLS private key | edge/proxy operator | public transport encryption | proxy/provider secret store | overlap old/new certificate, test clients, revoke old certificate | provider-managed recovery or approved encrypted escrow | remove compromised certificate, rotate upstream trust | PROVIDER DEPENDENT |

## Shared rules

* Never log bearer tokens, private keys, object secrets, database URLs, or raw
  request bodies.
* Record key IDs and digest identities, not secret material.
* A recovered database does not restore object-store bytes or patch trust by
  itself; reconciliation and release-bound signature verification remain
  mandatory.
* Key compromise and key loss are different incidents. Loss requires recovery
  from an approved backup; compromise requires revocation and a new trust
  decision.

The matrix is an engineering control boundary, not a KMS or compliance
certification.
