# Hyfens Domain Context

Status: CURRENT DOMAIN GLOSSARY

## Core hierarchy

`Organization → Application → Environment` is the authoritative customer
resource hierarchy. “Project” may be used in developer-facing copy, but it is
not a separate persisted domain entity; it refers to an Application.

## Product surfaces

- Customer Workspace operates one authenticated customer membership within its
  organization/application/environment context.
- Platform Console is a separate managed-platform surface for authorized
  Hyfens staff and uses explicit platform audience/capabilities.
- Shared authentication and API transport do not merge these audiences.

## Operational terms

- A Support Case is an auditable, tenant-aware customer/staff conversation.
- A commercial projection derives only from authoritative billing records and
  reports unavailable or multi-currency data instead of inventing totals.
- Archive/deactivate preserves historical records; it is not destructive
  deletion.
