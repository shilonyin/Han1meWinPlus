---
layout: Conceptual
title: 'Quickstart: Set up Artifact Signing | Microsoft Learn'
canonicalUrl: https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart
breadcrumb_path: /azure/bread/toc.json
feedback_help_link_url: https://learn.microsoft.com/answers/tags/133/azure
feedback_help_link_type: get-help-at-qna
feedback_product_url: https://feedback.azure.com/d365community/forum/79b1327d-d925-ec11-b6e6-000d3a4f06a4
feedback_system: Standard
permissioned-type: public
recommendations: true
recommendation_types:
- Training
- Certification
uhfHeaderId: azure
ms.suite: office
adobe-target: true
learn_banner_products:
- azure
description: This quickstart helps you get started with using Artifact Signing to sign your files.
author: TacoTechSharma
ms.author: mesharm
ms.service: azure-artifact-signing
ms.topic: quickstart
ms.date: 2026-05-21T00:00:00.0000000Z
ms.custom:
- references_regions
- devx-track-azurecli
- sfi-image-nochange
locale: en-us
document_id: e4b0e144-eede-8b1c-e536-295777681092
document_version_independent_id: 2186292b-e047-9ab0-49e2-c1120f9fdf1a
updated_at: 2026-10-08T05:11:00.0000000Z
original_content_git_url: https://github.com/MicrosoftDocs/azure-docs-pr/blob/live/articles/artifact-signing/quickstart.md
gitcommit: https://github.com/MicrosoftDocs/azure-docs-pr/blob/e20e84153a340971c919c91fe827535f3f771870/articles/artifact-signing/quickstart.md
git_commit_id: e20e84153a340971c919c91fe827535f3f771870
site_name: Docs
depot_name: Azure.azure-documents
page_type: conceptual
toc_rel: toc.json
pdf_url_template: https://learn.microsoft.com/pdfstore/en-us/Azure.azure-documents/{branchName}{pdfName}
word_count: 4334
asset_id: artifact-signing/quickstart
moniker_range_name: 
monikers: []
item_type: Content
source_path: articles/artifact-signing/quickstart.md
cmProducts:
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/43ed1c2e-9691-4a3c-b165-ac4bf26ee8d4
- https://authoring-docs-microsoft.poolparty.biz/devrel/68ec7f3a-2bc6-459f-b959-19beb729907d
- https://authoring-docs-microsoft.poolparty.biz/devrel/089c8ba6-d135-43ff-bfaf-b8197fb72fb9
spProducts:
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/8a92bf23-293a-4fa9-b96c-200e5c8aaf1c
- https://authoring-docs-microsoft.poolparty.biz/devrel/90370425-aca4-4a39-9533-d52e5e002a5d
- https://authoring-docs-microsoft.poolparty.biz/devrel/32516e21-6665-416f-be21-413febe47d91
platformId: e7b62a47-c327-67c3-cc09-d510f370999b
---

# Quickstart: Set up Artifact Signing | Microsoft Learn

Artifact Signing is a Microsoft fully managed, end-to-end certificate signing service. In this quickstart, you create the following three Artifact Signing resources to begin using Artifact Signing:

- An Artifact Signing account
- An identity validation
- A certificate profile

