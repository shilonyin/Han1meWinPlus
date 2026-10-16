---
layout: Conceptual
title: Code signing options for Windows app developers - Windows apps | Microsoft Learn
canonicalUrl: https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options
ms.service: windows-app-sdk
recommendations: true
ROBOTS: INDEX, FOLLOW
author: GrantMeStrength
ms.author: jken
Search.Product: eADQiWindows 10XVcnh
uhfHeaderId: MSDocsHeader-WinDevCenter
breadcrumb_path: /windows/breadcrumbs/toc.json
feedback_product_url: https://github.com/microsoft/msix-packaging/issues
feedback_system: OpenSource
ms.subservice: deployment
ms.update-cycle: 365-days
description: Compare code signing options for Windows apps distributed outside the Microsoft Store, including Azure Artifact Signing.
ms.topic: concept-article
ms.date: 2026-08-29T00:00:00.0000000Z
ms.localizationpriority: medium
locale: en-us
document_id: 24800f7e-ca76-797c-8bd2-ba63925342c5
document_version_independent_id: 24800f7e-ca76-797c-8bd2-ba63925342c5
updated_at: 2026-08-29T19:49:00.0000000Z
original_content_git_url: https://github.com/MicrosoftDocs/windows-dev-docs-pr/blob/live/hub/apps/package-and-deploy/code-signing-options.md
gitcommit: https://github.com/MicrosoftDocs/windows-dev-docs-pr/blob/e3f2840c3a685c4a4179d7d065a363573b2891b6/hub/apps/package-and-deploy/code-signing-options.md
git_commit_id: e3f2840c3a685c4a4179d7d065a363573b2891b6
site_name: Docs
depot_name: MSDN.windows-uwp-hub
page_type: conceptual
toc_rel: toc.json
pdf_url_template: https://learn.microsoft.com/pdfstore/en-us/MSDN.windows-uwp-hub/{branchName}{pdfName}
feedback_help_link_type: ''
feedback_help_link_url: ''
word_count: 1135
asset_id: apps/package-and-deploy/code-signing-options
moniker_range_name: 
monikers: []
item_type: Content
source_path: hub/apps/package-and-deploy/code-signing-options.md
cmProducts:
- https://authoring-docs-microsoft.poolparty.biz/devrel/4b35afe4-f177-4444-b587-bbae23b28d54
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/43ed1c2e-9691-4a3c-b165-ac4bf26ee8d4
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/cd440f3c-1b78-40a7-97ba-aa00a1d79df7
spProducts:
- https://authoring-docs-microsoft.poolparty.biz/devrel/2c4d2a56-33f6-41a4-9a47-c33d39ecc38e
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/8a92bf23-293a-4fa9-b96c-200e5c8aaf1c
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/c828f7e0-89b4-459c-9bae-d7ab1c4bd9ad
platformId: e1102efc-b3af-e75f-1092-00416a5cf285
---

# Code signing options for Windows app developers - Windows apps | Microsoft Learn

If you publish your app as an **MSIX package** through the Microsoft Store, code signing is free and handled for you automatically — Microsoft re-signs the package after certification and you don't need to purchase or manage a certificate. If you publish as an **MSI/EXE installer** through the Store, you are responsible for Authenticode signing your installer before submission. Everything else in this article applies to apps distributed **outside the Microsoft Store**.

## Comparison at a glance

| Option | Cost | Availability | SmartScreen behavior | Store eligible | Best for |
| --- | --- | --- | --- | --- | --- |
| **Microsoft Store (MSIX)** — Store re-signs your package | Free | Worldwide | ✅ No warnings | ✅ Yes | Recommended for most new apps |
| **Microsoft Store (MSI/EXE installer)** — publisher must sign | Cert chaining to [Trusted Root Program CA](/en-us/security/trusted-root/participants-list) required (varies by CA) | Worldwide | ✅ No SmartScreen prompts during Store install (UAC may still appear) | ✅ Yes | Existing Win32 apps submitting via MSI/EXE installer path |
| **Azure Artifact Signing** (formerly Trusted Signing) | ~$9.99/month | Organizations: USA, Canada, EU, UK. Individuals: USA and Canada only | ⚠️ Reputation builds over time; initial warnings expected | ❌ No | Recommended for non-Store distribution |
| **OV certificate** (from a CA such as DigiCert, Sectigo) | $150–300/year | Worldwide | ⚠️ Same as Azure Artifact Signing — reputation builds over time | ❌ No | Developers who can't use Azure Artifact Signing, or who prefer traditional CAs |
| **EV certificate** | $400+/year | Worldwide | ⚠️ Same as OV since 2024 — no longer instant bypass | ❌ No | No longer recommended specifically for SmartScreen bypass |
| **Self-signed certificate** | Free | — | ❌ Blocks installation for public users | ❌ No | Dev/testing only, or enterprise with managed certificate trust |
| **No signature** | Free | — | ❌ Strong SmartScreen block; enterprises may block entirely | ❌ No | Not recommended for public distribution |

## Microsoft Store — MSIX submissions: no signing needed

