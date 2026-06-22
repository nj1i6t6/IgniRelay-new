import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
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
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S? of(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

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
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'烽傳 IgniRelay'**
  String get appTitle;

  /// No description provided for @mainStartupLoading.
  ///
  /// In zh, this message translates to:
  /// **'烽傳 啟動中...'**
  String get mainStartupLoading;

  /// No description provided for @mainBluetoothDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要開啟藍牙'**
  String get mainBluetoothDialogTitle;

  /// No description provided for @mainBluetoothDialogContent.
  ///
  /// In zh, this message translates to:
  /// **'烽傳使用藍牙建立 Mesh 離線網路，\n用於傳遞求救訊號與物資媒合。\n\n請開啟藍牙以啟用完整功能。'**
  String get mainBluetoothDialogContent;

  /// No description provided for @mainBluetoothDialogCancel.
  ///
  /// In zh, this message translates to:
  /// **'稍後'**
  String get mainBluetoothDialogCancel;

  /// No description provided for @mainBluetoothDialogConfirm.
  ///
  /// In zh, this message translates to:
  /// **'開啟藍牙'**
  String get mainBluetoothDialogConfirm;

  /// No description provided for @mainBleFailSnack.
  ///
  /// In zh, this message translates to:
  /// **'BLE Mesh 啟動失敗：{error}'**
  String mainBleFailSnack(String error);

  /// No description provided for @mainPermissionSnack.
  ///
  /// In zh, this message translates to:
  /// **'需要藍牙與位置權限才能啟用 Mesh 網路'**
  String get mainPermissionSnack;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @tierLabel1Standard.
  ///
  /// In zh, this message translates to:
  /// **'標準模式 (Tier 1)'**
  String get tierLabel1Standard;

  /// No description provided for @tierLabel1Force.
  ///
  /// In zh, this message translates to:
  /// **'全速模式 (Tier 1)'**
  String get tierLabel1Force;

  /// No description provided for @tierLabel2EcoRelay.
  ///
  /// In zh, this message translates to:
  /// **'省電中繼模式 (Tier 2)'**
  String get tierLabel2EcoRelay;

  /// No description provided for @tierLabel3UltraEco.
  ///
  /// In zh, this message translates to:
  /// **'極省電模式 (Tier 3)'**
  String get tierLabel3UltraEco;

  /// No description provided for @shellTabSafety.
  ///
  /// In zh, this message translates to:
  /// **'安全'**
  String get shellTabSafety;

  /// No description provided for @shellTabPosition.
  ///
  /// In zh, this message translates to:
  /// **'位置'**
  String get shellTabPosition;

  /// No description provided for @shellTabEvents.
  ///
  /// In zh, this message translates to:
  /// **'事件'**
  String get shellTabEvents;

  /// No description provided for @shellTabAssist.
  ///
  /// In zh, this message translates to:
  /// **'協助'**
  String get shellTabAssist;

  /// No description provided for @shellTabMine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get shellTabMine;

  /// No description provided for @noFieldTitle.
  ///
  /// In zh, this message translates to:
  /// **'烽傳 IgniRelay'**
  String get noFieldTitle;

  /// No description provided for @noFieldSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'加入或建立一個場域，開始被看見、能求救、留下最後足跡。'**
  String get noFieldSubtitle;

  /// No description provided for @noFieldJoin.
  ///
  /// In zh, this message translates to:
  /// **'加入場域'**
  String get noFieldJoin;

  /// No description provided for @noFieldCreate.
  ///
  /// In zh, this message translates to:
  /// **'建立場域'**
  String get noFieldCreate;

  /// No description provided for @noFieldPreview.
  ///
  /// In zh, this message translates to:
  /// **'先看功能'**
  String get noFieldPreview;

  /// No description provided for @myTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get myTitle;

  /// No description provided for @mySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'場域、身分與設定'**
  String get mySubtitle;

  /// No description provided for @myFieldSection.
  ///
  /// In zh, this message translates to:
  /// **'場域'**
  String get myFieldSection;

  /// No description provided for @myFieldManage.
  ///
  /// In zh, this message translates to:
  /// **'場域管理'**
  String get myFieldManage;

  /// No description provided for @myCurrentField.
  ///
  /// In zh, this message translates to:
  /// **'目前場域：{name}'**
  String myCurrentField(String name);

  /// No description provided for @myFieldUnnamed.
  ///
  /// In zh, this message translates to:
  /// **'（未命名）'**
  String get myFieldUnnamed;

  /// No description provided for @myFieldJoinedCount.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {count} 個'**
  String myFieldJoinedCount(int count);

  /// No description provided for @myNoField.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入場域。'**
  String get myNoField;

  /// No description provided for @myRoleSection.
  ///
  /// In zh, this message translates to:
  /// **'身分與角色'**
  String get myRoleSection;

  /// No description provided for @myRoleEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'加入或建立場域後顯示。'**
  String get myRoleEmptyHint;

  /// No description provided for @myRoleOwnerDesc.
  ///
  /// In zh, this message translates to:
  /// **'你建立了這個場域，可分享加入 QR。'**
  String get myRoleOwnerDesc;

  /// No description provided for @myRoleParticipantDesc.
  ///
  /// In zh, this message translates to:
  /// **'你已加入這個場域。'**
  String get myRoleParticipantDesc;

  /// No description provided for @roleHost.
  ///
  /// In zh, this message translates to:
  /// **'主辦'**
  String get roleHost;

  /// No description provided for @roleMember.
  ///
  /// In zh, this message translates to:
  /// **'成員'**
  String get roleMember;

  /// No description provided for @myPermissionSection.
  ///
  /// In zh, this message translates to:
  /// **'權限狀態'**
  String get myPermissionSection;

  /// No description provided for @myComingSoon.
  ///
  /// In zh, this message translates to:
  /// **'即將提供'**
  String get myComingSoon;

  /// No description provided for @myDeveloperDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'開發者診斷'**
  String get myDeveloperDiagnostics;

  /// No description provided for @settingsSection.
  ///
  /// In zh, this message translates to:
  /// **'設定'**
  String get settingsSection;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'語言'**
  String get settingsLanguage;

  /// No description provided for @settingsTextSize.
  ///
  /// In zh, this message translates to:
  /// **'字體大小'**
  String get settingsTextSize;

  /// No description provided for @settingsTextSizeStandard.
  ///
  /// In zh, this message translates to:
  /// **'標準'**
  String get settingsTextSizeStandard;

  /// No description provided for @settingsTextSizeLarge.
  ///
  /// In zh, this message translates to:
  /// **'大字'**
  String get settingsTextSizeLarge;

  /// No description provided for @settingsTextSizeXLarge.
  ///
  /// In zh, this message translates to:
  /// **'特大字'**
  String get settingsTextSizeXLarge;

  /// No description provided for @settingsTextSizeHuge.
  ///
  /// In zh, this message translates to:
  /// **'超大字'**
  String get settingsTextSizeHuge;

  /// No description provided for @fieldTitle.
  ///
  /// In zh, this message translates to:
  /// **'場域'**
  String get fieldTitle;

  /// No description provided for @fieldSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'加入場域後才能收發事件'**
  String get fieldSubtitle;

  /// No description provided for @fieldNoneTitle.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入任何場域'**
  String get fieldNoneTitle;

  /// No description provided for @fieldNoneBody.
  ///
  /// In zh, this message translates to:
  /// **'掃描主辦方的場域 QR、輸入加入代碼，或自行建立一個場域。'**
  String get fieldNoneBody;

  /// No description provided for @fieldUnnamed.
  ///
  /// In zh, this message translates to:
  /// **'（未命名場域）'**
  String get fieldUnnamed;

  /// No description provided for @fieldActiveChip.
  ///
  /// In zh, this message translates to:
  /// **'作用中'**
  String get fieldActiveChip;

  /// No description provided for @fieldScanJoin.
  ///
  /// In zh, this message translates to:
  /// **'掃碼加入'**
  String get fieldScanJoin;

  /// No description provided for @fieldEnterCode.
  ///
  /// In zh, this message translates to:
  /// **'輸入代碼'**
  String get fieldEnterCode;

  /// No description provided for @fieldCreateNew.
  ///
  /// In zh, this message translates to:
  /// **'建立新場域'**
  String get fieldCreateNew;

  /// No description provided for @fieldJoinedHeader.
  ///
  /// In zh, this message translates to:
  /// **'已加入的場域（{count}）'**
  String fieldJoinedHeader(int count);

  /// No description provided for @fieldShowQr.
  ///
  /// In zh, this message translates to:
  /// **'顯示 QR'**
  String get fieldShowQr;

  /// No description provided for @fieldLeave.
  ///
  /// In zh, this message translates to:
  /// **'離開場域'**
  String get fieldLeave;

  /// No description provided for @fieldCreateFailed.
  ///
  /// In zh, this message translates to:
  /// **'建立場域失敗：{error}'**
  String fieldCreateFailed(String error);

  /// No description provided for @fieldSecretNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到此場域的密鑰，無法顯示 QR'**
  String get fieldSecretNotFound;

  /// No description provided for @fieldCodeTitle.
  ///
  /// In zh, this message translates to:
  /// **'輸入場域代碼'**
  String get fieldCodeTitle;

  /// No description provided for @fieldCodeBody.
  ///
  /// In zh, this message translates to:
  /// **'貼上 IGNI1 場域代碼，或輸入 64 個十六進位字元的場域密鑰。'**
  String get fieldCodeBody;

  /// No description provided for @fieldCodeHint.
  ///
  /// In zh, this message translates to:
  /// **'IGNI1:… 或 a1b2c3…'**
  String get fieldCodeHint;

  /// No description provided for @fieldCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get fieldCancel;

  /// No description provided for @fieldJoin.
  ///
  /// In zh, this message translates to:
  /// **'加入'**
  String get fieldJoin;

  /// No description provided for @fieldScannedName.
  ///
  /// In zh, this message translates to:
  /// **'掃碼場域'**
  String get fieldScannedName;

  /// No description provided for @fieldCodeUnrecognized.
  ///
  /// In zh, this message translates to:
  /// **'代碼格式無法辨識：需為 IGNI1 代碼或 64 個十六進位字元'**
  String get fieldCodeUnrecognized;

  /// No description provided for @fieldDefaultNamePrefix.
  ///
  /// In zh, this message translates to:
  /// **'場域-{prefix}'**
  String fieldDefaultNamePrefix(String prefix);

  /// No description provided for @fieldJoinedSnack.
  ///
  /// In zh, this message translates to:
  /// **'已加入場域 {id}…'**
  String fieldJoinedSnack(String id);

  /// No description provided for @fieldJoinFailed.
  ///
  /// In zh, this message translates to:
  /// **'加入場域失敗：{error}'**
  String fieldJoinFailed(String error);

  /// No description provided for @fieldLeaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'離開場域？'**
  String get fieldLeaveTitle;

  /// No description provided for @fieldLeaveBody.
  ///
  /// In zh, this message translates to:
  /// **'即將離開「{name}」。此動作不可復原，將從本機刪除此場域的密鑰，需重新掃碼 / 輸入代碼才能再次加入。'**
  String fieldLeaveBody(String name);

  /// No description provided for @fieldLeaveConfirm.
  ///
  /// In zh, this message translates to:
  /// **'離開'**
  String get fieldLeaveConfirm;

  /// No description provided for @fieldLeftSnack.
  ///
  /// In zh, this message translates to:
  /// **'已離開場域'**
  String get fieldLeftSnack;

  /// No description provided for @fieldLeaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'離開場域失敗：{error}'**
  String fieldLeaveFailed(String error);

  /// No description provided for @fieldCreateTitle.
  ///
  /// In zh, this message translates to:
  /// **'建立新場域'**
  String get fieldCreateTitle;

  /// No description provided for @fieldNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'場域名稱'**
  String get fieldNameLabel;

  /// No description provided for @fieldNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例：台北車站避難所'**
  String get fieldNameHint;

  /// No description provided for @fieldCreateConfirm.
  ///
  /// In zh, this message translates to:
  /// **'建立'**
  String get fieldCreateConfirm;

  /// No description provided for @fieldDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'新場域'**
  String get fieldDefaultName;

  /// No description provided for @fieldErrEmpty.
  ///
  /// In zh, this message translates to:
  /// **'代碼是空的'**
  String get fieldErrEmpty;

  /// No description provided for @fieldErrBadPrefix.
  ///
  /// In zh, this message translates to:
  /// **'這不是 IgniRelay 場域代碼（前綴不符）'**
  String get fieldErrBadPrefix;

  /// No description provided for @fieldErrTooFewSegments.
  ///
  /// In zh, this message translates to:
  /// **'代碼不完整'**
  String get fieldErrTooFewSegments;

  /// No description provided for @fieldErrBadSecret.
  ///
  /// In zh, this message translates to:
  /// **'代碼的場域密鑰格式錯誤'**
  String get fieldErrBadSecret;

  /// No description provided for @fieldErrBadCloudUrl.
  ///
  /// In zh, this message translates to:
  /// **'代碼的雲端網址無效（僅接受 https://）'**
  String get fieldErrBadCloudUrl;

  /// No description provided for @fieldErrStaffWithoutCloud.
  ///
  /// In zh, this message translates to:
  /// **'代碼格式錯誤：含 staff token 卻缺雲端網址'**
  String get fieldErrStaffWithoutCloud;

  /// No description provided for @fieldErrMalformed.
  ///
  /// In zh, this message translates to:
  /// **'代碼內容毀損，無法解析'**
  String get fieldErrMalformed;

  /// No description provided for @fieldScanBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get fieldScanBack;

  /// No description provided for @fieldScanTitle.
  ///
  /// In zh, this message translates to:
  /// **'掃描場域 QR'**
  String get fieldScanTitle;

  /// No description provided for @fieldScanHint.
  ///
  /// In zh, this message translates to:
  /// **'對準主辦方的場域 QR 即可自動加入'**
  String get fieldScanHint;

  /// No description provided for @fieldScanReject.
  ///
  /// In zh, this message translates to:
  /// **'這不是 IgniRelay 場域 QR，請換一個'**
  String get fieldScanReject;

  /// No description provided for @fieldScanNoCameraTitle.
  ///
  /// In zh, this message translates to:
  /// **'無法開啟相機'**
  String get fieldScanNoCameraTitle;

  /// No description provided for @fieldScanNoCameraBody.
  ///
  /// In zh, this message translates to:
  /// **'請確認已授予相機權限，或改用「輸入代碼」加入場域。'**
  String get fieldScanNoCameraBody;

  /// No description provided for @fieldQrTitle.
  ///
  /// In zh, this message translates to:
  /// **'場域 QR'**
  String get fieldQrTitle;

  /// No description provided for @fieldQrSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'讓對方掃描即可加入同一場域'**
  String get fieldQrSubtitle;

  /// No description provided for @fieldQrDebugWarning.
  ///
  /// In zh, this message translates to:
  /// **'（debug）此代碼含場域密鑰，請勿外流：'**
  String get fieldQrDebugWarning;

  /// No description provided for @fieldQrDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get fieldQrDone;

  /// No description provided for @previewModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'示範模式 · 不會送出任何資料'**
  String get previewModeSubtitle;

  /// No description provided for @previewBadge.
  ///
  /// In zh, this message translates to:
  /// **'示範資料'**
  String get previewBadge;

  /// No description provided for @previewBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get previewBack;

  /// No description provided for @previewPrev.
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get previewPrev;

  /// No description provided for @previewNext.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get previewNext;

  /// No description provided for @previewDemoChip.
  ///
  /// In zh, this message translates to:
  /// **'示範'**
  String get previewDemoChip;

  /// No description provided for @previewJoinIntro.
  ///
  /// In zh, this message translates to:
  /// **'掃描主辦者的 QR 或輸入密鑰即可加入一個場域。場域決定你和誰互通——只有同一個場域的人，才看得到彼此。'**
  String get previewJoinIntro;

  /// No description provided for @previewSafetyTitle.
  ///
  /// In zh, this message translates to:
  /// **'安全：被看見 + 求救'**
  String get previewSafetyTitle;

  /// No description provided for @previewSafetyIntro.
  ///
  /// In zh, this message translates to:
  /// **'加入後，App 會定期留下你的足跡，讓場域裡的人知道你還在、在哪附近。需要時可以長按發出 SOS。'**
  String get previewSafetyIntro;

  /// No description provided for @previewSafetyFootprintTitle.
  ///
  /// In zh, this message translates to:
  /// **'自動足跡（被看見）'**
  String get previewSafetyFootprintTitle;

  /// No description provided for @previewSafetyFootprintBody.
  ///
  /// In zh, this message translates to:
  /// **'靜止時省電、移動時更頻繁地留下足跡。不需要一直盯著手機，別人也能看到你最後的位置。'**
  String get previewSafetyFootprintBody;

  /// No description provided for @previewSafetySosTitle.
  ///
  /// In zh, this message translates to:
  /// **'求救 SOS'**
  String get previewSafetySosTitle;

  /// No description provided for @previewSafetySosBody.
  ///
  /// In zh, this message translates to:
  /// **'長按求救鍵，選擇紅色（受困）或黃色（受傷）。送出前有 5 秒可取消，避免誤觸。（示範不會真的送出）'**
  String get previewSafetySosBody;

  /// No description provided for @previewPositionTitle.
  ///
  /// In zh, this message translates to:
  /// **'位置：最後可信位置'**
  String get previewPositionTitle;

  /// No description provided for @previewPositionIntro.
  ///
  /// In zh, this message translates to:
  /// **'看見附近成員「最後可信的位置」與相對方位。雷達固定北朝上，越靠近中心代表離你越近。（這裡顯示的是示範資料）'**
  String get previewPositionIntro;

  /// No description provided for @previewFootprintLine.
  ///
  /// In zh, this message translates to:
  /// **'最後可信位置 · {ago}'**
  String previewFootprintLine(String ago);

  /// No description provided for @previewEventsTitle.
  ///
  /// In zh, this message translates to:
  /// **'事件：危害 / 廣播 / 打卡'**
  String get previewEventsTitle;

  /// No description provided for @previewEventsIntro.
  ///
  /// In zh, this message translates to:
  /// **'場域裡的重要訊息會集中在事件：危害提醒、管理者廣播、平安打卡，讓你快速掌握現場狀況。'**
  String get previewEventsIntro;

  /// No description provided for @previewAssistTitle.
  ///
  /// In zh, this message translates to:
  /// **'協助 + 離線也能用'**
  String get previewAssistTitle;

  /// No description provided for @previewAssistIntro.
  ///
  /// In zh, this message translates to:
  /// **'需要或能提供協助時，可以在「協助」裡媒合。最重要的是——沒有網路時，App 仍透過近距離轉傳運作。'**
  String get previewAssistIntro;

  /// No description provided for @previewAssistMatchTitle.
  ///
  /// In zh, this message translates to:
  /// **'協助媒合'**
  String get previewAssistMatchTitle;

  /// No description provided for @previewAssistMatchBody.
  ///
  /// In zh, this message translates to:
  /// **'提出需求或回應他人需求，讓資源在場域內就近流動。'**
  String get previewAssistMatchBody;

  /// No description provided for @previewAssistOfflineTitle.
  ///
  /// In zh, this message translates to:
  /// **'離線降級'**
  String get previewAssistOfflineTitle;

  /// No description provided for @previewAssistOfflineBody.
  ///
  /// In zh, this message translates to:
  /// **'沒有基地台或網路時，訊息會透過附近的裝置一手接一手傳遞；收訊恢復時自動補送，不會憑空捏造位置。'**
  String get previewAssistOfflineBody;

  /// No description provided for @previewToneSos.
  ///
  /// In zh, this message translates to:
  /// **'求救'**
  String get previewToneSos;

  /// No description provided for @previewToneWarn.
  ///
  /// In zh, this message translates to:
  /// **'危害'**
  String get previewToneWarn;

  /// No description provided for @previewToneInfo.
  ///
  /// In zh, this message translates to:
  /// **'廣播'**
  String get previewToneInfo;

  /// No description provided for @previewToneOk.
  ///
  /// In zh, this message translates to:
  /// **'平安'**
  String get previewToneOk;

  /// No description provided for @previewToneNeutral.
  ///
  /// In zh, this message translates to:
  /// **'事件'**
  String get previewToneNeutral;

  /// No description provided for @previewFieldLabel.
  ///
  /// In zh, this message translates to:
  /// **'示範場域 · DEMO-FIELD'**
  String get previewFieldLabel;

  /// No description provided for @previewAlias.
  ///
  /// In zh, this message translates to:
  /// **'化名 {alias}'**
  String previewAlias(String alias);

  /// No description provided for @previewFpAgo1.
  ///
  /// In zh, this message translates to:
  /// **'1 分鐘前'**
  String get previewFpAgo1;

  /// No description provided for @previewFpAgo4.
  ///
  /// In zh, this message translates to:
  /// **'4 分鐘前'**
  String get previewFpAgo4;

  /// No description provided for @previewFpAgoTrapped.
  ///
  /// In zh, this message translates to:
  /// **'受困 · 2 分鐘前'**
  String get previewFpAgoTrapped;

  /// No description provided for @previewSosTitle.
  ///
  /// In zh, this message translates to:
  /// **'求救 · 受困'**
  String get previewSosTitle;

  /// No description provided for @previewSosAgo.
  ///
  /// In zh, this message translates to:
  /// **'2 分鐘前'**
  String get previewSosAgo;

  /// No description provided for @previewHazardTitle.
  ///
  /// In zh, this message translates to:
  /// **'危害 · 火災 FIRE'**
  String get previewHazardTitle;

  /// No description provided for @previewHazardDetail.
  ///
  /// In zh, this message translates to:
  /// **'sev 2 · 巷口濃煙'**
  String get previewHazardDetail;

  /// No description provided for @previewHazardAgo.
  ///
  /// In zh, this message translates to:
  /// **'6 分鐘前'**
  String get previewHazardAgo;

  /// No description provided for @previewBroadcastTitle.
  ///
  /// In zh, this message translates to:
  /// **'管理廣播'**
  String get previewBroadcastTitle;

  /// No description provided for @previewBroadcastDetail.
  ///
  /// In zh, this message translates to:
  /// **'集合點改至北側出口'**
  String get previewBroadcastDetail;

  /// No description provided for @previewBroadcastAgo.
  ///
  /// In zh, this message translates to:
  /// **'10 分鐘前'**
  String get previewBroadcastAgo;

  /// No description provided for @previewCheckpointTitle.
  ///
  /// In zh, this message translates to:
  /// **'打卡 · 平安'**
  String get previewCheckpointTitle;

  /// No description provided for @previewCheckpointAgo.
  ///
  /// In zh, this message translates to:
  /// **'12 分鐘前'**
  String get previewCheckpointAgo;

  /// No description provided for @commonSend.
  ///
  /// In zh, this message translates to:
  /// **'送出'**
  String get commonSend;

  /// No description provided for @noCoordinate.
  ///
  /// In zh, this message translates to:
  /// **'無座標'**
  String get noCoordinate;

  /// No description provided for @noCoordinateParen.
  ///
  /// In zh, this message translates to:
  /// **'（無座標）'**
  String get noCoordinateParen;

  /// No description provided for @timeJustNow.
  ///
  /// In zh, this message translates to:
  /// **'剛剛'**
  String get timeJustNow;

  /// No description provided for @timeAgoSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒前'**
  String timeAgoSeconds(int seconds);

  /// No description provided for @timeAgoMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分鐘前'**
  String timeAgoMinutes(int minutes);

  /// No description provided for @timeAgoHours.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小時前'**
  String timeAgoHours(int hours);

  /// No description provided for @timeAgoDays.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天前'**
  String timeAgoDays(int days);

  /// No description provided for @safetyTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的安全'**
  String get safetyTitle;

  /// No description provided for @safetySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'通訊與足跡'**
  String get safetySubtitle;

  /// No description provided for @safetyToggleFailed.
  ///
  /// In zh, this message translates to:
  /// **'通訊切換失敗：{error}'**
  String safetyToggleFailed(String error);

  /// No description provided for @safetyUpdateNoField.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入場域 — 請先到「我的」加入或建立場域'**
  String get safetyUpdateNoField;

  /// No description provided for @safetyUpdateSent.
  ///
  /// In zh, this message translates to:
  /// **'已更新足跡（{count} 個鄰近裝置）'**
  String safetyUpdateSent(int count);

  /// No description provided for @safetyUpdateQueued.
  ///
  /// In zh, this message translates to:
  /// **'足跡已排入佇列，待鄰近裝置上線後送出'**
  String get safetyUpdateQueued;

  /// No description provided for @safetyUpdateAttempted.
  ///
  /// In zh, this message translates to:
  /// **'已嘗試更新足跡'**
  String get safetyUpdateAttempted;

  /// No description provided for @safetyUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新足跡失敗：{error}'**
  String safetyUpdateFailed(String error);

  /// No description provided for @safetyCommsOn.
  ///
  /// In zh, this message translates to:
  /// **'近距離通訊：開啟'**
  String get safetyCommsOn;

  /// No description provided for @safetyCommsOff.
  ///
  /// In zh, this message translates to:
  /// **'近距離通訊：關閉'**
  String get safetyCommsOff;

  /// No description provided for @safetyTurnOn.
  ///
  /// In zh, this message translates to:
  /// **'開啟'**
  String get safetyTurnOn;

  /// No description provided for @safetyTurnOff.
  ///
  /// In zh, this message translates to:
  /// **'關閉'**
  String get safetyTurnOff;

  /// No description provided for @safetyCurrentPath.
  ///
  /// In zh, this message translates to:
  /// **'目前路徑：{path}'**
  String safetyCurrentPath(String path);

  /// No description provided for @safetyStatPeers.
  ///
  /// In zh, this message translates to:
  /// **'鄰近裝置'**
  String get safetyStatPeers;

  /// No description provided for @safetyStatSent.
  ///
  /// In zh, this message translates to:
  /// **'已送'**
  String get safetyStatSent;

  /// No description provided for @safetyStatReceived.
  ///
  /// In zh, this message translates to:
  /// **'已收'**
  String get safetyStatReceived;

  /// No description provided for @safetyStatQueued.
  ///
  /// In zh, this message translates to:
  /// **'待送'**
  String get safetyStatQueued;

  /// No description provided for @safetyLastFootprint.
  ///
  /// In zh, this message translates to:
  /// **'最後足跡：{time}'**
  String safetyLastFootprint(String time);

  /// No description provided for @safetyFootprintTitle.
  ///
  /// In zh, this message translates to:
  /// **'足跡'**
  String get safetyFootprintTitle;

  /// No description provided for @safetyFootprintBody.
  ///
  /// In zh, this message translates to:
  /// **'讓附近的人看見你最後可信的位置。'**
  String get safetyFootprintBody;

  /// No description provided for @safetyUpdateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即更新足跡'**
  String get safetyUpdateNow;

  /// No description provided for @safetyAutoBeacon.
  ///
  /// In zh, this message translates to:
  /// **'自動足跡信標'**
  String get safetyAutoBeacon;

  /// No description provided for @safetyMotion.
  ///
  /// In zh, this message translates to:
  /// **'動作偵測：{state}'**
  String safetyMotion(String state);

  /// No description provided for @safetyGpsFix.
  ///
  /// In zh, this message translates to:
  /// **'GPS 定位：{age}'**
  String safetyGpsFix(String age);

  /// No description provided for @safetyGpsPolicy.
  ///
  /// In zh, this message translates to:
  /// **'定位策略：{reason}'**
  String safetyGpsPolicy(String reason);

  /// No description provided for @safetyRecentTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近足跡'**
  String get safetyRecentTitle;

  /// No description provided for @safetyNoFootprint.
  ///
  /// In zh, this message translates to:
  /// **'尚無足跡'**
  String get safetyNoFootprint;

  /// No description provided for @commsPathNoField.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入場域'**
  String get commsPathNoField;

  /// No description provided for @commsPathOffline.
  ///
  /// In zh, this message translates to:
  /// **'離線（近距離通訊未開啟）'**
  String get commsPathOffline;

  /// No description provided for @commsPathWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待鄰近裝置…'**
  String get commsPathWaiting;

  /// No description provided for @commsPathMesh.
  ///
  /// In zh, this message translates to:
  /// **'近距離網狀傳遞'**
  String get commsPathMesh;

  /// No description provided for @cloudOffline.
  ///
  /// In zh, this message translates to:
  /// **'雲端：離線'**
  String get cloudOffline;

  /// No description provided for @cloudConfigured.
  ///
  /// In zh, this message translates to:
  /// **'雲端：已設定（尚未啟用）'**
  String get cloudConfigured;

  /// No description provided for @gpsNoFix.
  ///
  /// In zh, this message translates to:
  /// **'尚無定位'**
  String get gpsNoFix;

  /// No description provided for @gpsReasonMovingRefresh.
  ///
  /// In zh, this message translates to:
  /// **'移動時更新'**
  String get gpsReasonMovingRefresh;

  /// No description provided for @gpsReasonMovingReuse.
  ///
  /// In zh, this message translates to:
  /// **'移動中沿用新定位'**
  String get gpsReasonMovingReuse;

  /// No description provided for @gpsReasonStationary.
  ///
  /// In zh, this message translates to:
  /// **'靜止沿用上次'**
  String get gpsReasonStationary;

  /// No description provided for @gpsReasonUnknown.
  ///
  /// In zh, this message translates to:
  /// **'沿用上次'**
  String get gpsReasonUnknown;

  /// No description provided for @gpsReasonManual.
  ///
  /// In zh, this message translates to:
  /// **'手動更新'**
  String get gpsReasonManual;

  /// No description provided for @gpsReasonUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'定位不可用'**
  String get gpsReasonUnavailable;

  /// No description provided for @beaconOff.
  ///
  /// In zh, this message translates to:
  /// **'已關閉'**
  String get beaconOff;

  /// No description provided for @beaconStatus.
  ///
  /// In zh, this message translates to:
  /// **'每 {secs} 秒 · 已更新 {count} 次{low}'**
  String beaconStatus(int secs, int count, String low);

  /// No description provided for @beaconLowSuffix.
  ///
  /// In zh, this message translates to:
  /// **'（低電量降頻）'**
  String get beaconLowSuffix;

  /// No description provided for @motionMoving.
  ///
  /// In zh, this message translates to:
  /// **'移動中'**
  String get motionMoving;

  /// No description provided for @motionStationary.
  ///
  /// In zh, this message translates to:
  /// **'靜止'**
  String get motionStationary;

  /// No description provided for @motionUnknown.
  ///
  /// In zh, this message translates to:
  /// **'尚未啟用'**
  String get motionUnknown;

  /// No description provided for @eventsTitle.
  ///
  /// In zh, this message translates to:
  /// **'事件'**
  String get eventsTitle;

  /// No description provided for @eventsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'危害、廣播、定點與系統事件'**
  String get eventsSubtitle;

  /// No description provided for @eventsRecentTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近事件'**
  String get eventsRecentTitle;

  /// No description provided for @eventsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'重新整理'**
  String get eventsRefresh;

  /// No description provided for @eventsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚無事件'**
  String get eventsEmpty;

  /// No description provided for @eventsRowType.
  ///
  /// In zh, this message translates to:
  /// **'類型 {type}'**
  String eventsRowType(String type);

  /// No description provided for @assistTitle.
  ///
  /// In zh, this message translates to:
  /// **'協助'**
  String get assistTitle;

  /// No description provided for @assistSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'離線協助與求助資源'**
  String get assistSubtitle;

  /// No description provided for @assistOfflineTitle.
  ///
  /// In zh, this message translates to:
  /// **'離線協助'**
  String get assistOfflineTitle;

  /// No description provided for @assistOfflineBody.
  ///
  /// In zh, this message translates to:
  /// **'離線求助資源與求救後續引導即將提供。需要緊急求救時，可隨時使用畫面上的全域求救鍵。'**
  String get assistOfflineBody;

  /// No description provided for @hazardCardTitleFormal.
  ///
  /// In zh, this message translates to:
  /// **'危害回報'**
  String get hazardCardTitleFormal;

  /// No description provided for @hazardCardTitleDebug.
  ///
  /// In zh, this message translates to:
  /// **'危害（HAZARD）'**
  String get hazardCardTitleDebug;

  /// No description provided for @hazardCardReport.
  ///
  /// In zh, this message translates to:
  /// **'回報危害'**
  String get hazardCardReport;

  /// No description provided for @hazardCardManualDebug.
  ///
  /// In zh, this message translates to:
  /// **'手動 HAZARD'**
  String get hazardCardManualDebug;

  /// No description provided for @hazardCardManualDebugTitle.
  ///
  /// In zh, this message translates to:
  /// **'手動 HAZARD（debug）'**
  String get hazardCardManualDebugTitle;

  /// No description provided for @hazardCardDebugSampleDesc.
  ///
  /// In zh, this message translates to:
  /// **'測試危害（debug）'**
  String get hazardCardDebugSampleDesc;

  /// No description provided for @hazardCardBodyFormal.
  ///
  /// In zh, this message translates to:
  /// **'附近的危害事件。回報時座標取自本機定位；無定位時無法回報，請先取得位置。'**
  String get hazardCardBodyFormal;

  /// No description provided for @hazardCardBodyDebug.
  ///
  /// In zh, this message translates to:
  /// **'收到的 typed HAZARD 事件（A3 接收側）。手動送出為 debug 占位（座標取本機 GPS，無定位則不送）。'**
  String get hazardCardBodyDebug;

  /// No description provided for @hazardCardDescLabel.
  ///
  /// In zh, this message translates to:
  /// **'描述（≤800B）'**
  String get hazardCardDescLabel;

  /// No description provided for @hazardCardNoLocation.
  ///
  /// In zh, this message translates to:
  /// **'目前沒有位置，請取得位置後再回報'**
  String get hazardCardNoLocation;

  /// No description provided for @hazardCardSentFormal.
  ///
  /// In zh, this message translates to:
  /// **'已回報危害「{type}」· 需已加入場域才會廣播'**
  String hazardCardSentFormal(String type);

  /// No description provided for @hazardCardSentDebug.
  ///
  /// In zh, this message translates to:
  /// **'HAZARD「{type}」已送出（id {id}） · 需已加入場域才會實際廣播'**
  String hazardCardSentDebug(String type, String id);

  /// No description provided for @hazardCardSendFailed.
  ///
  /// In zh, this message translates to:
  /// **'HAZARD 送出失敗: {error}'**
  String hazardCardSendFailed(String error);

  /// No description provided for @hazardCardEmpty.
  ///
  /// In zh, this message translates to:
  /// **'（尚無 HAZARD）'**
  String get hazardCardEmpty;

  /// No description provided for @hazardCardTypeFire.
  ///
  /// In zh, this message translates to:
  /// **'火災 FIRE'**
  String get hazardCardTypeFire;

  /// No description provided for @hazardCardTypeFlood.
  ///
  /// In zh, this message translates to:
  /// **'淹水 FLOOD'**
  String get hazardCardTypeFlood;

  /// No description provided for @hazardCardTypeCollapse.
  ///
  /// In zh, this message translates to:
  /// **'倒塌 COLLAPSE'**
  String get hazardCardTypeCollapse;

  /// No description provided for @hazardCardTypeChemical.
  ///
  /// In zh, this message translates to:
  /// **'化學 CHEMICAL'**
  String get hazardCardTypeChemical;

  /// No description provided for @hazardCardTypeRoadblock.
  ///
  /// In zh, this message translates to:
  /// **'路阻 ROADBLOCK'**
  String get hazardCardTypeRoadblock;

  /// No description provided for @hazardCardTypeOther.
  ///
  /// In zh, this message translates to:
  /// **'其他 OTHER'**
  String get hazardCardTypeOther;

  /// No description provided for @checkpointCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'CHECKPOINT（點名通過）'**
  String get checkpointCardTitle;

  /// No description provided for @checkpointCardManual.
  ///
  /// In zh, this message translates to:
  /// **'手動 CHECKPOINT'**
  String get checkpointCardManual;

  /// No description provided for @checkpointCardIdHint.
  ///
  /// In zh, this message translates to:
  /// **'點名點 / Field Node 錨點 id'**
  String get checkpointCardIdHint;

  /// No description provided for @checkpointCardBody.
  ///
  /// In zh, this message translates to:
  /// **'收到的點名通過事件（非 LWW，每次通過皆獨立保留）。'**
  String get checkpointCardBody;

  /// No description provided for @checkpointCardEmpty.
  ///
  /// In zh, this message translates to:
  /// **'（尚無 CHECKPOINT）'**
  String get checkpointCardEmpty;

  /// No description provided for @checkpointCardNoField.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入場域 — 請先在「場域」卡片加入或產生一個場域'**
  String get checkpointCardNoField;

  /// No description provided for @checkpointCardSent.
  ///
  /// In zh, this message translates to:
  /// **'CHECKPOINT「{id}」已送出（{count} peer）'**
  String checkpointCardSent(String id, int count);

  /// No description provided for @checkpointCardQueued.
  ///
  /// In zh, this message translates to:
  /// **'CHECKPOINT「{id}」已排入佇列（無在線 peer，深度 {depth}）'**
  String checkpointCardQueued(String id, int depth);

  /// No description provided for @checkpointCardAttempted.
  ///
  /// In zh, this message translates to:
  /// **'CHECKPOINT「{id}」已嘗試送出（{count} peer，無人接受）'**
  String checkpointCardAttempted(String id, int count);

  /// No description provided for @checkpointCardSendFailed.
  ///
  /// In zh, this message translates to:
  /// **'CHECKPOINT 送出失敗: {error}'**
  String checkpointCardSendFailed(String error);

  /// No description provided for @adminScopeField.
  ///
  /// In zh, this message translates to:
  /// **'本場域公告'**
  String get adminScopeField;

  /// No description provided for @adminScopeAll.
  ///
  /// In zh, this message translates to:
  /// **'全網公告'**
  String get adminScopeAll;

  /// No description provided for @adminScopeDefault.
  ///
  /// In zh, this message translates to:
  /// **'公告'**
  String get adminScopeDefault;

  /// No description provided for @adminExpiry.
  ///
  /// In zh, this message translates to:
  /// **'至 {time}'**
  String adminExpiry(String time);

  /// No description provided for @adminPublishTest.
  ///
  /// In zh, this message translates to:
  /// **'發測試 ADMIN 廣播'**
  String get adminPublishTest;

  /// No description provided for @adminTestMessage.
  ///
  /// In zh, this message translates to:
  /// **'測試管理廣播 {time}'**
  String adminTestMessage(String time);

  /// No description provided for @adminNoField.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入場域 — 請先加入或產生一個場域'**
  String get adminNoField;

  /// No description provided for @adminSent.
  ///
  /// In zh, this message translates to:
  /// **'ADMIN 廣播已送出（{count} peer）'**
  String adminSent(int count);

  /// No description provided for @adminQueued.
  ///
  /// In zh, this message translates to:
  /// **'ADMIN 廣播已排入佇列（深度 {depth}）'**
  String adminQueued(int depth);

  /// No description provided for @adminAttempted.
  ///
  /// In zh, this message translates to:
  /// **'ADMIN 廣播已嘗試送出（{count} peer）'**
  String adminAttempted(int count);

  /// No description provided for @adminSendFailed.
  ///
  /// In zh, this message translates to:
  /// **'ADMIN 廣播送出失敗: {error}'**
  String adminSendFailed(String error);

  /// No description provided for @sosTitle.
  ///
  /// In zh, this message translates to:
  /// **'緊急求救'**
  String get sosTitle;

  /// No description provided for @sosSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'長按求救鈕 1.5 秒，選擇狀態後 5 秒內可取消'**
  String get sosSubtitle;

  /// No description provided for @sosNearbyHeader.
  ///
  /// In zh, this message translates to:
  /// **'附近求救（{count}）'**
  String sosNearbyHeader(int count);

  /// No description provided for @sosNoneNearby.
  ///
  /// In zh, this message translates to:
  /// **'目前沒有收到求救訊號。'**
  String get sosNoneNearby;

  /// No description provided for @sosSending.
  ///
  /// In zh, this message translates to:
  /// **'求救傳送中…'**
  String get sosSending;

  /// No description provided for @sosTriggerTitle.
  ///
  /// In zh, this message translates to:
  /// **'發出求救'**
  String get sosTriggerTitle;

  /// No description provided for @sosTriggerBody.
  ///
  /// In zh, this message translates to:
  /// **'長按下方按鈕 1.5 秒，再選擇你的狀態。送出前還有 5 秒可取消。'**
  String get sosTriggerBody;

  /// No description provided for @sosHoldButton.
  ///
  /// In zh, this message translates to:
  /// **'按住求救'**
  String get sosHoldButton;

  /// No description provided for @sosCountdownTrapped.
  ///
  /// In zh, this message translates to:
  /// **'受困求救'**
  String get sosCountdownTrapped;

  /// No description provided for @sosCountdownInjured.
  ///
  /// In zh, this message translates to:
  /// **'受傷求救'**
  String get sosCountdownInjured;

  /// No description provided for @sosCountdownHint.
  ///
  /// In zh, this message translates to:
  /// **'秒後送出 — 仍可取消'**
  String get sosCountdownHint;

  /// No description provided for @sosActiveTitle.
  ///
  /// In zh, this message translates to:
  /// **'你已發出求救'**
  String get sosActiveTitle;

  /// No description provided for @sosChipTrapped.
  ///
  /// In zh, this message translates to:
  /// **'受困'**
  String get sosChipTrapped;

  /// No description provided for @sosChipInjured.
  ///
  /// In zh, this message translates to:
  /// **'受傷'**
  String get sosChipInjured;

  /// No description provided for @sosMarkSafe.
  ///
  /// In zh, this message translates to:
  /// **'我安全了'**
  String get sosMarkSafe;

  /// No description provided for @sosChooseStatus.
  ///
  /// In zh, this message translates to:
  /// **'選擇你的狀態'**
  String get sosChooseStatus;

  /// No description provided for @sosSeverityTrapped.
  ///
  /// In zh, this message translates to:
  /// **'受困（最高優先）'**
  String get sosSeverityTrapped;

  /// No description provided for @sosMarkSafeNoField.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入場域 — 無法送出狀態更新'**
  String get sosMarkSafeNoField;

  /// No description provided for @sosMarkSafeSent.
  ///
  /// In zh, this message translates to:
  /// **'已送出「我安全了」'**
  String get sosMarkSafeSent;

  /// No description provided for @sosResolvedChip.
  ///
  /// In zh, this message translates to:
  /// **'已解除'**
  String get sosResolvedChip;

  /// No description provided for @sosOutcomeSent.
  ///
  /// In zh, this message translates to:
  /// **'已送出。'**
  String get sosOutcomeSent;

  /// No description provided for @sosOutcomeNoField.
  ///
  /// In zh, this message translates to:
  /// **'尚未加入場域 — 求救未送出，請先加入場域。'**
  String get sosOutcomeNoField;

  /// No description provided for @sosOutcomeAccepted.
  ///
  /// In zh, this message translates to:
  /// **'已送達 {count} 個鄰近裝置。'**
  String sosOutcomeAccepted(int count);

  /// No description provided for @sosOutcomeQueued.
  ///
  /// In zh, this message translates to:
  /// **'已排入佇列（無在線鄰近裝置，深度 {depth}）。'**
  String sosOutcomeQueued(int depth);

  /// No description provided for @sosOutcomeAttempted.
  ///
  /// In zh, this message translates to:
  /// **'已嘗試送出（{count} 個，暫無人接收）。'**
  String sosOutcomeAttempted(int count);

  /// No description provided for @lastSeenTitle.
  ///
  /// In zh, this message translates to:
  /// **'最後可信位置'**
  String get lastSeenTitle;

  /// No description provided for @lastSeenSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'依足跡 / 點名通過推估，非即時定位'**
  String get lastSeenSubtitle;

  /// No description provided for @lastSeenNeedLocalPosition.
  ///
  /// In zh, this message translates to:
  /// **'需要本機位置才能顯示相對方位'**
  String get lastSeenNeedLocalPosition;

  /// No description provided for @lastSeenToggleList.
  ///
  /// In zh, this message translates to:
  /// **'列表'**
  String get lastSeenToggleList;

  /// No description provided for @lastSeenToggleRadar.
  ///
  /// In zh, this message translates to:
  /// **'雷達'**
  String get lastSeenToggleRadar;

  /// No description provided for @lastSeenEmpty.
  ///
  /// In zh, this message translates to:
  /// **'尚無位置證據 — 收到足跡（PRESENCE）或點名通過（CHECKPOINT）後，這裡會列出每人的最後可信位置。'**
  String get lastSeenEmpty;

  /// No description provided for @lastSeenUncertainty.
  ///
  /// In zh, this message translates to:
  /// **'誤差 ~{meters} m'**
  String lastSeenUncertainty(int meters);

  /// No description provided for @lastSeenAnchor.
  ///
  /// In zh, this message translates to:
  /// **'錨點 {id}'**
  String lastSeenAnchor(String id);

  /// No description provided for @confidenceHigh.
  ///
  /// In zh, this message translates to:
  /// **'可信度 高'**
  String get confidenceHigh;

  /// No description provided for @confidenceMedium.
  ///
  /// In zh, this message translates to:
  /// **'可信度 中'**
  String get confidenceMedium;

  /// No description provided for @confidenceLow.
  ///
  /// In zh, this message translates to:
  /// **'可信度 低'**
  String get confidenceLow;

  /// No description provided for @radarCaption.
  ///
  /// In zh, this message translates to:
  /// **'北朝上 · 外環 {range} · 圓心為本機（最後可信位置投影）'**
  String radarCaption(String range);
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SEn();
    case 'zh':
      return SZh();
  }

  throw FlutterError(
      'S.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
