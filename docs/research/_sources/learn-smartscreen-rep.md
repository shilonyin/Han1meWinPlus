---
layout: Conceptual
title: SmartScreen reputation for Windows app developers - Windows apps | Microsoft Learn
canonicalUrl: https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
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
description: Understand how Windows Defender SmartScreen reputation works, what to expect when you publish a new app, and how to minimize warnings for your users.
ms.topic: concept-article
ms.date: 2026-05-04T00:00:00.0000000Z
ms.localizationpriority: medium
locale: en-us
document_id: b56f018d-5abd-ad4e-45b1-0a23d0b2360b
document_version_independent_id: b56f018d-5abd-ad4e-45b1-0a23d0b2360b
updated_at: 2026-08-17T16:28:00.0000000Z
original_content_git_url: https://github.com/MicrosoftDocs/windows-dev-docs-pr/blob/live/hub/apps/package-and-deploy/smartscreen-reputation.md
gitcommit: https://github.com/MicrosoftDocs/windows-dev-docs-pr/blob/18ce52af24e626bacd6f6b221e133546aa26e77a/hub/apps/package-and-deploy/smartscreen-reputation.md
git_commit_id: 18ce52af24e626bacd6f6b221e133546aa26e77a
site_name: Docs
depot_name: MSDN.windows-uwp-hub
page_type: conceptual
toc_rel: toc.json
pdf_url_template: https://learn.microsoft.com/pdfstore/en-us/MSDN.windows-uwp-hub/{branchName}{pdfName}
feedback_help_link_type: ''
feedback_help_link_url: ''
word_count: 866
asset_id: apps/package-and-deploy/smartscreen-reputation
moniker_range_name: 
monikers: []
item_type: Content
source_path: hub/apps/package-and-deploy/smartscreen-reputation.md
cmProducts:
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/cd440f3c-1b78-40a7-97ba-aa00a1d79df7
- https://authoring-docs-microsoft.poolparty.biz/devrel/bcbcbad5-4208-4783-8035-8481272c98b8
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/43ed1c2e-9691-4a3c-b165-ac4bf26ee8d4
spProducts:
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/c828f7e0-89b4-459c-9bae-d7ab1c4bd9ad
- https://authoring-docs-microsoft.poolparty.biz/devrel/43b2e5aa-8a6d-4de2-a252-692232e5edc8
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/8a92bf23-293a-4fa9-b96c-200e5c8aaf1c
platformId: 012973ab-d754-f519-51b9-3b089d0cd2e0
---

# SmartScreen reputation for Windows app developers - Windows apps | Microsoft Learn

Microsoft Defender SmartScreen checks the reputation of downloaded files before allowing them to run. Understanding how reputation works can help avoid warnings when users download or run your files.

Tip

**The simplest way to avoid SmartScreen warnings is to publish through the Microsoft Store.** Store-distributed apps are signed by a Microsoft certificate and are never subject to SmartScreen download warnings. The remainder of this article applies to apps distributed outside the Store.

## How SmartScreen reputation works

SmartScreen evaluates two signals when a user downloads and runs a file:

1. **Publisher reputation** — Is the file signed? Is the signing certificate from a known, trusted publisher?
2. **File hash reputation** — Has this specific file been downloaded by users without indications of malicious behavior?

A negative or unknown reputation for a file's hash or its publisher's certificate can cause warnings to show. Even when signed, a newly created binary could still show a SmartScreen warning until its hash or publisher certificate accumulates sufficient evidence of positive reputation.

When a file is not signed, SmartScreen reputation must build for each new version of your files, starting with zero reputation. Reputation cannot transfer from previous versions unless both were signed using the same publisher identity.

## Certificate options and their SmartScreen implications

To reduce the likelihood of interruption, you should sign all of your files with a valid certificate.