Publishing an **MSIX package** through the Microsoft Store is the recommended distribution path for most Windows apps. Microsoft re-signs your package automatically, meaning users never see a SmartScreen warning and you never need to purchase or renew a certificate.

Note

If you're submitting a **Win32 MSI or EXE installer** to the Store (rather than an MSIX package), Microsoft does not re-sign your installer. The installer and its PE files must be signed with a certificate chaining to a CA in the [Microsoft Trusted Root Program](/en-us/security/trusted-root/participants-list) — self-signed certificates are not accepted. See [App package requirements for MSI/EXE](../publish/publish-your-app/msi/app-package-requirements).

Create a free developer account at https://storedeveloper.microsoft.com. After you register, use [Partner Center](https://partner.microsoft.com/dashboard) to submit your app and manage its listing.

→ [Publish your app to the Microsoft Store](../publish/publish-your-app/msix/create-app-submission)

## Azure Artifact Signing (formerly Trusted Signing) — recommended for non-Store distribution

[Azure Artifact Signing (formerly Trusted Signing)](/en-us/azure/trusted-signing/) is Microsoft's recommended code signing service for developers who distribute apps outside the Store.

**Key details:**

- **Cost:** Approximately $9.99/month — significantly less than a traditional OV or EV certificate
- **Identity validation:** Microsoft validates your organization or individual identity before issuing certificates; plan for a few business days for verification
- **No hardware token required:** Signing integrates directly with CI/CD pipelines (GitHub Actions, Azure DevOps, and others) — you don't need a physical USB token
- **SmartScreen behavior:** New files can show a SmartScreen warning until they accumulate sufficient reputation. Azure Artifact Signing does **not** provide instant SmartScreen trust, but signing consecutive releases with a consistent publisher/signing identity lets publisher reputation build over time, so later releases can inherit trust. See [SmartScreen reputation](smartscreen-reputation).

Important

**Geographic limitation:** Azure Artifact Signing is available to organizations in the USA, Canada, the European Union, and the United Kingdom. Individual developers are currently limited to the USA and Canada. If you are an individual developer outside those regions, see OV certificates below.

→ [Azure Artifact Signing documentation](/en-us/azure/trusted-signing/) → [Sign an MSIX package using SignTool](/en-us/windows/msix/package/sign-app-package-using-signtool)

## OV certificates — traditional CA option

Organization Validated (OV) certificates from a Certificate Authority (CA) such as DigiCert, Sectigo, or GlobalSign are a well-established option for code signing. They are the right choice when:

- You are located outside the USA, Canada, the EU, or the UK (organizations); or outside the USA or Canada (individual developers) and cannot use Azure Artifact Signing
- Your organization already has a relationship with a specific CA
- Your enterprise customers require a certificate from a particular CA

**Key details:**

- **Cost:** Typically $150–300/year depending on the CA and certificate tier
- **Identity validation:** The CA validates your organization's legal identity before issuing the certificate; allow several business days
- **HSM requirement:** As of June 2023, the CA/Browser Forum requires private keys for OV certificates to be stored on a hardware security module (HSM) or hardware token. Most CAs provide a compatible USB token or cloud HSM option.
- **SmartScreen behavior:** Expect SmartScreen prompts for new files until reputation is established. As with any trusted certificate, signing releases with a consistent identity lets publisher reputation accumulate across versions, rather than starting from zero each time.

OV certificates are a proven option and are functionally equivalent to Azure Artifact Signing for SmartScreen purposes. If you are in the US or Canada (or an organization in the EU or UK), Azure Artifact Signing is typically more cost-effective and integrates more smoothly with automated build pipelines.

## EV certificates — no longer recommended for SmartScreen

Extended Validation (EV) certificates previously bypassed SmartScreen entirely on first download, making them the go-to choice for new apps with no reputation. **That behavior was removed in 2024.** EV-signed files now go through the same reputation-building process as OV certificates.

**What this means:**

- If you already have an EV certificate, it is still valid and functional for signing — keep using it until it expires
- EV certificates still require more rigorous identity validation, which may matter for enterprise procurement or other trust contexts
- Paying the EV premium ($400+/year) solely to avoid SmartScreen warnings is **no longer justified** — you will still see the same warnings as with an OV certificate

→ [SmartScreen reputation for developers](smartscreen-reputation) for full details on how reputation builds and what users see

## Self-signed certificates — dev and testing only

A self-signed certificate is not trusted by Windows by default and will trigger a strong SmartScreen block for any user who hasn't manually installed the certificate as a trusted root. This makes self-signed certificates unsuitable for public distribution.

**Appropriate uses:**

- **Local development and testing** — you control the machine and can install the certificate manually
- **Enterprise internal distribution** — your IT department can deploy the certificate as a trusted root via Intune or Group Policy, allowing managed devices to install the app silently

→ [Sign an MSIX package using SignTool](/en-us/windows/msix/package/sign-app-package-using-signtool)

## Open source: SignPath Foundation

If your project is open source, [SignPath Foundation](https://signpath.io) offers free code signing for qualifying open-source projects. The program provides OV-level certificate signing through a managed pipeline. Check the SignPath Foundation website for eligibility requirements and the application process.
