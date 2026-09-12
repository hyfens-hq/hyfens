# Tax, retention, and geolocation research

**Research date:** 2026-09-12  
**Status:** Research-only; no application-code decision is made here.

This note is not legal or tax advice. It records primary-source findings and the decisions still needed from Hyfens' tax, accounting, privacy, and legal owners.

## Repository boundary

[Task 259](../../tasks/259-cloud-launch-operations-and-policy-gates.md) and [managed-operations research](managed-operations-research.md) already identify the unresolved GST/IGST/export-of-services treatment, invoice and credit-note ownership, tax wording, and financial/security/Enterprise/backup retention periods. This note avoids repeating those findings and narrows the gap to location evidence, classification, and retention-policy design.

The working repository assumption is an India-linked seller of a remote/managed Cloud service. The legal entity, GST registrations, establishments, merchant of record, customer mix, and whether Hyfens supplies on its own account are not established by the repository and must be confirmed.

## What the sources establish

### India GST/IGST — legal baseline

- The [CBIC IGST Act text](https://cbic-gst.gov.in/hindi/IGST-bill-e.html), sections 2(6), 2(13), and 2(17), treats cloud services and digital data storage as examples of OIDAR, defines export of services, and distinguishes an intermediary from a person supplying on its own account.
- For OIDAR, section 13(12) places the supply at the recipient's location. A recipient is deemed located in taxable territory when **any two** non-contradictory indicators are present: internet address, payment card, billing address, IP address, payment bank, SIM country code, or fixed-line location. IP/geolocation is therefore one possible indicator, not a standalone universal rule.
- For other services, section 12(2) uses the registered recipient's location or the unregistered recipient's address on record, falling back to the supplier's location when no address is available; section 13(2) generally uses the recipient's location for cross-border supplies. Section 13(8)(b) gives intermediary services a different result, so Hyfens must first classify its supply.
- Export-of-services treatment requires all section 2(6) conditions, including recipient and place of supply outside India and qualifying foreign-exchange/INR receipt. “Customer selected a foreign country” is not by itself a sufficient repository rule.
- [CGST Act section 36](https://www.indiacode.nic.in/indiacode/bitstream/123456789/15689/1/A2017-12.pdf) requires a registered person to retain books and records for 72 months from the annual-return due date, with a later-of extension for records involved in proceedings, appeals, revisions, or investigation. This is a tax-record floor for in-scope records, not a blanket period for every account field.
- [CBIC invoice rules](https://cbic-gst.gov.in/gst-invoice-rules.html) require fields including supplier/recipient details, invoice identity and date, description, value, tax rate/amount, and place of supply/state for inter-State supplies. [CBIC account/record rules](https://cbic-gst.gov.in/accnt-record-rules.html) require electronic records to be backed up, restorable, linked to source documents, and producible with an audit trail.

### EU VAT — legal baseline

- The [consolidated VAT Directive](https://eur-lex.europa.eu/eli/dir/2006/112/2025-04-14) generally places B2B services at the customer's business establishment/fixed establishment (Article 44). For B2C electronic services, Article 58 places the supply where the customer is established, has a permanent address, or usually resides. Article 196 makes the customer liable for qualifying Article 44 services supplied by a non-established supplier; Hyfens must confirm whether that mechanism applies to its product and customer.
- The [consolidated Implementing Regulation](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:02011R0282-20250414), Article 24b, generally uses two non-contradictory items from Article 24f for B2C electronic-service location, subject to specific network/decoder presumptions. Article 24f lists billing address, IP/geolocation, bank details, SIM mobile-country code, fixed-line location, and other commercially relevant information. The EUR 100,000 one-item simplification is tied to supplies from a business/fixed establishment in a Member State; Hyfens must not assume it applies to an India-only establishment.
- Article 247 leaves the invoice-storage period to each Member State; there is no single EU-wide invoice-retention number. Separate 10-year rules apply to particular records, including OSS records (Article 369k) and records of an electronic-interface facilitator (Article 242a), if Hyfens uses or falls within those regimes.
- The [European Commission place-of-taxation guidance](https://taxation-customs.ec.europa.eu/taxation/vat/vat-directive/place-taxation_en) is useful explanatory guidance, but the Directive and national implementing law control. The Commission's [ViDA page](https://taxation-customs.ec.europa.eu/taxation/vat/vat-digital-age-vida_en) is a change watch, not a present Hyfens implementation requirement.

### Privacy and data retention — legal baseline and timing

- Under the [GDPR](https://eur-lex.europa.eu/eli/reg/2016/679/), location data and online identifiers can be personal data. Purpose limitation, data minimisation, storage limitation, and a documented storage period/criterion apply. Article 17's erasure right has an exception where retention is necessary for a legal obligation or legal claims. A tax archive should therefore be narrow and access-restricted, not a reason to retain the whole account.
- India's [DPDP Act](https://www.meity.gov.in/writereaddata/files/Digital%20Personal%20Data%20Protection%20Act%202023.pdf) contains an erasure-when-purpose-ends rule subject to retention required by law, but the official [13 November 2025 commencement notification](https://www.meity.gov.in/static/uploads/2025/11/c56ceae6c383460ca69577428d36828b.pdf) puts section 8 in the 18-month phase. The [DPDP Rules 2025](https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf) likewise put rule 8 in the 18-month phase. On this research date, do not treat rule 8's future one-year processing-log floor or its narrow three-year schedule for specified large classes as a current universal Indian retention requirement.
- The [OECD International VAT/GST Guidelines](https://legalinstruments.oecd.org/public/doc/350/066a17c7-cc61-48c0-a065-436815d8a823.htm) recommend customer location for B2B, usual residence for remote B2C, and reliance on routinely collected, reasonably reliable evidence. They are an international recommendation, not binding Hyfens law.

## Decisions still required from Hyfens

1. **Supplier and customer model:** identify the contracting/merchant entity, GST registrations, establishments or fixed establishments, merchant of record, payment agent, and whether each sale is B2B, B2C, or an intermediary arrangement.
2. **Service classification:** decide whether Managed Cloud is supplied on Hyfens' own account and whether it is OIDAR/electronically supplied for the relevant market. Do not encode an intermediary or export rule before this decision.
3. **Location algorithm:** define the jurisdiction hierarchy and conflict handling at the chargeable event: customer legal/business address, GSTIN/VAT ID and validation, billing address, payment/bank country, IP/geolocation, SIM/phone evidence where available, and customer declarations. Decide how to handle VPNs, travel, multiple establishments, stale addresses, and missing or contradictory signals.
4. **Tax collection path:** decide India intra-State/inter-State/IGST/export handling, EU B2B reverse-charge handling, EU B2C registration/OSS strategy, applicable rates, tax-inclusive versus tax-exclusive USD pricing, and the legally responsible invoice/credit-note issuer.
5. **Evidence record:** decide the minimum immutable snapshot kept per chargeable event: customer status, jurisdiction result, signals relied on, rule/version, invoice/credit-note IDs, tax result, and any override/review reason.
6. **Retention matrix:** set separate periods and deletion behavior for invoices/credit notes, location evidence, VAT/GST IDs and addresses, payment/provider events, chargeback/refund records, security/fraud logs, audit records, backups, and legal holds. Define the start date for each period and the trigger for extending it when a proceeding or claim exists.
7. **Deletion and access:** define how tax evidence survives account deletion while unrelated profile, credential, and operational data are erased; minimize or pseudonymize retained personal data, restrict access, and document the legal basis and notice language for each retained class.
8. **Ownership and review:** assign tax/accounting, privacy/legal, finance, and engineering owners; set a re-review trigger for new countries, a changed payment model, EU VAT/ViDA changes, and DPDP commencement phases.

## Legal requirement versus operational practice

| Topic | Legal baseline | Operational practice to evaluate (not itself a legal requirement) |
| --- | --- | --- |
| Customer location | Use the applicable statutory test; India OIDAR and EU electronic B2C rules use multiple or prescribed evidence signals. | Capture a country/state-level decision snapshot at checkout or renewal rather than continuously tracking precise GPS. |
| Signal quality | IP/geolocation is one listed indicator and normally cannot satisfy a two-item rule alone. | Prefer customer-declared billing/business data plus an independent payment or network signal; route conflicts to review or a conservative fallback. |
| Evidence minimisation | Keep only what is needed to prove the tax result and comply with the relevant record rule. | Store the result, signal types, timestamps, rule version, and a recoverable reference; avoid retaining raw IP or precise coordinates when a derived country/state is sufficient. |
| Deletion | Tax-law retention can override erasure for the required records; privacy law still limits purpose, access, and duration. | Use a separate restricted tax/evidence archive with field-level minimisation and a documented deletion/hold workflow. |
| Payment provider | A gateway's receipt or fee document does not, without the issuer decision, settle who issues Hyfens' tax invoice. | Reconcile provider events to Hyfens' own invoice, credit-note, refund, and tax record. |

## Contradictions, assumptions, and cautions

- **Authority level:** the IGST Act supplies the enacted two-of-seven OIDAR test. A [CBIC/GST Council press release](https://cbic-gst.gov.in/pdf/Press-Release%20-55-GST-Council.pdf) separately recommends invoice treatment for certain online services to unregistered recipients. Treat that as an administrative clarification/recommendation, not as a substitute for checking the final notified Act/Rule position before implementation.
- **Retention is not one number:** India's 72-month tax rule, EU Member-State invoice periods, EU OSS/facilitator 10-year records, GDPR storage limitation, and future DPDP rules apply to different records and scopes. They should produce a data-class matrix, not a universal account-retention setting.
- **Classification is the largest unresolved dependency:** the same checkout signal can lead to different results depending on whether Hyfens is the principal supplier, an intermediary, an OIDAR supplier, or supplying a business customer. This note does not choose among those classifications.
- **Repository assumptions are provisional:** USD pricing, a payment gateway, and a managed Cloud offering appear in existing operations material, but the legal seller, registrations, and customer geography still need owner confirmation.

## Primary sources consulted

India: [CGST Act, India Code](https://www.indiacode.nic.in/indiacode/bitstream/123456789/15689/1/A2017-12.pdf), [IGST Act, CBIC](https://cbic-gst.gov.in/hindi/IGST-bill-e.html), [GST Invoice Rules](https://cbic-gst.gov.in/gst-invoice-rules.html), [GST Account and Record Rules](https://cbic-gst.gov.in/accnt-record-rules.html), and the [GST Council/CBIC press release](https://cbic-gst.gov.in/pdf/Press-Release%20-55-GST-Council.pdf).

EU: [VAT Directive, consolidated 14 April 2025](https://eur-lex.europa.eu/eli/dir/2006/112/2025-04-14), [VAT Implementing Regulation, consolidated 14 April 2025](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:02011R0282-20250414), [European Commission place-of-taxation guidance](https://taxation-customs.ec.europa.eu/taxation/vat/vat-directive/place-taxation_en), [GDPR](https://eur-lex.europa.eu/eli/reg/2016/679/), and [ViDA](https://taxation-customs.ec.europa.eu/taxation/vat/vat-digital-age-vida_en).

India privacy and international guidance: [DPDP Act](https://www.meity.gov.in/writereaddata/files/Digital%20Personal%20Data%20Protection%20Act%202023.pdf), [DPDP commencement notification](https://www.meity.gov.in/static/uploads/2025/11/c56ceae6c383460ca69577428d36828b.pdf), [DPDP Rules 2025](https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf), and [OECD International VAT/GST Guidelines](https://legalinstruments.oecd.org/public/doc/350/066a17c7-cc61-48c0-a065-436815d8a823.htm).