You can use either the Azure portal or an Azure CLI extension to create and manage most of your Artifact Signing resources. (You can complete identity validation *only* in the Azure portal. You can't complete identity validation by using the Azure CLI.) This quickstart shows you how.

## Prerequisites

Note

Public Trust certificates are available to organizations in the United States, Canada, the European Union, the United Kingdom, Australia, New Zealand, Japan, South Korea, Singapore, Switzerland, Norway, and Israel. Individual developers must be located in the United States or Canada. These geographic restrictions do not apply to Private Trust certificates.

Note

For Public Trust individual identity validation, Artifact Signing automatically sources identity details from the Azure billing account associated with the subscription used to create the Artifact Signing resource. The billing account must have an Account Type of Individual. The legal name and sold-to address on the billing account must match the information on the government-issued ID used for identity validation. Before starting validation, review and update the legal name and sold-to address as needed. This information appears on the Public Trust certificate profile. For instructions, see [Manage billing accounts](/en-us/microsoft-365/commerce/manage-billing-accounts?toc=/azure/artifact-signing/toc.json&amp;bc=/azure/artifact-signing/breadcrumb/toc.json). This billing account type requirement applies only to individual identity validation. Organization identity validation doesn't require an Azure billing account with an Account Type of Organization.

To complete this quickstart, you need:

- A Microsoft Entra tenant ID.

    For more information, see [Create a Microsoft Entra tenant](/en-us/azure/active-directory/fundamentals/create-new-tenant#create-a-new-tenant-for-your-organization).
- An Azure subscription.

    If you don't already have one, see [Create an Azure subscription](../cost-management-billing/manage/create-subscription#create-a-subscription) before you begin.

## Register the Artifact Signing resource provider

Before you use Artifact Signing, you must register the Artifact Signing resource provider.

A resource provider is a service that supplies Azure resources. Use the Azure portal or the Azure CLI to register the `Microsoft.CodeSigning` Artifact Signing resource provider.

# [Azure portal](#tab/registerrp-portal)
To register an Artifact Signing resource provider by using the Azure portal:

1. Sign in to the [Azure portal](https://portal.azure.com/).
2. In either the search box or under **All services**, select **Subscriptions**.
3. Select the subscription where you want to create Artifact Signing resources.
4. On the resource menu under **Settings**, select **Resource providers**.
5. In the list of resource providers, select **Microsoft.CodeSigning**.

    By default, the resource provider status is **NotRegistered**.

[![Screenshot that shows creating an Artifact Signing account.](media/artifact-signing-resource-provider-registration.png)](media/artifact-signing-resource-provider-registration.png#lightbox)

1. Select the ellipsis, and then select **Register**.

    [![Screenshot that shows the Microsoft.CodeSigning resource provider as registered.](media/artifact-signing-resource-provider.png)](media/artifact-signing-resource-provider.png#lightbox)

    The status of the resource provider changes to **Registered**.

# [Azure CLI](#tab/registerrp-cli)
To register an Artifact Signing resource provider by using the Azure CLI:

1. If you're using a local installation of the Azure CLI, sign in to the Azure CLI by using the `az login` command.
2. To finish the authentication process, complete the steps that appear in your terminal. For other sign-in options, see [Sign in by using the Azure CLI](/en-us/cli/azure/authenticate-azure-cli).
3. When you're prompted on first use, install the Azure CLI extension.

    For more information, see [Use extensions with the Azure CLI](/en-us/cli/azure/azure-cli-extensions-overview).

    For more information about the Artifact Signing Azure CLI extension, see [Artifact Signing service](/en-us/cli/azure/service-page/trusted%20signing%20service?view=azure-cli-latest&amp;preserve-view=true).
4. To see the versions of the Azure CLI and the dependent libraries that are installed, use the `az version` command.
5. To upgrade to the latest versions of the Azure CLI and dependent libraries, run the following command:

    ```azurecli
    az upgrade [--all {false, true}] [--allow-preview {false, true}] [--yes]
    ```
6. To set your default subscription ID, use the `az account set -s <subscription ID>` command.
7. To register an Artifact Signing resource provider, use this command:

    ```azurecli
    az provider register --namespace "Microsoft.CodeSigning"
    ```
8. Verify the registration:

    ```azurecli
    az provider show --namespace "Microsoft.CodeSigning"
    ```
9. To add the extension for Artifact Signing, use this command:

    ```azurecli
    az extension add --name artifact-signing
    ```

# [Azure PowerShell](#tab/registerrp-azpowershell)
1. Install [Azure PowerShell](/en-us/powershell/azure/install-azure-powershell) and [sign in](/en-us/powershell/azure/authenticate-azureps).
2. To set your default subscription ID, use the `Set-AzContext -Subscription <subscription ID>` command.
3. Verify the registration:

    ```powershell
    Get-AzResourceProvider -ProviderNamespace Microsoft.CodeSigning
    ```

---

## Create an Artifact Signing account

An Artifact Signing account is a logical container that holds identity validation and certificate profile resources. An identity validation is available at the subscription ID level and can be shared across all the Artifact Signing accounts within that subscription.

### Azure regions that support Artifact Signing

You can create Artifact Signing resources only in Azure regions where the service is currently available. The following table lists the Azure regions that currently support Artifact Signing resources:

| Region | Region class fields | Endpoint URI value |
| --- | --- | --- |
| Brazil South | BrazilSouth | `https://brs.codesigning.azure.net` |
| Central US | CentralUS | `https://cus.codesigning.azure.net` |
| East US | EastUS | `https://eus.codesigning.azure.net` |
| Japan East | JapanEast | `https://jpe.codesigning.azure.net` |
| Korea Central | KoreaCentral | `https://krc.codesigning.azure.net` |
| North Central US | NorthCentralUS | `https://ncus.codesigning.azure.net` |
| North Europe | NorthEurope | `https://neu.codesigning.azure.net` |
| Poland Central | PolandCentral | `https://plc.codesigning.azure.net` |
| South Central US | SouthCentralUS | `https://scus.codesigning.azure.net` |
| Switzerland North | SwitzerlandNorth | `https://swn.codesigning.azure.net` |
| West Central US | WestCentralUS | `https://wcus.codesigning.azure.net` |
| West Europe | WestEurope | `https://weu.codesigning.azure.net` |
| West US | WestUS | `https://wus.codesigning.azure.net` |
| West US 2 | WestUS2 | `https://wus2.codesigning.azure.net` |
| West US 3 | WestUS3 | `https://wus3.codesigning.azure.net` |

### Naming constraints for Artifact Signing accounts

Artifact Signing account names have some constraints.

An Artifact Signing account name must:

- Contain from 3 to 24 alphanumeric characters.
- Be globally unique.
- Begin with a letter.
- End with a letter or number.
- Not contain consecutive hyphens.

An Artifact Signing account name is:

- Not case-sensitive (*ABC* is the same as *abc*).
- Rejected by Azure Resource Manager if it begins with "one".

# [Azure portal](#tab/account-portal)
To create an Artifact Signing account by using the Azure portal:

1. Sign in to the [Azure portal](https://portal.azure.com/).
2. Search for and then select **Artifact Signing Accounts**.

    [![Screenshot that shows searching for Artifact Signing Accounts in the Azure portal.](media/artifact-signing-search-service.png)](media/artifact-signing-search-service.png#lightbox)
3. On the **Artifact Signing Accounts** pane, select **Create**.
4. For **Subscription**, select your Azure subscription.
5. For **Resource group**, select **Create new**, and then enter a resource group name.
6. For **Account name**, enter a unique account name.

    For more information, see Naming constraints for Artifact Signing accounts.
7. For **Region**, select an Azure region that supports Artifact Signing.
8. For **Pricing**, select a pricing tier.
9. Select the **Review + Create** button.

    [![Screenshot that shows creating an Artifact Signing account.](media/artifact-signing-account-creation.png)](media/artifact-signing-account-creation.png#lightbox)
10. After you successfully create your Artifact Signing account, select **Go to resource**.

# [Azure CLI](#tab/account-cli)
To create an Artifact Signing account by using the Azure CLI:

1. Create a resource group by using the following command. If you choose to use an existing resource group, skip this step.

```azurecli
   az group create --name MyResourceGroup --location EastUS
```

1. Create a unique Artifact Signing account by using the following command.

    For more information, see Naming constraints for Artifact Signing accounts.

    To create an Artifact Signing account that has a Basic SKU:

```azurecli
  az artifact-signing create -n MyAccount -l eastus -g MyResourceGroup --sku Basic
```

To create an Artifact Signing account that has a Premium SKU:

```azurecli
  az artifact-signing create -n MyAccount -l eastus -g MyResourceGroup --sku Premium
```

1. Verify your Artifact Signing account by using:

```azurecli
  az artifact-signing show -g MyResourceGroup -n MyAccount`
```

Note

If you use an earlier version of the Azure CLI from the Artifact Signing preview, your account defaults to the Basic SKU. To use the Premium SKU, either upgrade the Azure CLI to the latest version or use the Azure portal to create the account.

The following table lists *helpful commands* to use when you create an Artifact Signing account:

| Command | Description |
| --- | --- |
| `az artifact-signing -h` | Shows help commands and detailed options. |
| `az artifact-signing show -n MyAccount  -g MyResourceGroup` | Shows the details of an account. |
| `az artifact-signing update -n MyAccount -g MyResourceGroup --tags "key1=value1 key2=value2"` | Updates tags. |
| `az artifact-signing list -g MyResourceGroup` | Lists all accounts that are in a resource group. |

# [Azure PowerShell](#tab/account-azpowershell)
To create an Artifact Signing account by using the Azure CLI:

1. Create a resource group by using the following command. If you choose to use an existing resource group, skip this step.

```powershell
   New-AzResourceGroup -Name "MyResourceGroup" -Location "EastUS"
```

1. Create a unique Artifact Signing account by using the following command.

    For more information, see Naming constraints for Artifact Signing accounts.

    To create an Artifact Signing account that has a Basic SKU:

```powershell
   New-AzArtifactSigningAccount -AccountName test -ResourceGroupName rg-test -Location eastus -SkuName Basic
```

To create an Artifact Signing account that has a Premium SKU:

```powershell
  New-AzArtifactSigningAccount -AccountName test -ResourceGroupName rg-test -Location eastus -SkuName Premium
```

1. Verify your Artifact Signing account by using:

```powershell
  Get-AzArtifactSigningAccount -AccountName test -ResourceGroupName rg-test
```

---

## Create an identity validation request

You can complete your own identity validation by filling in the request form with the information that must be included in the certificate. Identity validation can be completed only in the Azure portal. You can't complete identity validation by using the Azure CLI.

Note

You can't create an identity validation request if you aren't assigned the appropriate role. If the **New identity** button on the menu bar appears dimmed in the Azure portal, ensure that you're assigned the Artifact Signing Identity Verifier role to proceed with identity validation.

# [Identity Validation - Organization](#tab/orgvalidation)
To create an identity validation request for an Organization or a DBA:

1. In the Azure portal, go to your new Artifact Signing account.
2. Confirm that you're assigned the Artifact Signing Identity Verifier role.

    To learn how to manage, access by using role-based access control (RBAC), see [Tutorial: Assign roles in Artifact Signing](tutorial-assign-roles).
3. On the Artifact Signing account **Overview** pane or on the resource menu under **Objects**, select **Identity validations**.
4. Select **Organization**, select **New Identity**, and then select either **Public** or **Private**.

    - Public identity validation applies only to these certificate profile types: Public Trust, Public Trust Test, VBS Enclave.
    - Private identity validation applies only to these certificate profile types: Private Trust, Private Trust CI Policy.
5. On **New organization validation**, enter the below details that meet the requirements.

    | Fields | Details |
    | --- | --- |
    | **Organization Name** | For public identity validation, provide the legal business entity to which the certificate is issued. For private identity validation, the value defaults to your Microsoft Entra tenant name. |
    | **(Private Identity Type only) Organizational Unit** | Enter the relevant information. |
    | **Website url** | Enter the website that belongs to the legal business entity. |
    | **Primary Email** | Enter a monitored email address on a domain owned by the legal business entity. Verified Credentials and email verification links are sent to this address and expire in seven days. The mailbox must accept links from external senders. |
    | **Secondary Email** | This email address must be different from the primary email address (distribution lists are accepted). For organizations, the domain must match the email address that is provided in the primary email address. Ensure that the email address can receive emails from external email addresses that have links. |
    | **Business Identifier** | Enter a business identifier for the legal business entity. |
    | **Seller ID** | Applies only to Microsoft Store customers. Find your Seller ID in the Partner Center portal. |
    | **Street, City, Country/Region, State/Province, Postal code** | Enter the business address of the legal business entity. |
    | **First Name** | Enter the first name of the individual representing the organization that will perform individual identity validation. Use the exact name as it appears on your government-issued identification document for the Identity Validation process. |
    | **Last Name** | Enter the last name of the individual representing the organization. This individual performs individual identity validation. Use the exact name as it appears on your government-issued identification document for the Identity Validation process. |
6. Select **Certificate subject preview** to see the preview of the information that appears in the certificate.
7. Select the **Create** button.
8. When the request is successfully created, the identity validation request status changes to **In Progress**.
9. When the status changes to **Action Required**, follow the instructions step 9 onwards in the Identity Validation - Individual Developer tab above.
10. The link for individual identity validation is also sent through email to the primary email address.
11. Once Individual Identity Validation is successfully completed, the status changes back to **In Progress** and the validation process continues.
12. If more documents are required, an email is sent and the request status changes to **Action Required**.
13. When the identity validation process is finished, the request status changes, and an email is sent with the updated status of the request:

    - **Completed** if the process is completed successfully.
    - **Failed** if the process isn't completed successfully.

    [![Screenshot that shows the Public option in the New identity validation pane.](media/artifact-signing-identity-validation-public.png)](media/artifact-signing-identity-validation-public.png#lightbox)

    [![Screenshot that shows the Private option in the New identity validation pane.](media/artifact-signing-identity-validation-private.png)](media/artifact-signing-identity-validation-private.png#lightbox)

### Important information for public identity validation

| Requirements | Details |
| --- | --- |
| Onboarding | For a quicker onboarding process, ensure that public records for the legal business entity that you're validated are up to date. |
| Accuracy | Ensure that you provide the correct information for public identity validation. If you need to make any changes after it's created, you must complete a new identity validation request. This change affects the associated certificates that are being used for signing. |
| Failed email verification | If email verification fails, you must initiate a new identity validation request. |
| Identity validation status | You're notified through email when there's an update to the identity validation status. You can also check the status in the Azure portal at any time. |
| Processing time | Processing your identity validation request takes from 1 to 20 business days (possibly longer if we need to request more documentation from you). |
| More documentation | If we need more documentation to process the identity validation request, you're notified through email. You can upload the documents in the Azure portal. For documentation upload, there are three attempts. The documentation request email contains information about file size requirements. Ensure that any documents you provide are the most current.  - All documents submitted must be issued within the previous 12 months and where the expiration date is a future date that is at least two months away.  - If it isn't possible to provide additional documentation, update your account information to match any legal documents already provided or your official Company registration details.  - When providing official business document, such as business registration form, business charter, or articles of incorporation that list the company name and address as it is provided at the time of Identity Validation request creation.  - Ensure the domain registration or domain invoice from registration or renewal that lists the entity and contact name and all the domains that are included/mentioned in the request. |

# [Identity Validation - Individual Developer](#tab/indiedevvalidation)
To create an Individual identity validation request for an Individual Developer:

1. In the Azure portal, go to your new Artifact Signing account.
2. Confirm that you're assigned the Artifact Signing Identity Verifier role.

    To learn how to manage access by using role-based access control (RBAC), see [Tutorial: Assign roles in Artifact Signing](tutorial-assign-roles).
3. On the Artifact Signing account **Overview** pane or on the resource menu under **Objects**, select **Identity validations**.
4. Select **Organization**, in the dropdown select **Individual** and then select **New Identity**, underneath select **Public**.

    - Public identity validation applies to these certificate profile types: Public Trust, Public Trust Test, VBS Enclave.
    - Private identity validation is only for Organizations.
5. On **New identity validation**, select the billing account associated to the subscription. [![Screenshot that shows the billing account dropdown for indie.](media/artifact-signing-billing-account-individual.png)](media/artifact-signing-billing-account-individual.png#lightbox)
6. Once a billing account is selected, the form is automatically populated with the billing account information. These fields are read-only and cannot be edited within the form. Before proceeding, ensure the populated details meet the required criteria. If updates are needed, modify the information directly in the billing account.

    | Fields | Details |
    | --- | --- |
    | **First Name** | Use the exact name as it appears on your government-issued identification document for the Identity Validation process. |
    | **Last Name** | Use the exact name as it appears on your government-issued identification document for the Identity Validation process. |
    | **Primary Email** | Enter the email address that is going to receive the Identity Validation link. Make sure to use the same email address when logging into the Microsoft Account to access the Identity Validation link. |
    | **Street, City, Country/Region, State/Province, Postal code** | Enter the address as it appears on your government issued identification document or utility bill or bank statement. The city, state/province, and country/region from the address entered here's displayed on the certificate. |
7. **Certificate subject preview** shows the preview of the information that appears on the certificate.

    - Your email address and street address aren't included in the certificate.
8. Select the **Create** button.
9. When the request is successfully created, the identity validation request status changes to **In Progress**.
10. When the status changes to **Action Required**. Select your name, a blade opens on the right-hand side. Select the link under "Please complete your verification here".
11. Follow the link to complete the Identity Validation process. Use the email address provided at the time of the request creation. Enter the credentials when prompted, and you'll be navigated to the next screen.
12. Select **Get verified here through our trusted ID-verifiers**.

    [![Screenshot that shows the first screen for Verified ID.](media/artifact-signing-first-qr-code.png)](media/artifact-signing-first-qr-code.png#lightbox)
13. Create verified credentials by using the trusted partners' pages. The following steps show an example walkthrough. It uses the trusted partner: AU10TIX. You're navigated to a third party website.

    1. Select **Let’s Begin**.

    [![Screenshot that shows the second screen for Verified ID.](media/artifact-signing-second-verified-id.png)](media/artifact-signing-second-verified-id.png#lightbox)
14. Enter your primary email address from the request here.

    [![Screenshot that shows screen to enter email address for Verified ID.](media/artifact-signing-enter-email-id.png)](media/artifact-signing-enter-email-id.png#lightbox)

    AU10TIX sends an email verification in email that includes a PIN code.

    1. Check your email for the verification email and enter the PIN code to verify your email account.

    [![Screenshot that shows screen to enter pincode for Verified ID.](media/artifact-signing-enter-pin-code.png)](media/artifact-signing-enter-pin-code.png#lightbox)
15. Enter phone number when prompted on the next screen.

    [![Screenshot that shows screen to enter phone number for Verified ID.](media/artifact-signing-enter-phone-number.png)](media/artifact-signing-enter-phone-number.png#lightbox)
16. Select **Start**.

    [![Screenshot that shows screen begin Verified ID.](media/artifact-signing-begin-on-laptop.png)](media/artifact-signing-begin-on-laptop.png#lightbox)
17. Use camera of your mobile device to scan the QR code. Don't close this screen on your browser.

    [![Screenshot that shows screen to scan QR code on phone to begin Verified ID.](media/artifact-signing-scan-qr-code-on-phone.png)](media/artifact-signing-scan-qr-code-on-phone.png#lightbox)
18. On your mobile device, select **Start**. Follow the steps to complete the process and present the relevant documentation when prompted.
19. After the Au10TIX process is complete on your mobile device, select **Open Authenticator**.

    [![Screenshot that shows screen to navigate to Authenticator.](media/artifact-signing-open-authenticator.png)](media/artifact-signing-open-authenticator.png#lightbox)
20. Now back on the browser, scan the QR code from your mobile device. Don't close the browser.

    [![Screenshot that shows screen to scan QR code on phone once again to being Verified ID.](media/artifact-signing-scan-qr-code-again.png)](media/artifact-signing-scan-qr-code-again.png#lightbox)
21. Select **Add** to add a verified ID to the Microsoft Authenticator app.

    [![Screenshot that shows screen to Verified ID to their authenticator app.](media/artifact-signing-add-verified-id.png)](media/artifact-signing-add-verified-id.png#lightbox)
22. The browser screen shows Present your Verified ID. Scan the QR code.
23. Select **Verifiable Credential** to share with Artifact Signing.
24. Select **Share** to share the credentials with Artifact Signing.
25. For successful completion the browser screen on your nonmobile device updates to: **Verification Successful** .

    [![Screenshot that shows the indie successful on onevet.](media/artifact-signing-indie-identity-validation-onevet.png)](media/artifact-signing-indie-identity-validation-onevet.png#lightbox)
26. It takes a couple of minutes for the Identity Validation status on Azure portal to update. For a successful Verified ID the status, on Azure portal changes to **Completed**.

    [![Screenshot that shows the indie successful on Azure portal.](media/artifact-signing-identity-validation-indie.png)](media/artifact-signing-identity-validation-indie.png#lightbox)

### Important information for public identity validation for Individual Developers

1. Minimum Requirements for Mobile OSes and supported Browsers:

    [![Screenshot that shows the mobile OSes supported for indie.](media/artifact-signing-au10tix-mobileos-supported.png)](media/artifact-signing-au10tix-mobileos-supported.png#lightbox)

    [![Screenshot that shows the browsers supported for indie.](media/artifact-signing-au10tix-browser-supported.png)](media/artifact-signing-au10tix-browser-supported.png#lightbox)
2. Types of ID Accepted:

    - Government-issued IDs such as passports, driving licenses, or ID cards.
    - Photo IDs (or a US Social Security Card).
    - Official government-issued IDs such as a passport, driver’s license, or state ID.
    - Don't submit privately issued IDs such as library cards, school IDs, club membership cards, etc.
3. Visibility/Low Light/Bright Light:

    - Don't use flash.
    - Don't place the ID in direct sunlight.
    - Hold the camera or mobile device steady while taking the picture.
4. Best Practices for Supplemental Docs:

    - Utility Bills: Electricity, water, gas, or telephone bills (should be recent, typically within the last three months).
    - Bank Statements: Official statements from banks or credit card companies that show the individual’s address.
    - The POA document must have the address, name, and date appear on the main page (first page), so multiple pages aren't required.
5. General best practices:

    - Single picture per file, if two-sided, create one file per side.
    - Handwritten documents aren't accepted.
    - Don't crop the image (cut corners, miss parts) try to have margins on all sides of the captured image before capturing.
    - Don't use Photoshop or other editing software; don't alter the document in any way.
    - Don't use flash.
    - Take the photo from directly above the document while it is on a flat surface.
    - Avoid colored and noisy background.
    - Don't obstruct the ID (no fingers covering part of the document).
    - Use color images not lower than 200 DPI. The ideal image size is 500Kb. AU10TIX best practice is to accept images with 400 DPI and above.
    - The minimum threshold for the image size for an OK result is 600 W X 370 H pixels.
    - Accepted file types: .bmp .jpg .gif .tif .pdf.
    - Users can't upload images smaller than 30kb or larger than 5MB.

---

## Create a certificate profile

A certificate profile resource is the logical container of the certificates that are issued to you for signing.

### Naming constraints for certificate profiles

Certificate profile names have some constraints.

A certificate profile name must:

- Contain from 5 to 100 alphanumeric characters.
- Begin with a letter, end with a letter or number, and not contain consecutive hyphens.
- Be unique within the account.

A certificate profile name is:

- In the same Azure region as the account, by default inheritance.
- Not case-sensitive (*ABC* is the same as *abc*).

# [Azure portal](#tab/certificateprofile-portal)
To create a certificate profile in the Azure portal:

1. In the Azure portal, go to your new Artifact Signing account.
2. On the Artifact Signing account **Overview** pane or on the resource menu under **Objects**, select **Certificate profiles**.
3. On the command bar, select **Create** and select a certificate profile type.

    ![Screenshot that shows the Artifact Signing certificate profile types to choose from.](media/artifact-signing-certificate-profile-types.png)
4. On **Create certificate profile**, provide the following information:

    a. For **Certificate Profile Name**, enter a unique name.

    For more information, see Naming constraints for certificate profiles.

    The value for **Certificate Type** is autopopulated based on the certificate profile type you selected. For **Program Type**, keep the default None. Change it only if you're enrolled in the Windows endpoint security platform or [windows recovery environment](/en-us/windows-hardware/manufacture/desktop/winre-remote-recovery-management-overview?view=windows-11) program.

    b. For **Verified CN and O**, select an identity validation that must be displayed on the certificate.

    - If the street address must be displayed on the certificate, select the **Include street address** checkbox.
    - If the postal code must be displayed on the certificate, select the **Include postal code** checkbox.

        The values for the remaining fields are autopopulated based on your selection for **Verified CN and O**.

        A generated **Certificate Subject Preview** shows the preview of the certificate that will be issued.
5. Select **Create**.

    [![Screenshot that shows the Create certificate profile pane.](media/artifact-signing-certificate-profile-creation.png)](media/artifact-signing-certificate-profile-creation.png#lightbox)

# [Azure CLI](#tab/certificateprofile-cli)
### Prerequisites

You need the identity validation ID for the entity that the certificate profile is being created for. Complete these steps find your identity validation ID in the Azure portal.

1. In the Azure portal, go to your Artifact Signing account.
2. On the Artifact Signing account **Overview** pane or on the resource menu under **Objects**, select **Identity validations**.
3. Select the hyperlink for the relevant entity. On the **Identity validation** pane, you can copy the value for **Identity validation Id**.

    [![Screenshot that shows copying the identity validation ID for an Artifact Signing account.](media/artifact-signing-identity-validation-id.png)](media/artifact-signing-identity-validation-id.png#lightbox)

To create a certificate profile by using the Azure CLI:

1. Create a certificate profile by using the following command:

```azurecli
az artifact-signing certificate-profile create -g MyResourceGroup --a
   account-name MyAccount -n MyProfile --profile-type PublicTrust --identity-validation-id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

For more information, see Naming constraints for certificate profiles.

1. Create a certificate profile that includes optional fields (street address or postal code) in the subject name of the certificate by using the following command:

```azurecli
az artifact-signing certificate-profile create -g MyResourceGroup --account-name MyAccount -n MyProfile --profile-type PublicTrust --identity-validation-id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx --include-street true
```

1. Verify that you successfully created a certificate profile by using the following command:

```azurecli
az artifact-signing certificate-profile show -g myRG --account-name MyAccount -n  MyProfile
```

The following table lists *helpful commands* to use when you create a certificate profile by using the Azure CLI:

| Command | Description |
| --- | --- |
| `az artifact-signing certificate-profile create -–help` | Shows help for sample commands, and shows detailed parameter descriptions. |
| `az artifact-signing certificate-profile list -g MyResourceGroup --account-name MyAccount` | Lists all certificate profiles that are associated with an Artifact Signing account. |
| `az artifact-signing certificate-profile show -g MyResourceGroup --account-name MyAccount -n MyProfile` | Gets the details for a certificate profile. |

# [Azure PowerShell](#tab/certificateprofile-azpowershell)
### Prerequisites

You need the identity validation ID for the entity that the certificate profile is being created for. Complete these steps find your identity validation ID in the Azure portal.

1. In the Azure portal, go to your Artifact Signing account.
2. On the Artifact Signing account **Overview** pane or on the resource menu under **Objects**, select **Identity validations**.
3. Select the hyperlink for the relevant entity. On the **Identity validation** pane, you can copy the value for **Identity validation Id**.

    [![Screenshot that shows copying the identity validation ID for an Artifact Signing account.](media/artifact-signing-identity-validation-id.png)](media/artifact-signing-identity-validation-id.png#lightbox)

To create a certificate profile by using the Azure PowerShell:

1. Create a certificate profile by using the following command:

```powershell
  New-AzArtifactSigningCertificateProfile -AccountName test -ResourceGroupName rg-test -ProfileName test -IdentityValidationId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx -ProfileType PublicTrustTest
```

For more information, see Naming constraints for certificate profiles.

1. Create a certificate profile that includes optional fields (street address or postal code) in the subject name of the certificate by using the following command:

```powershell
  New-AzArtifactSigningCertificateProfile -AccountName test -ResourceGroupName rg-test -ProfileName test -IdentityValidationId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx -ProfileType PublicTrustTest -IncludeStreetAddress
```

1. Verify that you successfully created a certificate profile by using the following command:

```powershell
  Get-AzArtifactSigningCertificateProfile -AccountName test -ResourceGroupName rg-test -ProfileName test
```

---

## Clean up resources

# [Azure portal](#tab/deleteresources-portal)
To delete Artifact Signing resources by using the Azure portal:

### Delete a certificate profile

1. In the Azure portal, go to your Artifact Signing account.
2. On the Artifact Signing account **Overview** pane or on the resource menu under **Objects**, select **Certificate profiles**.
3. On **Certificate profiles**, select the certificate profile that you want to delete.
4. On the command bar, select **Delete**.

Note

This action stops any signing that's associated with the certificate profile.

### Delete an Artifact Signing account

1. Sign in to the [Azure portal](https://portal.azure.com/).
2. In the search box, enter and then select **Artifact Signing Accounts**.
3. On **Artifact Signing Accounts**, select the Artifact Signing account that you want to delete.
4. On the command bar, select **Delete**.
5. Deleting an Artifact Signing account also deletes its associated certificate profiles. Identity validation requests remain available because they're scoped at the subscription level.

Note

This action removes all certificate profiles that are linked to this account. Any signing processes that are associated with the certificate profiles stops.

# [Azure CLI](#tab/adeleteresources-cli)
To delete Artifact Signing resources by using the Azure CLI:

### Delete a certificate profile

To delete an Artifact Signing certificate profile:

```azurecli
az artifact-signing certificate-profile delete -g MyResourceGroup --account-name MyAccount -n MyProfile
```

Note

This action stops any signing that's associated with the certificate profile.

### Delete an Artifact Signing account

You can use the Azure CLI to delete Artifact Signing resources.

To delete an Artifact Signing account:

```azurecli
az artifact-signing delete -n MyAccount -g MyResourceGroup
```

Note

This action removes all certificate profiles that are linked to this account. Any signing processes that are associated with the certificate profiles stops.

# [Azure PowerShell](#tab/adeleteresources-azpowershell)
To delete Artifact Signing resources by using Azure PowerShell:

### Delete a certificate profile

To delete an Artifact Signing certificate profile:

```powershell
  Remove-AzArtifactSigningCertificateProfile -AccountName test -ResourceGroupName test -ProfileName test
```

Note

This action stops any signing that's associated with the certificate profile.

### Delete an Artifact Signing account

To delete an Artifact Signing account:

```powershell
  Remove-AzArtifactSigningAccount -AccountName test -ResourceGroupName rg-test
```

Note

This action removes all certificate profiles that are linked to this account. Any signing processes that are associated with the certificate profiles stops.

---
