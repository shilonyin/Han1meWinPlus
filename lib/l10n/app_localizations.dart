import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Han1meWinPlus'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get simplifiedChinese;

  /// No description provided for @traditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'繁體中文'**
  String get traditionalChinese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @keyframeSettings.
  ///
  /// In en, this message translates to:
  /// **'Key H-Frame Settings'**
  String get keyframeSettings;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @keyframesEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Key H-Frames'**
  String get keyframesEnabled;

  /// No description provided for @keyframesEnabledDescription.
  ///
  /// In en, this message translates to:
  /// **'Show key H-frame entries and countdown in the player'**
  String get keyframesEnabledDescription;

  /// No description provided for @keyframesDisabledDescription.
  ///
  /// In en, this message translates to:
  /// **'Key H-frames are disabled'**
  String get keyframesDisabledDescription;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @noKeyframes.
  ///
  /// In en, this message translates to:
  /// **'No key H-frames yet'**
  String get noKeyframes;

  /// No description provided for @editVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Video Title'**
  String get editVideoTitle;

  /// No description provided for @deleteVideoKeyframes.
  ///
  /// In en, this message translates to:
  /// **'Delete this video\'s key H-frames'**
  String get deleteVideoKeyframes;

  /// No description provided for @deleteVideoKeyframesConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete all key H-frames for \"{title}\"?'**
  String deleteVideoKeyframesConfirmation(Object title);

  /// No description provided for @editPosition.
  ///
  /// In en, this message translates to:
  /// **'Edit Position'**
  String get editPosition;

  /// No description provided for @deleteKeyframe.
  ///
  /// In en, this message translates to:
  /// **'Delete Key H-Frame'**
  String get deleteKeyframe;

  /// No description provided for @deleteKeyframeTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Key H-Frame'**
  String get deleteKeyframeTitle;

  /// No description provided for @videoTitle.
  ///
  /// In en, this message translates to:
  /// **'Video Title'**
  String get videoTitle;

  /// No description provided for @positionMilliseconds.
  ///
  /// In en, this message translates to:
  /// **'Position (ms)'**
  String get positionMilliseconds;

  /// No description provided for @invalidKeyframe.
  ///
  /// In en, this message translates to:
  /// **'Invalid position, or less than 10 seconds from another keyframe'**
  String get invalidKeyframe;

  /// No description provided for @content.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get content;

  /// No description provided for @languageSettings.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettings;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeAndColor.
  ///
  /// In en, this message translates to:
  /// **'Theme & Color'**
  String get themeAndColor;

  /// No description provided for @interfaceLayout.
  ///
  /// In en, this message translates to:
  /// **'Interface Layout'**
  String get interfaceLayout;

  /// No description provided for @wallpaperColors.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper Colors'**
  String get wallpaperColors;

  /// No description provided for @basicColors.
  ///
  /// In en, this message translates to:
  /// **'Basic Colors'**
  String get basicColors;

  /// No description provided for @customAccentColor.
  ///
  /// In en, this message translates to:
  /// **'Custom Accent Color'**
  String get customAccentColor;

  /// No description provided for @invalidColor.
  ///
  /// In en, this message translates to:
  /// **'Enter a six-digit hex color'**
  String get invalidColor;

  /// No description provided for @playback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playback;

  /// No description provided for @playerEngine.
  ///
  /// In en, this message translates to:
  /// **'Player Engine'**
  String get playerEngine;

  /// No description provided for @preferredQuality.
  ///
  /// In en, this message translates to:
  /// **'Preferred Quality'**
  String get preferredQuality;

  /// No description provided for @resumePlayback.
  ///
  /// In en, this message translates to:
  /// **'Resume Playback'**
  String get resumePlayback;

  /// No description provided for @resumePlaybackDescription.
  ///
  /// In en, this message translates to:
  /// **'Continue from the last position on next playback'**
  String get resumePlaybackDescription;

  /// No description provided for @autoPlayOnOpen.
  ///
  /// In en, this message translates to:
  /// **'Play Immediately'**
  String get autoPlayOnOpen;

  /// No description provided for @autoPlayOnOpenDescription.
  ///
  /// In en, this message translates to:
  /// **'Start playback automatically when a video page opens'**
  String get autoPlayOnOpenDescription;

  /// No description provided for @site.
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get site;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @networkSettings.
  ///
  /// In en, this message translates to:
  /// **'Network Settings'**
  String get networkSettings;

  /// No description provided for @useBuiltInHosts.
  ///
  /// In en, this message translates to:
  /// **'Use Built-in Hosts'**
  String get useBuiltInHosts;

  /// No description provided for @useBuiltInHostsDescription.
  ///
  /// In en, this message translates to:
  /// **'Use built-in Cloudflare addresses for Hanime1 domains, falling back to system DNS automatically'**
  String get useBuiltInHostsDescription;

  /// No description provided for @addressLatency.
  ///
  /// In en, this message translates to:
  /// **'Address Latency'**
  String get addressLatency;

  /// No description provided for @addressLatencyDescription.
  ///
  /// In en, this message translates to:
  /// **'Probes the built-in candidate addresses concurrently and prefers the fastest one; only applies when no proxy is used'**
  String get addressLatencyDescription;

  /// No description provided for @addressLatencyProxyNotice.
  ///
  /// In en, this message translates to:
  /// **'Requests currently go through a proxy, so the built-in addresses are not used; the figures below are direct-connection probes and for reference only'**
  String get addressLatencyProxyNotice;

  /// No description provided for @addressLatencyProbe.
  ///
  /// In en, this message translates to:
  /// **'Test again'**
  String get addressLatencyProbe;

  /// No description provided for @addressLatencyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get addressLatencyUnavailable;

  /// No description provided for @addressLatencyNotProbed.
  ///
  /// In en, this message translates to:
  /// **'Not probed'**
  String get addressLatencyNotProbed;

  /// No description provided for @addressLatencyLastProbed.
  ///
  /// In en, this message translates to:
  /// **'Last probed: {time}'**
  String addressLatencyLastProbed(Object time);

  /// No description provided for @addressLatencyDone.
  ///
  /// In en, this message translates to:
  /// **'Speed test finished'**
  String get addressLatencyDone;

  /// No description provided for @addressGroupSite.
  ///
  /// In en, this message translates to:
  /// **'Hanime1 site'**
  String get addressGroupSite;

  /// No description provided for @addressGroupImageCdn.
  ///
  /// In en, this message translates to:
  /// **'Image CDN'**
  String get addressGroupImageCdn;

  /// No description provided for @addressGroupGetchu.
  ///
  /// In en, this message translates to:
  /// **'Getchu previews'**
  String get addressGroupGetchu;

  /// No description provided for @siteDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Site Diagnostics'**
  String get siteDiagnostics;

  /// No description provided for @siteDiagnosticsDescription.
  ///
  /// In en, this message translates to:
  /// **'Checks DNS, connectivity, certificate, page structure and login state of the current site to help locate common problems'**
  String get siteDiagnosticsDescription;

  /// No description provided for @siteGroups.
  ///
  /// In en, this message translates to:
  /// **'Site Groups'**
  String get siteGroups;

  /// No description provided for @siteGroupsDescription.
  ///
  /// In en, this message translates to:
  /// **'Group the site list: rename groups, reorder them and move sites between groups; sites are categorised by type until you customise them'**
  String get siteGroupsDescription;

  /// No description provided for @siteGroupAdd.
  ///
  /// In en, this message translates to:
  /// **'Add group'**
  String get siteGroupAdd;

  /// No description provided for @siteGroupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get siteGroupName;

  /// No description provided for @siteGroupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the default name'**
  String get siteGroupNameHint;

  /// No description provided for @siteGroupRename.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get siteGroupRename;

  /// No description provided for @siteGroupMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to'**
  String get siteGroupMoveTo;

  /// No description provided for @siteGroupEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sites in this group yet'**
  String get siteGroupEmpty;

  /// No description provided for @siteGroupDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be deleted and its sites merged into the first group'**
  String siteGroupDeleteHint(Object name);

  /// No description provided for @siteHostsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sites'**
  String siteHostsCount(int count);

  /// No description provided for @diagnose.
  ///
  /// In en, this message translates to:
  /// **'Run diagnostics'**
  String get diagnose;

  /// No description provided for @diagnosticDns.
  ///
  /// In en, this message translates to:
  /// **'DNS Lookup'**
  String get diagnosticDns;

  /// No description provided for @diagnosticConnectivity.
  ///
  /// In en, this message translates to:
  /// **'Connectivity'**
  String get diagnosticConnectivity;

  /// No description provided for @diagnosticCertificate.
  ///
  /// In en, this message translates to:
  /// **'SSL Certificate'**
  String get diagnosticCertificate;

  /// No description provided for @diagnosticSite.
  ///
  /// In en, this message translates to:
  /// **'Site Status'**
  String get diagnosticSite;

  /// No description provided for @diagnosticLogin.
  ///
  /// In en, this message translates to:
  /// **'Login Status'**
  String get diagnosticLogin;

  /// No description provided for @diagnosticOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get diagnosticOk;

  /// No description provided for @diagnosticFail.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get diagnosticFail;

  /// No description provided for @diagnosticSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get diagnosticSkipped;

  /// No description provided for @diagnosticDnsOk.
  ///
  /// In en, this message translates to:
  /// **'Resolved {host}: {addresses}'**
  String diagnosticDnsOk(Object host, Object addresses);

  /// No description provided for @diagnosticDnsFail.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve {host}'**
  String diagnosticDnsFail(Object host);

  /// No description provided for @diagnosticHttpOk.
  ///
  /// In en, this message translates to:
  /// **'HTTP {code}, the site is reachable'**
  String diagnosticHttpOk(int code);

  /// No description provided for @diagnosticHttpFail.
  ///
  /// In en, this message translates to:
  /// **'HTTP {code}, access denied'**
  String diagnosticHttpFail(int code);

  /// No description provided for @diagnosticError.
  ///
  /// In en, this message translates to:
  /// **'Check failed: {detail}'**
  String diagnosticError(Object detail);

  /// No description provided for @diagnosticCertificateOk.
  ///
  /// In en, this message translates to:
  /// **'Certificate valid, issued by {issuer}'**
  String diagnosticCertificateOk(Object issuer);

  /// No description provided for @diagnosticCertificateNone.
  ///
  /// In en, this message translates to:
  /// **'No certificate information available'**
  String get diagnosticCertificateNone;

  /// No description provided for @diagnosticSiteOk.
  ///
  /// In en, this message translates to:
  /// **'Page structure looks correct: {url}'**
  String diagnosticSiteOk(Object url);

  /// No description provided for @diagnosticSiteFail.
  ///
  /// In en, this message translates to:
  /// **'HTTP {code}, the site is unavailable'**
  String diagnosticSiteFail(int code);

  /// No description provided for @diagnosticSiteStructure.
  ///
  /// In en, this message translates to:
  /// **'Unexpected page structure; the mirror may be dead or the site was redesigned'**
  String get diagnosticSiteStructure;

  /// No description provided for @diagnosticLoginSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved account: {name}'**
  String diagnosticLoginSaved(Object name);

  /// No description provided for @diagnosticLoginSkipped.
  ///
  /// In en, this message translates to:
  /// **'Not signed in, skipping the login check'**
  String get diagnosticLoginSkipped;

  /// No description provided for @suggestionLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get suggestionLabel;

  /// No description provided for @suggestionCloudflare.
  ///
  /// In en, this message translates to:
  /// **'The server rejected the request; this is usually a Cloudflare challenge or a region restriction — try another network or mirror address'**
  String get suggestionCloudflare;

  /// No description provided for @suggestionDns.
  ///
  /// In en, this message translates to:
  /// **'System DNS may be poisoned; enable \"Use Built-in Hosts\" or switch to DNS over HTTPS'**
  String get suggestionDns;

  /// No description provided for @suggestionTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server is too slow or unreachable; check your network and retry'**
  String get suggestionTimeout;

  /// No description provided for @suggestionSite.
  ///
  /// In en, this message translates to:
  /// **'The site responded abnormally; try another mirror address'**
  String get suggestionSite;

  /// No description provided for @addressLatencyPreferred.
  ///
  /// In en, this message translates to:
  /// **'Preferred: {address} ({ms} ms)'**
  String addressLatencyPreferred(Object address, int ms);

  /// No description provided for @proxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get proxy;

  /// No description provided for @proxyDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow the system proxy, connect directly, or use a custom address; built-in hosts and DoH only apply when not using a proxy'**
  String get proxyDescription;

  /// No description provided for @proxySystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get proxySystem;

  /// No description provided for @proxyDirect.
  ///
  /// In en, this message translates to:
  /// **'No proxy (direct)'**
  String get proxyDirect;

  /// No description provided for @proxyCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom proxy'**
  String get proxyCustom;

  /// No description provided for @proxyCustomAddress.
  ///
  /// In en, this message translates to:
  /// **'Proxy address'**
  String get proxyCustomAddress;

  /// No description provided for @proxyCustomAddressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 127.0.0.1:7897 (http:// optional)'**
  String get proxyCustomAddressHint;

  /// No description provided for @proxyDirectOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'A proxy is in use, so built-in hosts have no effect'**
  String get proxyDirectOnlyHint;

  /// No description provided for @doh.
  ///
  /// In en, this message translates to:
  /// **'DNS over HTTPS'**
  String get doh;

  /// No description provided for @useDoh.
  ///
  /// In en, this message translates to:
  /// **'Use DNS over HTTPS'**
  String get useDoh;

  /// No description provided for @dohSettings.
  ///
  /// In en, this message translates to:
  /// **'DNS over HTTPS Settings'**
  String get dohSettings;

  /// No description provided for @dohDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get dohDisabled;

  /// No description provided for @dohPreset.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get dohPreset;

  /// No description provided for @dohCustomUrl.
  ///
  /// In en, this message translates to:
  /// **'Custom DoH URL'**
  String get dohCustomUrl;

  /// No description provided for @dohBootstrapIps.
  ///
  /// In en, this message translates to:
  /// **'Bootstrap IP Addresses'**
  String get dohBootstrapIps;

  /// No description provided for @dohBootstrapIpsDescription.
  ///
  /// In en, this message translates to:
  /// **'Separated by comma, space, or newline'**
  String get dohBootstrapIpsDescription;

  /// No description provided for @dohTimeoutSeconds.
  ///
  /// In en, this message translates to:
  /// **'Timeout (seconds)'**
  String get dohTimeoutSeconds;

  /// No description provided for @dohTimeoutSecondsDescription.
  ///
  /// In en, this message translates to:
  /// **'Range from 1 to 60 seconds'**
  String get dohTimeoutSecondsDescription;

  /// No description provided for @customMirrorSite.
  ///
  /// In en, this message translates to:
  /// **'Custom Mirror Site'**
  String get customMirrorSite;

  /// No description provided for @customMirrorSiteHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a mirror site with the same structure as the main site that opens its homepage directly, e.g. https://www.example.com/enter; the homepage is requested exactly as entered. AV source addresses (e.g. xHamster) also work here and are recognized by domain'**
  String get customMirrorSiteHint;

  /// No description provided for @enableCustomMirrorSite.
  ///
  /// In en, this message translates to:
  /// **'Enable custom mirror site'**
  String get enableCustomMirrorSite;

  /// No description provided for @customMirrorSiteInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid HTTPS URL that opens the homepage directly, e.g. https://www.example.com/enter'**
  String get customMirrorSiteInvalid;

  /// No description provided for @customMirrorApiPathMode.
  ///
  /// In en, this message translates to:
  /// **'Other API Path'**
  String get customMirrorApiPathMode;

  /// No description provided for @customMirrorPathFollowHome.
  ///
  /// In en, this message translates to:
  /// **'Follow Home Directory'**
  String get customMirrorPathFollowHome;

  /// No description provided for @customMirrorPathFollowHomeSummary.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://www.example.com/enter/search'**
  String get customMirrorPathFollowHomeSummary;

  /// No description provided for @customMirrorPathRoot.
  ///
  /// In en, this message translates to:
  /// **'Use Root Domain'**
  String get customMirrorPathRoot;

  /// No description provided for @customMirrorPathRootSummary.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://www.example.com/search. The homepage always uses the URL entered above'**
  String get customMirrorPathRootSummary;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @customMirrorTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Test succeeded\nHomepage: {homeUrl}\nOther API base: {apiBase}'**
  String customMirrorTestSuccess(Object homeUrl, Object apiBase);

  /// No description provided for @customMirrorTestJavSuccess.
  ///
  /// In en, this message translates to:
  /// **'Test succeeded: recognized as {source}\nRequest base: {base}\nParsed {count} items'**
  String customMirrorTestJavSuccess(Object source, Object base, int count);

  /// No description provided for @customMirrorTestPartialSuccess.
  ///
  /// In en, this message translates to:
  /// **'Homepage test succeeded, but other API test failed\nOther API base: {apiBase}\nReason: HTTP {statusCode}'**
  String customMirrorTestPartialSuccess(Object apiBase, int statusCode);

  /// No description provided for @customMirrorTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Test failed: {error}'**
  String customMirrorTestFailed(Object error);

  /// No description provided for @customMirrorTestFailedHttp.
  ///
  /// In en, this message translates to:
  /// **'Test failed: HTTP {statusCode}\nHomepage: {url}'**
  String customMirrorTestFailedHttp(int statusCode, Object url);

  /// No description provided for @customMirrorTestParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Connected, but failed to parse the homepage structure'**
  String get customMirrorTestParseFailed;

  /// No description provided for @customMirrorTestChallenge.
  ///
  /// In en, this message translates to:
  /// **'The site is protected by Cloudflare and may not be usable'**
  String get customMirrorTestChallenge;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @cloudflareVerification.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare Verification'**
  String get cloudflareVerification;

  /// No description provided for @cloudflareVerificationDescription.
  ///
  /// In en, this message translates to:
  /// **'Complete verification when visiting protected pages'**
  String get cloudflareVerificationDescription;

  /// No description provided for @autoCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Auto-check for updates'**
  String get autoCheckUpdates;

  /// No description provided for @useUpdateMirror.
  ///
  /// In en, this message translates to:
  /// **'Automatically use update mirrors'**
  String get useUpdateMirror;

  /// No description provided for @useUpdateMirrorDescription.
  ///
  /// In en, this message translates to:
  /// **'Try update mirrors in order when the original GitHub download fails'**
  String get useUpdateMirrorDescription;

  /// No description provided for @checkUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get checkUpdates;

  /// No description provided for @application.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get application;

  /// No description provided for @applicationSettings.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get applicationSettings;

  /// No description provided for @applicationSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Modify app-related settings'**
  String get applicationSettingsDescription;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @keyframeManagement.
  ///
  /// In en, this message translates to:
  /// **'Key H-Frame Management'**
  String get keyframeManagement;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Version and open-source info'**
  String get aboutDescription;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @cache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get cache;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get clearCache;

  /// No description provided for @clearCacheDescription.
  ///
  /// In en, this message translates to:
  /// **'Clears cached cover images and list metadata. Downloads and watch history are kept.'**
  String get clearCacheDescription;

  /// No description provided for @cacheUsage.
  ///
  /// In en, this message translates to:
  /// **'Currently using {size}'**
  String cacheUsage(String size);

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared {size}'**
  String cacheCleared(String size);

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get more;

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previousPage;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get nextPage;

  /// No description provided for @featured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get featured;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @videoSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No playable video source'**
  String get videoSourceUnavailable;

  /// No description provided for @videoPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load video'**
  String get videoPlaybackFailed;

  /// No description provided for @completeCloudflareVerification.
  ///
  /// In en, this message translates to:
  /// **'Complete Cloudflare Verification'**
  String get completeCloudflareVerification;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search videos, authors, tags…'**
  String get searchHint;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No matching videos found'**
  String get noSearchResults;

  /// No description provided for @javSourceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'This AV source supports keyword search only — please type a keyword'**
  String get javSourceSearchHint;

  /// No description provided for @recommendedVideos.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommendedVideos;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category: {value}'**
  String category(Object value);

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort: {value}'**
  String sort(Object value);

  /// No description provided for @releaseDate.
  ///
  /// In en, this message translates to:
  /// **'Release date: {value}'**
  String releaseDate(Object value);

  /// No description provided for @releaseDateTitle.
  ///
  /// In en, this message translates to:
  /// **'Release Date'**
  String get releaseDateTitle;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration: {value}'**
  String duration(Object value);

  /// No description provided for @searchAuthors.
  ///
  /// In en, this message translates to:
  /// **'Search Authors'**
  String get searchAuthors;

  /// No description provided for @tagsSelected.
  ///
  /// In en, this message translates to:
  /// **'Tags: {count} selected'**
  String tagsSelected(int count);

  /// No description provided for @broadMatch.
  ///
  /// In en, this message translates to:
  /// **'Broad Match'**
  String get broadMatch;

  /// No description provided for @broadMatchDescription.
  ///
  /// In en, this message translates to:
  /// **'Matches any of the selected tags; more results but lower precision.'**
  String get broadMatchDescription;

  /// No description provided for @tagVideoAttributes.
  ///
  /// In en, this message translates to:
  /// **'Video Attributes'**
  String get tagVideoAttributes;

  /// No description provided for @tagRelationships.
  ///
  /// In en, this message translates to:
  /// **'Relationships'**
  String get tagRelationships;

  /// No description provided for @tagCharacterSettings.
  ///
  /// In en, this message translates to:
  /// **'Character Settings'**
  String get tagCharacterSettings;

  /// No description provided for @tagAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get tagAppearance;

  /// No description provided for @tagSettings.
  ///
  /// In en, this message translates to:
  /// **'Scenes & Places'**
  String get tagSettings;

  /// No description provided for @tagStory.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get tagStory;

  /// No description provided for @tagPositions.
  ///
  /// In en, this message translates to:
  /// **'Positions'**
  String get tagPositions;

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'Date Range'**
  String get dateRange;

  /// No description provided for @specificYearMonth.
  ///
  /// In en, this message translates to:
  /// **'Specific Year & Month'**
  String get specificYearMonth;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @allYears.
  ///
  /// In en, this message translates to:
  /// **'All Years'**
  String get allYears;

  /// No description provided for @allMonths.
  ///
  /// In en, this message translates to:
  /// **'All Months'**
  String get allMonths;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @defaultValue.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultValue;

  /// No description provided for @comments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get comments;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @noComments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get noComments;

  /// No description provided for @previews.
  ///
  /// In en, this message translates to:
  /// **'Season Previews'**
  String get previews;

  /// No description provided for @previewSource.
  ///
  /// In en, this message translates to:
  /// **'Previews source'**
  String get previewSource;

  /// No description provided for @previewSourceAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get previewSourceAuto;

  /// No description provided for @previewSourceDefault.
  ///
  /// In en, this message translates to:
  /// **'Default site'**
  String get previewSourceDefault;

  /// No description provided for @previewSourceGetchu.
  ///
  /// In en, this message translates to:
  /// **'Getchu'**
  String get previewSourceGetchu;

  /// No description provided for @previewSourceAutoDescription.
  ///
  /// In en, this message translates to:
  /// **'Fall back to Getchu when the default site has no previews'**
  String get previewSourceAutoDescription;

  /// No description provided for @previewSourceDefaultDescription.
  ///
  /// In en, this message translates to:
  /// **'Only use the default site previews'**
  String get previewSourceDefaultDescription;

  /// No description provided for @previewSourceGetchuDescription.
  ///
  /// In en, this message translates to:
  /// **'Only use the Getchu previews'**
  String get previewSourceGetchuDescription;

  /// No description provided for @previewSourceSwitched.
  ///
  /// In en, this message translates to:
  /// **'Default site previews are unavailable, switched to Getchu'**
  String get previewSourceSwitched;

  /// No description provided for @getchuPreviews.
  ///
  /// In en, this message translates to:
  /// **'Getchu Season Previews'**
  String get getchuPreviews;

  /// No description provided for @getchuPreviewMonth.
  ///
  /// In en, this message translates to:
  /// **'Getchu {month} Release Schedule'**
  String getchuPreviewMonth(Object month);

  /// No description provided for @getchuPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Getchu season previews are unavailable'**
  String get getchuPreviewUnavailable;

  /// No description provided for @noGetchuPreviews.
  ///
  /// In en, this message translates to:
  /// **'No Getchu season previews this month'**
  String get noGetchuPreviews;

  /// No description provided for @getchuPreviewDetail.
  ///
  /// In en, this message translates to:
  /// **'Getchu Preview Details'**
  String get getchuPreviewDetail;

  /// No description provided for @openGetchu.
  ///
  /// In en, this message translates to:
  /// **'Open Getchu'**
  String get openGetchu;

  /// No description provided for @playTrailer.
  ///
  /// In en, this message translates to:
  /// **'Play trailer'**
  String get playTrailer;

  /// No description provided for @trailerNumber.
  ///
  /// In en, this message translates to:
  /// **'Trailer {number}'**
  String trailerNumber(int number);

  /// No description provided for @productIntroduction.
  ///
  /// In en, this message translates to:
  /// **'Product Introduction'**
  String get productIntroduction;

  /// No description provided for @story.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get story;

  /// No description provided for @staff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staff;

  /// No description provided for @getchuSeries.
  ///
  /// In en, this message translates to:
  /// **'Series Products'**
  String get getchuSeries;

  /// No description provided for @previewMonth.
  ///
  /// In en, this message translates to:
  /// **'{month} Release Schedule'**
  String previewMonth(Object month);

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous Month'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next Month'**
  String get nextMonth;

  /// No description provided for @previewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Season previews unavailable this month'**
  String get previewUnavailable;

  /// No description provided for @previewUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'You can reload, or view previews from earlier months.'**
  String get previewUnavailableDescription;

  /// No description provided for @noPreviews.
  ///
  /// In en, this message translates to:
  /// **'No season previews this month'**
  String get noPreviews;

  /// No description provided for @noPreviewsDescription.
  ///
  /// In en, this message translates to:
  /// **'Previews will appear here once released. You can also browse earlier months.'**
  String get noPreviewsDescription;

  /// No description provided for @watchVideo.
  ///
  /// In en, this message translates to:
  /// **'Watch Video'**
  String get watchVideo;

  /// No description provided for @previewImages.
  ///
  /// In en, this message translates to:
  /// **'Preview Images ({count})'**
  String previewImages(int count);

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @watchDuration.
  ///
  /// In en, this message translates to:
  /// **'Watch time  {duration}'**
  String watchDuration(Object duration);

  /// No description provided for @noWatchHistory.
  ///
  /// In en, this message translates to:
  /// **'No watch history'**
  String get noWatchHistory;

  /// No description provided for @hoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String hoursMinutes(Object hours, Object minutes);

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{value} min'**
  String minutes(Object value);

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'{value} sec'**
  String seconds(Object value);

  /// No description provided for @myLibrary.
  ///
  /// In en, this message translates to:
  /// **'My Library'**
  String get myLibrary;

  /// No description provided for @watchLater.
  ///
  /// In en, this message translates to:
  /// **'Watch Later'**
  String get watchLater;

  /// No description provided for @favoriteVideos.
  ///
  /// In en, this message translates to:
  /// **'Favorite Videos'**
  String get favoriteVideos;

  /// No description provided for @subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptions;

  /// No description provided for @noWatchLater.
  ///
  /// In en, this message translates to:
  /// **'No watch-later videos'**
  String get noWatchLater;

  /// No description provided for @noFavoriteVideos.
  ///
  /// In en, this message translates to:
  /// **'No favorite videos'**
  String get noFavoriteVideos;

  /// No description provided for @noSubscriptionVideos.
  ///
  /// In en, this message translates to:
  /// **'No subscription videos'**
  String get noSubscriptionVideos;

  /// No description provided for @selectedItems.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedItems(int count);

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @deleteSelectedCache.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected Cache'**
  String get deleteSelectedCache;

  /// No description provided for @deleteSelectedCacheConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} selected caches? The local files will be deleted too.'**
  String deleteSelectedCacheConfirmation(int count);

  /// No description provided for @cacheSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} videos · {size}'**
  String cacheSummary(int count, String size);

  /// No description provided for @groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// No description provided for @groupSettings.
  ///
  /// In en, this message translates to:
  /// **'Group settings'**
  String get groupSettings;

  /// No description provided for @emptyCacheHint.
  ///
  /// In en, this message translates to:
  /// **'Downloaded videos will appear here'**
  String get emptyCacheHint;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get createGroup;

  /// No description provided for @noCache.
  ///
  /// In en, this message translates to:
  /// **'No cache'**
  String get noCache;

  /// No description provided for @cachedVideos.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get cachedVideos;

  /// No description provided for @activeDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get activeDownloads;

  /// No description provided for @cacheEmptyActive.
  ///
  /// In en, this message translates to:
  /// **'Nothing is downloading'**
  String get cacheEmptyActive;

  /// No description provided for @folderContents.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String folderContents(int count);

  /// No description provided for @mainEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Main'**
  String get mainEpisodes;

  /// No description provided for @folderSize.
  ///
  /// In en, this message translates to:
  /// **'Total {size}'**
  String folderSize(Object size);

  /// No description provided for @taskSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get taskSort;

  /// No description provided for @sortByDefault.
  ///
  /// In en, this message translates to:
  /// **'Default order'**
  String get sortByDefault;

  /// No description provided for @sortByRecent.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get sortByRecent;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'By name'**
  String get sortByName;

  /// No description provided for @sortBySize.
  ///
  /// In en, this message translates to:
  /// **'By size'**
  String get sortBySize;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreActions;

  /// No description provided for @noGrouping.
  ///
  /// In en, this message translates to:
  /// **'No group'**
  String get noGrouping;

  /// No description provided for @startAll.
  ///
  /// In en, this message translates to:
  /// **'Start all'**
  String get startAll;

  /// No description provided for @pauseAll.
  ///
  /// In en, this message translates to:
  /// **'Pause all'**
  String get pauseAll;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @switchToGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get switchToGrid;

  /// No description provided for @switchToList.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get switchToList;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openFolder;

  /// No description provided for @backToCache.
  ///
  /// In en, this message translates to:
  /// **'All downloads'**
  String get backToCache;

  /// No description provided for @selectQuality.
  ///
  /// In en, this message translates to:
  /// **'Current quality'**
  String get selectQuality;

  /// No description provided for @myDownloads.
  ///
  /// In en, this message translates to:
  /// **'My downloads'**
  String get myDownloads;

  /// No description provided for @downloadCountButton.
  ///
  /// In en, this message translates to:
  /// **'Download ({count})'**
  String downloadCountButton(int count);

  /// No description provided for @localVideoMissing.
  ///
  /// In en, this message translates to:
  /// **'Local video file not found. Delete this cache and re-download.'**
  String get localVideoMissing;

  /// No description provided for @deleteCache.
  ///
  /// In en, this message translates to:
  /// **'Delete Cache'**
  String get deleteCache;

  /// No description provided for @deleteCacheConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete the local cache for \"{title}\"?'**
  String deleteCacheConfirmation(Object title);

  /// No description provided for @deleteGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"'**
  String deleteGroupTitle(Object name);

  /// No description provided for @moveGroupCacheToDefault.
  ///
  /// In en, this message translates to:
  /// **'Caches in this group will move to the default group.'**
  String get moveGroupCacheToDefault;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get groupName;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @confirmExitTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit app?'**
  String get confirmExitTitle;

  /// No description provided for @queued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get queued;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloading;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @downloadSpeed.
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String downloadSpeed(Object speed);

  /// No description provided for @downloadProgressFull.
  ///
  /// In en, this message translates to:
  /// **'{speed} · {downloaded} / {total}'**
  String downloadProgressFull(Object speed, Object downloaded, Object total);

  /// No description provided for @downloadProgressPartial.
  ///
  /// In en, this message translates to:
  /// **'{speed} · {downloaded}'**
  String downloadProgressPartial(Object speed, Object downloaded);

  /// No description provided for @commentsTitle.
  ///
  /// In en, this message translates to:
  /// **'{title} Comments'**
  String commentsTitle(Object title);

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}/{year}'**
  String date(int year, int month, int day);

  /// No description provided for @thirdPartyClient.
  ///
  /// In en, this message translates to:
  /// **'Third-party Hanime1 client'**
  String get thirdPartyClient;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @dataSource.
  ///
  /// In en, this message translates to:
  /// **'Data Source'**
  String get dataSource;

  /// No description provided for @dataSourceDescription.
  ///
  /// In en, this message translates to:
  /// **'Public page content from the Hanime1 website'**
  String get dataSourceDescription;

  /// No description provided for @githubRepository.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get githubRepository;

  /// No description provided for @reportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report an Issue'**
  String get reportIssue;

  /// No description provided for @submitGitHubIssue.
  ///
  /// In en, this message translates to:
  /// **'Submit a GitHub Issue'**
  String get submitGitHubIssue;

  /// No description provided for @openSourceLicense.
  ///
  /// In en, this message translates to:
  /// **'Open Source License'**
  String get openSourceLicense;

  /// No description provided for @verificationComplete.
  ///
  /// In en, this message translates to:
  /// **'Verification Complete'**
  String get verificationComplete;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @exitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit Fullscreen'**
  String get exitFullscreen;

  /// No description provided for @fullscreenPlayback.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen Playback'**
  String get fullscreenPlayback;

  /// No description provided for @pauseBeforeAddingKeyframe.
  ///
  /// In en, this message translates to:
  /// **'Pause the video before adding a key H-frame'**
  String get pauseBeforeAddingKeyframe;

  /// No description provided for @addKeyframe.
  ///
  /// In en, this message translates to:
  /// **'Add Key H-Frame'**
  String get addKeyframe;

  /// No description provided for @addKeyframeConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Add the current paused position as a key H-frame?\n\nCurrent time: {position} ms\nAdjacent keyframes must be at least 10 seconds apart.'**
  String addKeyframeConfirmation(int position);

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @keyframeAdded.
  ///
  /// In en, this message translates to:
  /// **'Key H-frame added'**
  String get keyframeAdded;

  /// No description provided for @keyframeTooClose.
  ///
  /// In en, this message translates to:
  /// **'Less than 10 seconds from an existing keyframe'**
  String get keyframeTooClose;

  /// No description provided for @longPressAddKeyframe.
  ///
  /// In en, this message translates to:
  /// **'Long press to add a key H-frame'**
  String get longPressAddKeyframe;

  /// No description provided for @keyframes.
  ///
  /// In en, this message translates to:
  /// **'Key H-Frames'**
  String get keyframes;

  /// No description provided for @deleteCurrentVideoKeyframes.
  ///
  /// In en, this message translates to:
  /// **'Delete all key H-frames for the current video'**
  String get deleteCurrentVideoKeyframes;

  /// No description provided for @deleteCurrentVideoKeyframesConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete all key H-frames for the current video?'**
  String get deleteCurrentVideoKeyframesConfirmation;

  /// No description provided for @editKeyframe.
  ///
  /// In en, this message translates to:
  /// **'Edit Key H-Frame'**
  String get editKeyframe;

  /// No description provided for @keyframeCountdown.
  ///
  /// In en, this message translates to:
  /// **'Key H-frame in {seconds} seconds'**
  String keyframeCountdown(Object seconds);

  /// No description provided for @episodeList.
  ///
  /// In en, this message translates to:
  /// **'Episode List'**
  String get episodeList;

  /// No description provided for @seriesVideos.
  ///
  /// In en, this message translates to:
  /// **'Series Videos'**
  String get seriesVideos;

  /// No description provided for @relatedVideos.
  ///
  /// In en, this message translates to:
  /// **'Related Videos'**
  String get relatedVideos;

  /// No description provided for @studio.
  ///
  /// In en, this message translates to:
  /// **'Studio'**
  String get studio;

  /// No description provided for @subscribed.
  ///
  /// In en, this message translates to:
  /// **'Subscribed'**
  String get subscribed;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @selectDownloadQuality.
  ///
  /// In en, this message translates to:
  /// **'Select Download Quality'**
  String get selectDownloadQuality;

  /// No description provided for @startDownload.
  ///
  /// In en, this message translates to:
  /// **'Start Download'**
  String get startDownload;

  /// No description provided for @downloadQualitySection.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get downloadQualitySection;

  /// No description provided for @downloadEpisodesSection.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get downloadEpisodesSection;

  /// No description provided for @downloadGroupSection.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get downloadGroupSection;

  /// No description provided for @downloadEpisodeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} episodes'**
  String downloadEpisodeCount(int count);

  /// No description provided for @downloadSelectAllEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get downloadSelectAllEpisodes;

  /// No description provided for @downloadClearEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get downloadClearEpisodes;

  /// No description provided for @downloadCurrentOnly.
  ///
  /// In en, this message translates to:
  /// **'Current episode only'**
  String get downloadCurrentOnly;

  /// No description provided for @downloadPartialFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} episodes could not be prepared'**
  String downloadPartialFailed(int count);

  /// No description provided for @downloadNothingSelected.
  ///
  /// In en, this message translates to:
  /// **'Select at least one episode'**
  String get downloadNothingSelected;

  /// No description provided for @addedToDownloadQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to download queue'**
  String get addedToDownloadQueue;

  /// No description provided for @collapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// No description provided for @collapseSidebar.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get collapseSidebar;

  /// No description provided for @expandSidebar.
  ///
  /// In en, this message translates to:
  /// **'Expand sidebar'**
  String get expandSidebar;

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @commentsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load comments'**
  String get commentsLoadFailed;

  /// No description provided for @keyframeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} keyframes'**
  String keyframeCount(int count);

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get followSystem;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get themeColor;

  /// No description provided for @rose.
  ///
  /// In en, this message translates to:
  /// **'Rose'**
  String get rose;

  /// No description provided for @blue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get blue;

  /// No description provided for @teal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get teal;

  /// No description provided for @amber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get amber;

  /// No description provided for @forestGreen.
  ///
  /// In en, this message translates to:
  /// **'Forest Green'**
  String get forestGreen;

  /// No description provided for @orange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get orange;

  /// No description provided for @indigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get indigo;

  /// No description provided for @pink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get pink;

  /// No description provided for @purple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get purple;

  /// No description provided for @keyframeSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage the toggle and per-video key H-frames'**
  String get keyframeSettingsDescription;

  /// No description provided for @latestVersion.
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date'**
  String get latestVersion;

  /// No description provided for @newVersionAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version {version} available'**
  String newVersionAvailable(Object version);

  /// No description provided for @newVersionReleased.
  ///
  /// In en, this message translates to:
  /// **'A new version has been released.'**
  String get newVersionReleased;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get updateNow;

  /// No description provided for @noInstallableApk.
  ///
  /// In en, this message translates to:
  /// **'No installable APK for this version'**
  String get noInstallableApk;

  /// No description provided for @updateIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Update Incomplete'**
  String get updateIncomplete;

  /// No description provided for @downloadingUpdate.
  ///
  /// In en, this message translates to:
  /// **'Downloading Update'**
  String get downloadingUpdate;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String updateFailed(Object error);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @monetColors.
  ///
  /// In en, this message translates to:
  /// **'Monet Colors'**
  String get monetColors;

  /// No description provided for @monetColorsDescription.
  ///
  /// In en, this message translates to:
  /// **'Use dynamic system wallpaper colors'**
  String get monetColorsDescription;

  /// No description provided for @downloadSettings.
  ///
  /// In en, this message translates to:
  /// **'Download Settings'**
  String get downloadSettings;

  /// No description provided for @downloadSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Speed and concurrent download limits'**
  String get downloadSettingsDescription;

  /// No description provided for @downloadSpeedLimit.
  ///
  /// In en, this message translates to:
  /// **'Download Speed Limit'**
  String get downloadSpeedLimit;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @concurrentDownloads.
  ///
  /// In en, this message translates to:
  /// **'Concurrent Download Limit'**
  String get concurrentDownloads;

  /// No description provided for @concurrentDownloadsDescription.
  ///
  /// In en, this message translates to:
  /// **'Download {count} videos at the same time'**
  String concurrentDownloadsDescription(int count);

  /// No description provided for @autoGroupDownloads.
  ///
  /// In en, this message translates to:
  /// **'Auto-create series groups'**
  String get autoGroupDownloads;

  /// No description provided for @autoGroupDownloadsDescription.
  ///
  /// In en, this message translates to:
  /// **'Put a new download into a group named after the video'**
  String get autoGroupDownloadsDescription;

  /// No description provided for @groupNameFromSeries.
  ///
  /// In en, this message translates to:
  /// **'Name groups after the series'**
  String get groupNameFromSeries;

  /// No description provided for @groupNameFromSeriesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No series name detected in this title'**
  String get groupNameFromSeriesUnavailable;

  /// No description provided for @groupNameTraditional.
  ///
  /// In en, this message translates to:
  /// **'Use Traditional Chinese group names'**
  String get groupNameTraditional;

  /// No description provided for @willUseExistingGroup.
  ///
  /// In en, this message translates to:
  /// **'Will use existing group \"{name}\"'**
  String willUseExistingGroup(String name);

  /// No description provided for @willCreateNewGroup.
  ///
  /// In en, this message translates to:
  /// **'Will create new group \"{name}\"'**
  String willCreateNewGroup(String name);

  /// No description provided for @downloadPath.
  ///
  /// In en, this message translates to:
  /// **'Download Path'**
  String get downloadPath;

  /// No description provided for @defaultDownloadPath.
  ///
  /// In en, this message translates to:
  /// **'/storage/emulated/0/Android/data/com.liar.han1meplus/files/Download/'**
  String get defaultDownloadPath;

  /// No description provided for @exportDownloads.
  ///
  /// In en, this message translates to:
  /// **'Export Downloads'**
  String get exportDownloads;

  /// No description provided for @exportDownloadsDescription.
  ///
  /// In en, this message translates to:
  /// **'Export all downloaded items from the private download directory to a custom directory'**
  String get exportDownloadsDescription;

  /// No description provided for @exportCompleted.
  ///
  /// In en, this message translates to:
  /// **'Downloads exported'**
  String get exportCompleted;

  /// No description provided for @amoledMode.
  ///
  /// In en, this message translates to:
  /// **'AMOLED Mode'**
  String get amoledMode;

  /// No description provided for @amoledModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Use pure black background in dark theme'**
  String get amoledModeDescription;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text Size'**
  String get textSize;

  /// No description provided for @textSizePreview.
  ///
  /// In en, this message translates to:
  /// **'What is the meaning of life?'**
  String get textSizePreview;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @watchHistory.
  ///
  /// In en, this message translates to:
  /// **'Watch History'**
  String get watchHistory;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @noPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists'**
  String get noPlaylists;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete Playlist'**
  String get deletePlaylist;

  /// No description provided for @deletePlaylistConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String deletePlaylistConfirmation(Object title);

  /// No description provided for @videoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} videos'**
  String videoCount(int count);

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String loadFailed(Object error);

  /// No description provided for @playlistEmpty.
  ///
  /// In en, this message translates to:
  /// **'Playlist is empty'**
  String get playlistEmpty;

  /// No description provided for @writeComment.
  ///
  /// In en, this message translates to:
  /// **'Write a Comment'**
  String get writeComment;

  /// No description provided for @commentHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your comment'**
  String get commentHint;

  /// No description provided for @latest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get latest;

  /// No description provided for @popular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get popular;

  /// No description provided for @oldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get oldest;

  /// No description provided for @playlistCreatedBy.
  ///
  /// In en, this message translates to:
  /// **'Created by {name}'**
  String playlistCreatedBy(Object name);

  /// No description provided for @playlistStats.
  ///
  /// In en, this message translates to:
  /// **'Playlist • {count} videos • {views} views'**
  String playlistStats(int count, int views);

  /// No description provided for @playAll.
  ///
  /// In en, this message translates to:
  /// **'Play All'**
  String get playAll;

  /// No description provided for @earliest.
  ///
  /// In en, this message translates to:
  /// **'Earliest'**
  String get earliest;

  /// No description provided for @mostReplies.
  ///
  /// In en, this message translates to:
  /// **'Most Replies'**
  String get mostReplies;

  /// No description provided for @mostLikes.
  ///
  /// In en, this message translates to:
  /// **'Most Liked'**
  String get mostLikes;

  /// No description provided for @mostDislikes.
  ///
  /// In en, this message translates to:
  /// **'Most Disliked'**
  String get mostDislikes;

  /// No description provided for @viewReplies.
  ///
  /// In en, this message translates to:
  /// **'View Replies'**
  String get viewReplies;

  /// No description provided for @viewRepliesCount.
  ///
  /// In en, this message translates to:
  /// **'View Replies ({count})'**
  String viewRepliesCount(int count);

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @replyComment.
  ///
  /// In en, this message translates to:
  /// **'Reply to Comment'**
  String get replyComment;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get addToPlaylist;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New Playlist'**
  String get newPlaylist;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logout;

  /// No description provided for @logoutConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Log out of the current account?'**
  String get logoutConfirmation;

  /// No description provided for @accountProfile.
  ///
  /// In en, this message translates to:
  /// **'Account Profile'**
  String get accountProfile;

  /// No description provided for @signedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed In'**
  String get signedIn;

  /// No description provided for @signedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed Out'**
  String get signedOut;

  /// No description provided for @accountSummary.
  ///
  /// In en, this message translates to:
  /// **'@{id}\n{subscriberCount} subscribers · {videoCount} videos\n{joined}'**
  String accountSummary(
    Object id,
    int subscriberCount,
    int videoCount,
    Object joined,
  );

  /// No description provided for @subscriberVideoCount.
  ///
  /// In en, this message translates to:
  /// **'{subscriberCount} subscribers · {videoCount} videos'**
  String subscriberVideoCount(int subscriberCount, int videoCount);

  /// No description provided for @joinedDate.
  ///
  /// In en, this message translates to:
  /// **'Joined {date}'**
  String joinedDate(Object date);

  /// No description provided for @mine.
  ///
  /// In en, this message translates to:
  /// **'My Page'**
  String get mine;

  /// No description provided for @tapToLogin.
  ///
  /// In en, this message translates to:
  /// **'Tap to Log In'**
  String get tapToLogin;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @saveProfile.
  ///
  /// In en, this message translates to:
  /// **'Save Profile'**
  String get saveProfile;

  /// No description provided for @oldPassword.
  ///
  /// In en, this message translates to:
  /// **'Old Password'**
  String get oldPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get login;

  /// No description provided for @finishLogin.
  ///
  /// In en, this message translates to:
  /// **'Finish Log In'**
  String get finishLogin;

  /// No description provided for @playbackSettings.
  ///
  /// In en, this message translates to:
  /// **'Playback Settings'**
  String get playbackSettings;

  /// No description provided for @playbackSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Playback speed, long-press speed, and control display time'**
  String get playbackSettingsDescription;

  /// No description provided for @defaultPlaybackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Default Playback Speed'**
  String get defaultPlaybackSpeed;

  /// No description provided for @longPressPlaybackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Default Long-press Speed'**
  String get longPressPlaybackSpeed;

  /// No description provided for @playerControlsTimeout.
  ///
  /// In en, this message translates to:
  /// **'Player Controls Auto-Hide'**
  String get playerControlsTimeout;

  /// No description provided for @playerControlsTimeoutDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically hide player controls when idle'**
  String get playerControlsTimeoutDescription;

  /// No description provided for @privacySettings.
  ///
  /// In en, this message translates to:
  /// **'Privacy Settings'**
  String get privacySettings;

  /// No description provided for @appLock.
  ///
  /// In en, this message translates to:
  /// **'App Lock'**
  String get appLock;

  /// No description provided for @appLockDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, screen-lock verification is required to enter the app'**
  String get appLockDescription;

  /// No description provided for @emergencyExit.
  ///
  /// In en, this message translates to:
  /// **'Emergency Exit'**
  String get emergencyExit;

  /// No description provided for @emergencyExitDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, pressing volume up three times stops playback and returns to the home screen'**
  String get emergencyExitDescription;

  /// No description provided for @hideFromRecents.
  ///
  /// In en, this message translates to:
  /// **'Hide from Recents'**
  String get hideFromRecents;

  /// No description provided for @hideFromRecentsDescription.
  ///
  /// In en, this message translates to:
  /// **'Hide the app from the recents screen when in the background'**
  String get hideFromRecentsDescription;

  /// No description provided for @commentSettings.
  ///
  /// In en, this message translates to:
  /// **'Comment Settings'**
  String get commentSettings;

  /// No description provided for @enableComments.
  ///
  /// In en, this message translates to:
  /// **'Enable Comments'**
  String get enableComments;

  /// No description provided for @commentsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Comments are disabled'**
  String get commentsDisabled;

  /// No description provided for @commentKeywordFilter.
  ///
  /// In en, this message translates to:
  /// **'Keyword Filter'**
  String get commentKeywordFilter;

  /// No description provided for @commentKeywordFilterDescription.
  ///
  /// In en, this message translates to:
  /// **'Comments containing a keyword will be hidden'**
  String get commentKeywordFilterDescription;

  /// No description provided for @keyword.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get keyword;

  /// No description provided for @deepLinkSettings.
  ///
  /// In en, this message translates to:
  /// **'Deep Link Settings'**
  String get deepLinkSettings;

  /// No description provided for @deepLinkSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Jump into this app quickly after opening related web pages'**
  String get deepLinkSettingsDescription;

  /// No description provided for @openAppLinkSettings.
  ///
  /// In en, this message translates to:
  /// **'Manage Web Links'**
  String get openAppLinkSettings;

  /// No description provided for @openAppLinkSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Allow Han1meWinPlus to open supported links in system settings'**
  String get openAppLinkSettingsDescription;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback Speed'**
  String get playbackSpeed;

  /// No description provided for @lockControls.
  ///
  /// In en, this message translates to:
  /// **'Lock Controls'**
  String get lockControls;

  /// No description provided for @unlockControls.
  ///
  /// In en, this message translates to:
  /// **'Unlock Controls'**
  String get unlockControls;

  /// No description provided for @brightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @comicMode.
  ///
  /// In en, this message translates to:
  /// **'Comic Mode'**
  String get comicMode;

  /// No description provided for @horizontalSearchCards.
  ///
  /// In en, this message translates to:
  /// **'Horizontal Video Cards'**
  String get horizontalSearchCards;

  /// No description provided for @horizontalSearchCardsDescription.
  ///
  /// In en, this message translates to:
  /// **'Display videos as horizontal cards'**
  String get horizontalSearchCardsDescription;

  /// No description provided for @compactSearchCards.
  ///
  /// In en, this message translates to:
  /// **'Use New Cards for Some Categories'**
  String get compactSearchCards;

  /// No description provided for @compactSearchCardsDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, Hentai and Short Anime categories use compact vertical cards with cover on top and title below'**
  String get compactSearchCardsDescription;

  /// No description provided for @expandHomeVideoCards.
  ///
  /// In en, this message translates to:
  /// **'Expand Home Video Cards'**
  String get expandHomeVideoCards;

  /// No description provided for @expandHomeVideoCardsDescription.
  ///
  /// In en, this message translates to:
  /// **'When off, each home category shows a row of videos; when on, uses the videos-per-row setting'**
  String get expandHomeVideoCardsDescription;

  /// No description provided for @searchCardsPerRow.
  ///
  /// In en, this message translates to:
  /// **'Video Cards Per Row'**
  String get searchCardsPerRow;

  /// No description provided for @searchCardsPerRowValue.
  ///
  /// In en, this message translates to:
  /// **'{count} per row'**
  String searchCardsPerRowValue(int count);

  /// No description provided for @comicModeDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, home, library, and cache show comic content only'**
  String get comicModeDescription;

  /// No description provided for @comicBrowse.
  ///
  /// In en, this message translates to:
  /// **'Comic Filters'**
  String get comicBrowse;

  /// No description provided for @trendingComics.
  ///
  /// In en, this message translates to:
  /// **'Trending Comics'**
  String get trendingComics;

  /// No description provided for @latestComics.
  ///
  /// In en, this message translates to:
  /// **'Latest Uploads'**
  String get latestComics;

  /// No description provided for @comicSearchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Comics don\'t support keyword search'**
  String get comicSearchUnavailable;

  /// No description provided for @comicDetails.
  ///
  /// In en, this message translates to:
  /// **'Comic Details'**
  String get comicDetails;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @pageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pages'**
  String pageCount(int count);

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @chapter.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get chapter;

  /// No description provided for @chapterOne.
  ///
  /// In en, this message translates to:
  /// **'Chapter 1'**
  String get chapterOne;

  /// No description provided for @addToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Add to Library'**
  String get addToLibrary;

  /// No description provided for @cacheComicConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Cache the entire comic?'**
  String get cacheComicConfirmation;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @noComics.
  ///
  /// In en, this message translates to:
  /// **'No comics'**
  String get noComics;

  /// No description provided for @pageNumber.
  ///
  /// In en, this message translates to:
  /// **'Page Number'**
  String get pageNumber;

  /// No description provided for @readingMode.
  ///
  /// In en, this message translates to:
  /// **'Reading Mode'**
  String get readingMode;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @leftToRight.
  ///
  /// In en, this message translates to:
  /// **'Single Page (Left to Right)'**
  String get leftToRight;

  /// No description provided for @rightToLeft.
  ///
  /// In en, this message translates to:
  /// **'Single Page (Right to Left)'**
  String get rightToLeft;

  /// No description provided for @topToBottom.
  ///
  /// In en, this message translates to:
  /// **'Single Page (Top to Bottom)'**
  String get topToBottom;

  /// No description provided for @scroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get scroll;

  /// No description provided for @scrollGap.
  ///
  /// In en, this message translates to:
  /// **'Scroll (with gaps)'**
  String get scrollGap;

  /// No description provided for @black.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get black;

  /// No description provided for @gray.
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get gray;

  /// No description provided for @white.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get white;

  /// No description provided for @cacheCategory.
  ///
  /// In en, this message translates to:
  /// **'Cache Category'**
  String get cacheCategory;

  /// No description provided for @newCategory.
  ///
  /// In en, this message translates to:
  /// **'New Category'**
  String get newCategory;

  /// No description provided for @navigationDrawer.
  ///
  /// In en, this message translates to:
  /// **'Use Navigation Drawer'**
  String get navigationDrawer;

  /// No description provided for @navigationDrawerDescription.
  ///
  /// In en, this message translates to:
  /// **'Use a drawer instead of the bottom navigation bar'**
  String get navigationDrawerDescription;

  /// No description provided for @colorScheme.
  ///
  /// In en, this message translates to:
  /// **'Color scheme'**
  String get colorScheme;

  /// No description provided for @colorRose.
  ///
  /// In en, this message translates to:
  /// **'Rose'**
  String get colorRose;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get colorTeal;

  /// No description provided for @colorAmber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get colorAmber;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get colorIndigo;

  /// No description provided for @colorPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get colorPink;

  /// No description provided for @colorPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colorPurple;

  /// No description provided for @colorWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get colorWhite;

  /// No description provided for @colorCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get colorCustom;

  /// No description provided for @dynamicColor.
  ///
  /// In en, this message translates to:
  /// **'Dynamic color'**
  String get dynamicColor;

  /// No description provided for @display.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// No description provided for @window.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get window;

  /// No description provided for @useSystemFont.
  ///
  /// In en, this message translates to:
  /// **'Use system font'**
  String get useSystemFont;

  /// No description provided for @useSystemFontDescription.
  ///
  /// In en, this message translates to:
  /// **'Turn off to use the HarmonyOS Sans font'**
  String get useSystemFontDescription;

  /// No description provided for @useSystemTitleBar.
  ///
  /// In en, this message translates to:
  /// **'Use system title bar'**
  String get useSystemTitleBar;

  /// No description provided for @useSystemTitleBarDescription.
  ///
  /// In en, this message translates to:
  /// **'Turn off to use the title bar built into the app'**
  String get useSystemTitleBarDescription;

  /// No description provided for @minimizeToTray.
  ///
  /// In en, this message translates to:
  /// **'Minimize to the system tray on close'**
  String get minimizeToTray;

  /// No description provided for @minimizeToTrayDescription.
  ///
  /// In en, this message translates to:
  /// **'The close button keeps the app running in the tray; use the tray menu to show the window or exit'**
  String get minimizeToTrayDescription;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Desktop notifications'**
  String get notifications;

  /// No description provided for @notificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Notify when a download finishes or a new version is available'**
  String get notificationsDescription;

  /// No description provided for @downloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get downloadComplete;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get updateAvailable;

  /// No description provided for @windowBackdrop.
  ///
  /// In en, this message translates to:
  /// **'Window backdrop'**
  String get windowBackdrop;

  /// No description provided for @windowBackdropOff.
  ///
  /// In en, this message translates to:
  /// **'Off (solid colour)'**
  String get windowBackdropOff;

  /// No description provided for @windowBackdropMica.
  ///
  /// In en, this message translates to:
  /// **'Mica (Windows 11)'**
  String get windowBackdropMica;

  /// No description provided for @windowBackdropAcrylic.
  ///
  /// In en, this message translates to:
  /// **'Acrylic (Windows 10)'**
  String get windowBackdropAcrylic;

  /// No description provided for @globalHotkeys.
  ///
  /// In en, this message translates to:
  /// **'Global hotkeys'**
  String get globalHotkeys;

  /// No description provided for @globalHotkeysDescription.
  ///
  /// In en, this message translates to:
  /// **'Work even when the window is not focused: Ctrl+Alt+H show/hide, Ctrl+Alt+Space play/pause, Ctrl+Alt+Left/Right previous/next episode'**
  String get globalHotkeysDescription;

  /// No description provided for @trayShowWindow.
  ///
  /// In en, this message translates to:
  /// **'Show Window'**
  String get trayShowWindow;

  /// No description provided for @trayExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get trayExit;

  /// No description provided for @minimizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimizeWindow;

  /// No description provided for @maximizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get maximizeWindow;

  /// No description provided for @restoreWindow.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreWindow;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @anime4k.
  ///
  /// In en, this message translates to:
  /// **'Anime4K'**
  String get anime4k;

  /// No description provided for @uploader.
  ///
  /// In en, this message translates to:
  /// **'Uploader'**
  String get uploader;

  /// No description provided for @seekSensitivity.
  ///
  /// In en, this message translates to:
  /// **'Seek Sensitivity'**
  String get seekSensitivity;

  /// No description provided for @seekSensitivityDescription.
  ///
  /// In en, this message translates to:
  /// **'Lower it to reduce the jump distance when swiping left or right'**
  String get seekSensitivityDescription;

  /// No description provided for @seekSensitivityValue.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String seekSensitivityValue(int value);

  /// No description provided for @playerSettings.
  ///
  /// In en, this message translates to:
  /// **'Player Settings'**
  String get playerSettings;

  /// No description provided for @playerSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Decoder, renderer, and advanced libmpv options'**
  String get playerSettingsDescription;

  /// No description provided for @hardwareDecode.
  ///
  /// In en, this message translates to:
  /// **'Hardware Decode'**
  String get hardwareDecode;

  /// No description provided for @hardwareDecodeDescription.
  ///
  /// In en, this message translates to:
  /// **'Use hardware-accelerated video decoding'**
  String get hardwareDecodeDescription;

  /// No description provided for @hardwareDecoder.
  ///
  /// In en, this message translates to:
  /// **'Hardware decoder'**
  String get hardwareDecoder;

  /// No description provided for @hardwareDecoderDescription.
  ///
  /// In en, this message translates to:
  /// **'Only effective when hardware decoding is enabled'**
  String get hardwareDecoderDescription;

  /// No description provided for @hardwareDecoderHint.
  ///
  /// In en, this message translates to:
  /// **'Unsupported decoders fall back to software decoding'**
  String get hardwareDecoderHint;

  /// No description provided for @projectSection.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get projectSection;

  /// No description provided for @openSourceSection.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get openSourceSection;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// No description provided for @upstreamProject.
  ///
  /// In en, this message translates to:
  /// **'Upstream project'**
  String get upstreamProject;

  /// No description provided for @contributing.
  ///
  /// In en, this message translates to:
  /// **'Contributing'**
  String get contributing;

  /// No description provided for @acknowledgements.
  ///
  /// In en, this message translates to:
  /// **'Acknowledgements'**
  String get acknowledgements;

  /// No description provided for @acknowledgementsBody.
  ///
  /// In en, this message translates to:
  /// **'This app is built on top of an upstream open-source project. Thanks to its author and every contributor.\n\nThe interface and playback are powered by Flutter, media_kit (libmpv), Riverpod, go_router and other open-source projects.\n\nThe UI font is HarmonyOS Sans by Huawei Device Co., Ltd., free to use under the HarmonyOS Sans Fonts License Agreement.'**
  String get acknowledgementsBody;

  /// No description provided for @agplLicense.
  ///
  /// In en, this message translates to:
  /// **'AGPL-3.0 license'**
  String get agplLicense;

  /// No description provided for @thirdPartyLicenses.
  ///
  /// In en, this message translates to:
  /// **'Third-party licenses'**
  String get thirdPartyLicenses;

  /// No description provided for @changelog.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get changelog;

  /// No description provided for @changelogUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Changelog is unavailable right now'**
  String get changelogUnavailable;

  /// No description provided for @openOnGitHub.
  ///
  /// In en, this message translates to:
  /// **'Open on GitHub'**
  String get openOnGitHub;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed, please try again later'**
  String get updateCheckFailed;

  /// No description provided for @javSources.
  ///
  /// In en, this message translates to:
  /// **'AV sources'**
  String get javSources;

  /// No description provided for @javSourceVerification.
  ///
  /// In en, this message translates to:
  /// **'Needs Cloudflare verification in the app'**
  String get javSourceVerification;

  /// No description provided for @javNew.
  ///
  /// In en, this message translates to:
  /// **'New Releases'**
  String get javNew;

  /// No description provided for @javUncensored.
  ///
  /// In en, this message translates to:
  /// **'Uncensored'**
  String get javUncensored;

  /// No description provided for @javSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Chinese Subtitles'**
  String get javSubtitles;

  /// No description provided for @javHot.
  ///
  /// In en, this message translates to:
  /// **'Hot'**
  String get javHot;

  /// No description provided for @javTopRated.
  ///
  /// In en, this message translates to:
  /// **'Top Rated'**
  String get javTopRated;

  /// No description provided for @javByCategory.
  ///
  /// In en, this message translates to:
  /// **'By Category'**
  String get javByCategory;

  /// No description provided for @javAmateur.
  ///
  /// In en, this message translates to:
  /// **'Amateur'**
  String get javAmateur;

  /// No description provided for @updateSection.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updateSection;

  /// No description provided for @decoder.
  ///
  /// In en, this message translates to:
  /// **'Decoder'**
  String get decoder;

  /// No description provided for @decoderSettings.
  ///
  /// In en, this message translates to:
  /// **'Decoder Settings'**
  String get decoderSettings;

  /// No description provided for @videoRenderer.
  ///
  /// In en, this message translates to:
  /// **'Video Renderer'**
  String get videoRenderer;

  /// No description provided for @viewSettings.
  ///
  /// In en, this message translates to:
  /// **'View Settings'**
  String get viewSettings;

  /// No description provided for @customParameters.
  ///
  /// In en, this message translates to:
  /// **'Custom Parameters'**
  String get customParameters;

  /// No description provided for @customParametersDescription.
  ///
  /// In en, this message translates to:
  /// **'libmpv options applied on top of the defaults'**
  String get customParametersDescription;

  /// No description provided for @customParametersHint.
  ///
  /// In en, this message translates to:
  /// **'One key=value per line, e.g. cache=yes'**
  String get customParametersHint;

  /// No description provided for @superResolution.
  ///
  /// In en, this message translates to:
  /// **'Super Resolution'**
  String get superResolution;

  /// No description provided for @superResolutionDescription.
  ///
  /// In en, this message translates to:
  /// **'Enhance the picture with libmpv shaders or scalers'**
  String get superResolutionDescription;

  /// No description provided for @availableOnlyForLibmpv.
  ///
  /// In en, this message translates to:
  /// **'Only available when the decoder is libmpv'**
  String get availableOnlyForLibmpv;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @libMpv.
  ///
  /// In en, this message translates to:
  /// **'libmpv'**
  String get libMpv;

  /// No description provided for @exoPlayer.
  ///
  /// In en, this message translates to:
  /// **'ExoPlayer'**
  String get exoPlayer;

  /// No description provided for @avPlayer.
  ///
  /// In en, this message translates to:
  /// **'AVPlayer'**
  String get avPlayer;

  /// No description provided for @rendererAuto.
  ///
  /// In en, this message translates to:
  /// **'auto'**
  String get rendererAuto;

  /// No description provided for @rendererGpu.
  ///
  /// In en, this message translates to:
  /// **'gpu'**
  String get rendererGpu;

  /// No description provided for @rendererGpuNext.
  ///
  /// In en, this message translates to:
  /// **'gpu-next'**
  String get rendererGpuNext;

  /// No description provided for @rendererMediacodecEmbed.
  ///
  /// In en, this message translates to:
  /// **'mediacodec_embed'**
  String get rendererMediacodecEmbed;

  /// No description provided for @viewPlatformView.
  ///
  /// In en, this message translates to:
  /// **'PlatformView'**
  String get viewPlatformView;

  /// No description provided for @viewSurfaceView.
  ///
  /// In en, this message translates to:
  /// **'SurfaceView'**
  String get viewSurfaceView;

  /// No description provided for @superResolutionOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get superResolutionOff;

  /// No description provided for @superResolutionOffDescription.
  ///
  /// In en, this message translates to:
  /// **'No processing, player default scaler'**
  String get superResolutionOffDescription;

  /// No description provided for @superResolutionEfficiency.
  ///
  /// In en, this message translates to:
  /// **'Anime4K Efficiency'**
  String get superResolutionEfficiency;

  /// No description provided for @superResolutionEfficiencyDescription.
  ///
  /// In en, this message translates to:
  /// **'Anime4K lite tier: line enhancement plus upscaling, lower cost'**
  String get superResolutionEfficiencyDescription;

  /// No description provided for @superResolutionQuality.
  ///
  /// In en, this message translates to:
  /// **'Anime4K Quality'**
  String get superResolutionQuality;

  /// No description provided for @superResolutionQualityDescription.
  ///
  /// In en, this message translates to:
  /// **'Anime4K quality tier: line enhancement plus upscaling, heaviest load'**
  String get superResolutionQualityDescription;

  /// No description provided for @superResolutionNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural Upscaling (EWA Lanczos)'**
  String get superResolutionNatural;

  /// No description provided for @superResolutionNaturalDescription.
  ///
  /// In en, this message translates to:
  /// **'No shaders; only swaps the upscaling filter for sharpened EWA Lanczos'**
  String get superResolutionNaturalDescription;

  /// No description provided for @switchingQuality.
  ///
  /// In en, this message translates to:
  /// **'Switching quality…'**
  String get switchingQuality;

  /// No description provided for @accountManage.
  ///
  /// In en, this message translates to:
  /// **'Account Management'**
  String get accountManage;

  /// No description provided for @accountManageSubtitleEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add or switch accounts for this site'**
  String get accountManageSubtitleEmpty;

  /// No description provided for @accountManageSubtitleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} account(s) saved for this site'**
  String accountManageSubtitleCount(int count);

  /// No description provided for @removeAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove Account'**
  String get removeAccount;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add Account'**
  String get addAccount;

  /// No description provided for @defaultCategory.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultCategory;

  /// No description provided for @appLocked.
  ///
  /// In en, this message translates to:
  /// **'App Locked'**
  String get appLocked;

  /// No description provided for @unlocking.
  ///
  /// In en, this message translates to:
  /// **'Unlocking…'**
  String get unlocking;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @homeCategoryTabs.
  ///
  /// In en, this message translates to:
  /// **'Use Collapsed Home Categories'**
  String get homeCategoryTabs;

  /// No description provided for @homeCategoryTabsDescription.
  ///
  /// In en, this message translates to:
  /// **'Pick the home category from a dropdown next to the title; videos are shown as a multi column waterfall'**
  String get homeCategoryTabsDescription;

  /// No description provided for @recommendationFilters.
  ///
  /// In en, this message translates to:
  /// **'Recommendation Filters'**
  String get recommendationFilters;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @videoTitleKeywordFilter.
  ///
  /// In en, this message translates to:
  /// **'Video Title Keyword Filter'**
  String get videoTitleKeywordFilter;

  /// No description provided for @videoTitleKeywordFilterDescription.
  ///
  /// In en, this message translates to:
  /// **'Hide videos whose titles contain a keyword'**
  String get videoTitleKeywordFilterDescription;

  /// No description provided for @minimumVideoDuration.
  ///
  /// In en, this message translates to:
  /// **'Minimum Video Duration'**
  String get minimumVideoDuration;

  /// No description provided for @minimumVideoViews.
  ///
  /// In en, this message translates to:
  /// **'Minimum Views'**
  String get minimumVideoViews;

  /// No description provided for @noFilter.
  ///
  /// In en, this message translates to:
  /// **'No Filter'**
  String get noFilter;

  /// No description provided for @value.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get value;

  /// No description provided for @authorFilter.
  ///
  /// In en, this message translates to:
  /// **'Author Filter'**
  String get authorFilter;

  /// No description provided for @authorFilterDescription.
  ///
  /// In en, this message translates to:
  /// **'Hide videos by author name or ID'**
  String get authorFilterDescription;

  /// No description provided for @author.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// No description provided for @videoTagFilter.
  ///
  /// In en, this message translates to:
  /// **'Video Tag Filter'**
  String get videoTagFilter;

  /// No description provided for @videoTagFilterDescription.
  ///
  /// In en, this message translates to:
  /// **'Hide videos containing specified tags'**
  String get videoTagFilterDescription;

  /// No description provided for @tag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tag;

  /// No description provided for @exemptSubscribedAuthors.
  ///
  /// In en, this message translates to:
  /// **'Exempt Subscribed Authors'**
  String get exemptSubscribedAuthors;

  /// No description provided for @exemptSubscribedAuthorsDescription.
  ///
  /// In en, this message translates to:
  /// **'Content from subscribed authors is not filtered'**
  String get exemptSubscribedAuthorsDescription;

  /// No description provided for @applyFiltersToRelated.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters to Related Videos'**
  String get applyFiltersToRelated;

  /// No description provided for @applyFiltersToRelatedDescription.
  ///
  /// In en, this message translates to:
  /// **'Filter related videos on the video details page'**
  String get applyFiltersToRelatedDescription;

  /// No description provided for @applyFiltersToSearch.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters to Search'**
  String get applyFiltersToSearch;

  /// No description provided for @applyFiltersToSearchDescription.
  ///
  /// In en, this message translates to:
  /// **'Filter videos in search results'**
  String get applyFiltersToSearchDescription;

  /// No description provided for @commentUserFilter.
  ///
  /// In en, this message translates to:
  /// **'Comment User Filter'**
  String get commentUserFilter;

  /// No description provided for @commentUserFilterDescription.
  ///
  /// In en, this message translates to:
  /// **'Hide comments by user name or ID'**
  String get commentUserFilterDescription;

  /// No description provided for @incognitoPlayback.
  ///
  /// In en, this message translates to:
  /// **'Incognito Mode'**
  String get incognitoPlayback;

  /// No description provided for @incognitoPlaybackDescription.
  ///
  /// In en, this message translates to:
  /// **'Do not retain watch history'**
  String get incognitoPlaybackDescription;

  /// No description provided for @autoPlayNext.
  ///
  /// In en, this message translates to:
  /// **'Auto Play Next'**
  String get autoPlayNext;

  /// No description provided for @autoPlayNextDescription.
  ///
  /// In en, this message translates to:
  /// **'Play the next episode after the current video finishes'**
  String get autoPlayNextDescription;

  /// No description provided for @loopPlayback.
  ///
  /// In en, this message translates to:
  /// **'Loop Playback'**
  String get loopPlayback;

  /// No description provided for @loopPlaybackDescription.
  ///
  /// In en, this message translates to:
  /// **'Restart the current video automatically after it finishes'**
  String get loopPlaybackDescription;

  /// No description provided for @autoPictureInPicture.
  ///
  /// In en, this message translates to:
  /// **'Auto Picture-in-Picture'**
  String get autoPictureInPicture;

  /// No description provided for @autoPictureInPictureDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter picture-in-picture when leaving the app during playback'**
  String get autoPictureInPictureDescription;

  /// No description provided for @webDavSettings.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Settings'**
  String get webDavSettings;

  /// No description provided for @webDav.
  ///
  /// In en, this message translates to:
  /// **'WebDAV'**
  String get webDav;

  /// No description provided for @webDavSync.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Sync'**
  String get webDavSync;

  /// No description provided for @watchHistorySync.
  ///
  /// In en, this message translates to:
  /// **'Watch History Sync'**
  String get watchHistorySync;

  /// No description provided for @favoriteSync.
  ///
  /// In en, this message translates to:
  /// **'Favorite Sync'**
  String get favoriteSync;

  /// No description provided for @webDavConfiguration.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Configuration'**
  String get webDavConfiguration;

  /// No description provided for @syncWatchHistoryNow.
  ///
  /// In en, this message translates to:
  /// **'Sync Watch History Now'**
  String get syncWatchHistoryNow;

  /// No description provided for @webDavDisabled.
  ///
  /// In en, this message translates to:
  /// **'Enable WebDAV sync first'**
  String get webDavDisabled;

  /// No description provided for @syncQueued.
  ///
  /// In en, this message translates to:
  /// **'Watch history sync is queued'**
  String get syncQueued;

  /// No description provided for @webDavUrl.
  ///
  /// In en, this message translates to:
  /// **'WebDAV URL'**
  String get webDavUrl;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted'**
  String get reportSubmitted;

  /// No description provided for @castToDevice.
  ///
  /// In en, this message translates to:
  /// **'Cast to Device'**
  String get castToDevice;

  /// No description provided for @pictureInPicture.
  ///
  /// In en, this message translates to:
  /// **'Picture-in-Picture'**
  String get pictureInPicture;

  /// No description provided for @videoAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Video Aspect Ratio'**
  String get videoAspectRatio;

  /// No description provided for @aspectAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get aspectAuto;

  /// No description provided for @aspectCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop to Fill'**
  String get aspectCrop;

  /// No description provided for @aspectStretch.
  ///
  /// In en, this message translates to:
  /// **'Stretch to Fill'**
  String get aspectStretch;

  /// No description provided for @aspectFourThree.
  ///
  /// In en, this message translates to:
  /// **'4:3'**
  String get aspectFourThree;

  /// No description provided for @searchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search History'**
  String get searchHistory;

  /// No description provided for @searchHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No search history'**
  String get searchHistoryEmpty;

  /// No description provided for @deleteSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Delete search history'**
  String get deleteSearchHistory;

  /// No description provided for @restoreSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search this combination'**
  String get restoreSearchHistory;

  /// No description provided for @searchHistorySummary.
  ///
  /// In en, this message translates to:
  /// **'{query} · {filters}'**
  String searchHistorySummary(Object query, Object filters);

  /// No description provided for @searchHistoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get searchHistoryAll;

  /// No description provided for @searchHistoryTags.
  ///
  /// In en, this message translates to:
  /// **'{count} tags'**
  String searchHistoryTags(int count);

  /// No description provided for @externalPlayback.
  ///
  /// In en, this message translates to:
  /// **'External Playback'**
  String get externalPlayback;

  /// No description provided for @addTags.
  ///
  /// In en, this message translates to:
  /// **'Add Tags'**
  String get addTags;

  /// No description provided for @removeTags.
  ///
  /// In en, this message translates to:
  /// **'Remove Tags'**
  String get removeTags;

  /// No description provided for @translate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translate;

  /// No description provided for @translating.
  ///
  /// In en, this message translates to:
  /// **'Translating...'**
  String get translating;

  /// No description provided for @translationFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed'**
  String get translationFailed;

  /// No description provided for @cachedDownloads.
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get cachedDownloads;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @switchGroup.
  ///
  /// In en, this message translates to:
  /// **'Switch Groups'**
  String get switchGroup;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @sortOrder.
  ///
  /// In en, this message translates to:
  /// **'Sort Order'**
  String get sortOrder;

  /// No description provided for @recentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently Updated'**
  String get recentlyUpdated;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete Group'**
  String get deleteGroup;

  /// No description provided for @deleteGroupDescription.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete this group without deleting cached media'**
  String get deleteGroupDescription;

  /// No description provided for @deleteGroupConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete this group? It will be gone forever!'**
  String get deleteGroupConfirmation;

  /// No description provided for @backupSettings.
  ///
  /// In en, this message translates to:
  /// **'Backup Settings'**
  String get backupSettings;

  /// No description provided for @backupSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Import or export an application data backup'**
  String get backupSettingsDescription;

  /// No description provided for @exportDataBackup.
  ///
  /// In en, this message translates to:
  /// **'Export Data Backup'**
  String get exportDataBackup;

  /// No description provided for @exportDataBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Export settings, watch history, download groups and video information, key H-frames, and check-in records for device migration.'**
  String get exportDataBackupDescription;

  /// No description provided for @importDataBackup.
  ///
  /// In en, this message translates to:
  /// **'Import Data Backup'**
  String get importDataBackup;

  /// No description provided for @importDataBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Restore settings, watch history, download groups and video information, key H-frames, and check-in records from a backup file.'**
  String get importDataBackupDescription;

  /// No description provided for @backupExported.
  ///
  /// In en, this message translates to:
  /// **'Data backup exported'**
  String get backupExported;

  /// No description provided for @backupImported.
  ///
  /// In en, this message translates to:
  /// **'Data backup imported'**
  String get backupImported;

  /// No description provided for @androidPrivateDownloadPath.
  ///
  /// In en, this message translates to:
  /// **'Android downloads use the private app directory. Export downloads to save them through SAF.'**
  String get androidPrivateDownloadPath;

  /// No description provided for @privateDownloadPath.
  ///
  /// In en, this message translates to:
  /// **'Mobile downloads use the private app directory. Export downloads to save them to a custom directory.'**
  String get privateDownloadPath;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose Folder'**
  String get chooseFolder;

  /// No description provided for @manualCookieLogin.
  ///
  /// In en, this message translates to:
  /// **'Enter Cookies Manually'**
  String get manualCookieLogin;

  /// No description provided for @cookies.
  ///
  /// In en, this message translates to:
  /// **'Cookies'**
  String get cookies;

  /// No description provided for @invalidCookies.
  ///
  /// In en, this message translates to:
  /// **'Enter valid cookies'**
  String get invalidCookies;

  /// No description provided for @myListSection.
  ///
  /// In en, this message translates to:
  /// **'My Lists'**
  String get myListSection;

  /// No description provided for @videoSection.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videoSection;

  /// No description provided for @checkIn.
  ///
  /// In en, this message translates to:
  /// **'Check-in'**
  String get checkIn;

  /// No description provided for @checkInToday.
  ///
  /// In en, this message translates to:
  /// **'Today\'s check-ins'**
  String get checkInToday;

  /// No description provided for @checkInNotYet.
  ///
  /// In en, this message translates to:
  /// **'No check-ins today yet'**
  String get checkInNotYet;

  /// No description provided for @checkInTimes.
  ///
  /// In en, this message translates to:
  /// **'Checked in {count} times'**
  String checkInTimes(int count);

  /// No description provided for @checkInNow.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get checkInNow;

  /// No description provided for @checkInType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get checkInType;

  /// No description provided for @checkInTypeMasturbation.
  ///
  /// In en, this message translates to:
  /// **'Masturbation'**
  String get checkInTypeMasturbation;

  /// No description provided for @checkInTypeWetDream.
  ///
  /// In en, this message translates to:
  /// **'Wet dream'**
  String get checkInTypeWetDream;

  /// No description provided for @checkInTypeSex.
  ///
  /// In en, this message translates to:
  /// **'Sex'**
  String get checkInTypeSex;

  /// No description provided for @checkInTypeOral.
  ///
  /// In en, this message translates to:
  /// **'Oral'**
  String get checkInTypeOral;

  /// No description provided for @checkInMonthDays.
  ///
  /// In en, this message translates to:
  /// **'Days this month'**
  String get checkInMonthDays;

  /// No description provided for @checkInMonthTotal.
  ///
  /// In en, this message translates to:
  /// **'Times this month'**
  String get checkInMonthTotal;

  /// No description provided for @checkInBestStreak.
  ///
  /// In en, this message translates to:
  /// **'Best streak'**
  String get checkInBestStreak;

  /// No description provided for @railPreviews.
  ///
  /// In en, this message translates to:
  /// **'Previews'**
  String get railPreviews;

  /// No description provided for @railWatchLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get railWatchLater;

  /// No description provided for @railFavorites.
  ///
  /// In en, this message translates to:
  /// **'Liked'**
  String get railFavorites;

  /// No description provided for @railPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get railPlaylists;

  /// No description provided for @railSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subs'**
  String get railSubscriptions;

  /// No description provided for @railHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get railHistory;

  /// No description provided for @homeQuickCategories.
  ///
  /// In en, this message translates to:
  /// **'Home Shortcuts'**
  String get homeQuickCategories;

  /// No description provided for @homeQuickCategoriesDescription.
  ///
  /// In en, this message translates to:
  /// **'The six shortcuts shown in the home header; content and order are customizable'**
  String get homeQuickCategoriesDescription;

  /// No description provided for @homeQuickCategoriesSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected (drag to reorder)'**
  String get homeQuickCategoriesSelected;

  /// No description provided for @homeQuickCategoriesHint.
  ///
  /// In en, this message translates to:
  /// **'Up to {max}, tap ✕ to remove'**
  String homeQuickCategoriesHint(int max);

  /// No description provided for @homeQuickCategoriesAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get homeQuickCategoriesAvailable;

  /// No description provided for @homeQuickCategoriesFull.
  ///
  /// In en, this message translates to:
  /// **'Limit reached ({max})'**
  String homeQuickCategoriesFull(int max);

  /// No description provided for @homeQuickCategoriesNeedsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Load the home page first to list all categories (only saved ones are shown now)'**
  String get homeQuickCategoriesNeedsNetwork;

  /// No description provided for @clearSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearSearchHistory;

  /// No description provided for @searchPopularTags.
  ///
  /// In en, this message translates to:
  /// **'Popular tags'**
  String get searchPopularTags;

  /// No description provided for @searchSortGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get searchSortGeneral;

  /// No description provided for @searchMoreFilters.
  ///
  /// In en, this message translates to:
  /// **'More filters'**
  String get searchMoreFilters;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @backToTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get backToTop;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