| Certificate type | First-download SmartScreen behavior |
| --- | --- |
| Microsoft Store | ✅ No warning — covered by Microsoft's certificate |
| Valid Certificate (OV/EV) | ⚠️ Warning — app flagged as unrecognized until reputation accumulates; verified publisher name is displayed |
| No signature | ⚠️ Warning — "Windows protected your PC"; User must choose "Run anyway" before the app can run. Enterprise policy can prevent continuation entirely. |
| Self-signed Certificate | ⚠️ Warning — Same behavior as no signature |

Note

EV certificates no longer bypass SmartScreen. Years ago, signing files with an Extended Validation (EV) code signing certificate would result in positive SmartScreen reputation by default, but this behavior no longer exists. EV certificates may matter for enterprise procurement, but they no longer impact SmartScreen behavior. Paying a premium for EV solely to avoid SmartScreen warnings is no longer justified.

### Microsoft Store (recommended)

Apps published through the Microsoft Store are re-signed by Microsoft and carry full reputation. Users will never see a SmartScreen warning for a Store-installed app.

### Artifact Signing (formerly Trusted Signing)

[Artifact Signing](/en-us/azure/trusted-signing/) (formerly Trusted Signing) is Microsoft's recommended code signing service for non-Store distribution:

- **Cost** — Starts at $9.99/month. See [Artifact Signing pricing](https://azure.microsoft.com/pricing/details/artifact-signing/).
- **No hardware token required** — integrates directly with CI/CD pipelines (GitHub Actions, Azure DevOps)
- **Identity validation required** — Microsoft validates your identity before issuing certificates
- **SmartScreen behavior** — reputation accumulates over time based on download volume and behavior

## What to expect when you publish a new app

1. **First downloads:** Users may see a SmartScreen prompt indicating the app is unrecognized. For signed apps, the publisher name is displayed. Users should proceed only after verifying the source.
2. **As downloads accumulate:** SmartScreen reputation builds up automatically. The prompt will stop appearing once the file hash has sufficient download history. There is no exact threshold, but it can take several weeks and hundreds of clean installs from a wide audience.
3. **New version:** Signing files using a trusted certificate can allow certificate reputation to build, potentially avoiding warnings on new files signed by the same trusted certificate. Unsigned files must build reputation anew with every update.

There is no need (or mechanism) to manually submit a file for SmartScreen reputation review for consumer endpoints. Reputation builds organically through download volume.

Note

Enterprise environments may have different SmartScreen behavior depending on policy configuration; for example, the ability to bypass a SmartScreen warning may be disabled. Enterprises may distribute files from Trusted Intranet locations not subject to SmartScreen review. Enterprise IT administrators may optionally submit files for review via the [Microsoft Security Intelligence portal](https://www.microsoft.com/en-us/wdsi/filesubmission). This can accelerate trust for internal or managed deployments.

## Minimizing SmartScreen warnings in practice

- **Publish to the Microsoft Store** where feasible — this is the most reliable way to avoid warnings entirely
- **Sign every release** — unsigned files cannot inherit a positive reputation from the signing certificate
- **Do not modify signed files** - Avoid modifying files after signing as doing so can [break the signature](/en-us/windows/win32/secbp/understanding-pe-signatures#security-implications) depending on client configuration
- **Do not sign potentially unwanted applications** - Avoid signing any file which exhibits [malicious or potentially unwanted application](/en-us/unified-secops/criteria) behavior, or the certificate may develop **negative** reputation
- **Use a consistent signing identity** — changing your signing certificate affects the publisher trust signal
- **Communicate with early adopters** — for new apps, let beta users know they may see a SmartScreen prompt on first download, and that they should only proceed after verifying the publisher and confirming they trust the download source

Tip

On Windows 11 devices, the Smart App Control feature may supersede SmartScreen Application Reputation. Smart App Control will block execution of unsigned files unless the file has a positive reputation. Smart App Control signature checks apply to all executable files, not just those downloaded from the Internet.
