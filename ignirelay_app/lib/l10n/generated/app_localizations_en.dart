// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SEn extends S {
  SEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'IgniRelay';

  @override
  String get mainStartupLoading => 'IgniRelay Starting...';

  @override
  String get mainBluetoothDialogTitle => 'Bluetooth Required';

  @override
  String get mainBluetoothDialogContent =>
      'IgniRelay uses Bluetooth to build an offline Mesh network\nfor transmitting SOS signals and supply matching.\n\nPlease enable Bluetooth to activate full functionality.';

  @override
  String get mainBluetoothDialogCancel => 'Later';

  @override
  String get mainBluetoothDialogConfirm => 'Enable Bluetooth';

  @override
  String mainBleFailSnack(String error) {
    return 'BLE Mesh failed to start: $error';
  }

  @override
  String get mainPermissionSnack =>
      'Bluetooth and location permissions are required for Mesh networking';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get tierLabel1Standard => 'Standard Mode (Tier 1)';

  @override
  String get tierLabel1Force => 'Full Speed Mode (Tier 1)';

  @override
  String get tierLabel2EcoRelay => 'Eco Relay Mode (Tier 2)';

  @override
  String get tierLabel3UltraEco => 'Ultra Eco Mode (Tier 3)';

  @override
  String get shellTabSafety => 'Safety';

  @override
  String get shellTabPosition => 'Location';

  @override
  String get shellTabEvents => 'Events';

  @override
  String get shellTabAssist => 'Assist';

  @override
  String get shellTabMine => 'Me';

  @override
  String get noFieldTitle => 'IgniRelay';

  @override
  String get noFieldSubtitle =>
      'Join or create a field to become visible, call for help, and leave a last known trail.';

  @override
  String get noFieldJoin => 'Join field';

  @override
  String get noFieldCreate => 'Create field';

  @override
  String get noFieldPreview => 'Guided preview';

  @override
  String get myTitle => 'Me';

  @override
  String get mySubtitle => 'Field, identity & settings';

  @override
  String get myFieldSection => 'Field';

  @override
  String get myFieldManage => 'Manage field';

  @override
  String myCurrentField(String name) {
    return 'Current field: $name';
  }

  @override
  String get myFieldUnnamed => '(unnamed)';

  @override
  String myFieldJoinedCount(int count) {
    return 'Joined $count';
  }

  @override
  String get myNoField => 'No field joined yet.';

  @override
  String get myRoleSection => 'Identity & role';

  @override
  String get myRoleEmptyHint => 'Shown after you join or create a field.';

  @override
  String get myRoleOwnerDesc =>
      'You created this field; you can share the join QR.';

  @override
  String get myRoleParticipantDesc => 'You have joined this field.';

  @override
  String get roleHost => 'Host';

  @override
  String get roleMember => 'Member';

  @override
  String get myPermissionSection => 'Permission status';

  @override
  String get myComingSoon => 'Coming soon';

  @override
  String get myDeveloperDiagnostics => 'Developer diagnostics';

  @override
  String get settingsSection => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTextSize => 'Text size';

  @override
  String get settingsTextSizeStandard => 'Standard';

  @override
  String get settingsTextSizeLarge => 'Large';

  @override
  String get settingsTextSizeXLarge => 'X-Large';

  @override
  String get settingsTextSizeHuge => 'Huge';

  @override
  String get fieldTitle => 'Field';

  @override
  String get fieldSubtitle => 'Join a field to send and receive events';

  @override
  String get fieldNoneTitle => 'Not in any field yet';

  @override
  String get fieldNoneBody =>
      'Scan the host\'s field QR, enter a join code, or create your own field.';

  @override
  String get fieldUnnamed => '(unnamed field)';

  @override
  String get fieldActiveChip => 'Active';

  @override
  String get fieldScanJoin => 'Scan to join';

  @override
  String get fieldEnterCode => 'Enter code';

  @override
  String get fieldCreateNew => 'Create field';

  @override
  String fieldJoinedHeader(int count) {
    return 'Joined fields ($count)';
  }

  @override
  String get fieldShowQr => 'Show QR';

  @override
  String get fieldLeave => 'Leave field';

  @override
  String fieldCreateFailed(String error) {
    return 'Couldn\'t create field: $error';
  }

  @override
  String get fieldSecretNotFound =>
      'This field\'s key wasn\'t found, so the QR can\'t be shown';

  @override
  String get fieldCodeTitle => 'Enter field code';

  @override
  String get fieldCodeBody =>
      'Paste an IGNI1 field code, or enter the 64-character hex field key.';

  @override
  String get fieldCodeHint => 'IGNI1:… or a1b2c3…';

  @override
  String get fieldCancel => 'Cancel';

  @override
  String get fieldJoin => 'Join';

  @override
  String get fieldScannedName => 'Scanned field';

  @override
  String get fieldCodeUnrecognized =>
      'Unrecognized code: it must be an IGNI1 code or 64 hex characters';

  @override
  String fieldDefaultNamePrefix(String prefix) {
    return 'Field-$prefix';
  }

  @override
  String fieldJoinedSnack(String id) {
    return 'Joined field $id…';
  }

  @override
  String fieldJoinFailed(String error) {
    return 'Couldn\'t join field: $error';
  }

  @override
  String get fieldLeaveTitle => 'Leave field?';

  @override
  String fieldLeaveBody(String name) {
    return 'About to leave \"$name\". This can\'t be undone — the field\'s key is removed from this device, and you\'ll need to scan or enter the code again to rejoin.';
  }

  @override
  String get fieldLeaveConfirm => 'Leave';

  @override
  String get fieldLeftSnack => 'Left the field';

  @override
  String fieldLeaveFailed(String error) {
    return 'Couldn\'t leave field: $error';
  }

  @override
  String get fieldCreateTitle => 'Create field';

  @override
  String get fieldNameLabel => 'Field name';

  @override
  String get fieldNameHint => 'e.g. Taipei Station shelter';

  @override
  String get fieldCreateConfirm => 'Create';

  @override
  String get fieldDefaultName => 'New field';

  @override
  String get fieldErrEmpty => 'The code is empty';

  @override
  String get fieldErrBadPrefix =>
      'This isn\'t an IgniRelay field code (prefix mismatch)';

  @override
  String get fieldErrTooFewSegments => 'The code is incomplete';

  @override
  String get fieldErrBadSecret => 'The code\'s field key is malformed';

  @override
  String get fieldErrBadCloudUrl =>
      'The code\'s cloud URL is invalid (https:// only)';

  @override
  String get fieldErrStaffWithoutCloud =>
      'Malformed code: it has a staff token but no cloud URL';

  @override
  String get fieldErrMalformed => 'The code is corrupted and can\'t be parsed';

  @override
  String get fieldScanBack => 'Back';

  @override
  String get fieldScanTitle => 'Scan field QR';

  @override
  String get fieldScanHint =>
      'Point at the host\'s field QR to join automatically';

  @override
  String get fieldScanReject =>
      'That\'s not an IgniRelay field QR — try another';

  @override
  String get fieldScanNoCameraTitle => 'Can\'t open the camera';

  @override
  String get fieldScanNoCameraBody =>
      'Check that camera permission is granted, or use \"Enter code\" to join a field instead.';

  @override
  String get fieldQrTitle => 'Field QR';

  @override
  String get fieldQrSubtitle => 'Have others scan this to join the same field';

  @override
  String get fieldQrDebugWarning =>
      '(debug) This code contains the field key — don\'t share it:';

  @override
  String get fieldQrDone => 'Done';

  @override
  String get previewModeSubtitle => 'Demo mode · nothing is sent';

  @override
  String get previewBadge => 'Demo data';

  @override
  String get previewBack => 'Back';

  @override
  String get previewPrev => 'Previous';

  @override
  String get previewNext => 'Next';

  @override
  String get previewDemoChip => 'Demo';

  @override
  String get previewJoinIntro =>
      'Scan the host\'s QR or enter a key to join a field. The field decides who you connect with — only people in the same field can see each other.';

  @override
  String get previewSafetyTitle => 'Safety: be seen + call for help';

  @override
  String get previewSafetyIntro =>
      'After you join, the app periodically leaves your footprint so people in the field know you\'re still around and roughly where. Press and hold to send an SOS when you need it.';

  @override
  String get previewSafetyFootprintTitle => 'Automatic footprint (be seen)';

  @override
  String get previewSafetyFootprintBody =>
      'Saves power when you\'re still, updates more often when you move. No need to watch your phone — others can still see your last position.';

  @override
  String get previewSafetySosTitle => 'SOS';

  @override
  String get previewSafetySosBody =>
      'Press and hold the SOS button, then choose red (trapped) or yellow (injured). You get 5 seconds to cancel before it sends. (The demo never actually sends.)';

  @override
  String get previewPositionTitle => 'Location: last trusted position';

  @override
  String get previewPositionIntro =>
      'See nearby members\' last trusted position and relative bearing. The radar is fixed north-up; closer to the center means closer to you. (This shows demo data.)';

  @override
  String previewFootprintLine(String ago) {
    return 'Last trusted position · $ago';
  }

  @override
  String get previewEventsTitle => 'Events: hazards / broadcasts / check-ins';

  @override
  String get previewEventsIntro =>
      'Important messages collect under Events: hazard alerts, admin broadcasts, and safety check-ins, so you can size up the situation fast.';

  @override
  String get previewAssistTitle => 'Assist + works offline';

  @override
  String get previewAssistIntro =>
      'Match needs and offers under Assist. Most importantly — with no network, the app keeps working by relaying through nearby devices.';

  @override
  String get previewAssistMatchTitle => 'Assist matching';

  @override
  String get previewAssistMatchBody =>
      'Post a need or answer someone else\'s, so resources move locally within the field.';

  @override
  String get previewAssistOfflineTitle => 'Offline fallback';

  @override
  String get previewAssistOfflineBody =>
      'With no cell tower or network, messages hop device to device nearby; when coverage returns they\'re sent automatically — and it never makes up a position.';

  @override
  String get previewToneSos => 'SOS';

  @override
  String get previewToneWarn => 'Hazard';

  @override
  String get previewToneInfo => 'Broadcast';

  @override
  String get previewToneOk => 'Safe';

  @override
  String get previewToneNeutral => 'Event';

  @override
  String get previewFieldLabel => 'Demo field · DEMO-FIELD';

  @override
  String previewAlias(String alias) {
    return 'Alias $alias';
  }

  @override
  String get previewFpAgo1 => '1 min ago';

  @override
  String get previewFpAgo4 => '4 min ago';

  @override
  String get previewFpAgoTrapped => 'Trapped · 2 min ago';

  @override
  String get previewSosTitle => 'SOS · Trapped';

  @override
  String get previewSosAgo => '2 min ago';

  @override
  String get previewHazardTitle => 'Hazard · Fire (FIRE)';

  @override
  String get previewHazardDetail => 'sev 2 · heavy smoke at the alley';

  @override
  String get previewHazardAgo => '6 min ago';

  @override
  String get previewBroadcastTitle => 'Admin broadcast';

  @override
  String get previewBroadcastDetail => 'Assembly point moved to the north exit';

  @override
  String get previewBroadcastAgo => '10 min ago';

  @override
  String get previewCheckpointTitle => 'Check-in · Safe';

  @override
  String get previewCheckpointAgo => '12 min ago';

  @override
  String get commonSend => 'Send';

  @override
  String get noCoordinate => 'No coordinates';

  @override
  String get noCoordinateParen => '(no coordinates)';

  @override
  String get timeJustNow => 'just now';

  @override
  String timeAgoSeconds(int seconds) {
    return '${seconds}s ago';
  }

  @override
  String timeAgoMinutes(int minutes) {
    return '$minutes min ago';
  }

  @override
  String timeAgoHours(int hours) {
    return '${hours}h ago';
  }

  @override
  String timeAgoDays(int days) {
    return '${days}d ago';
  }

  @override
  String get safetyTitle => 'My safety';

  @override
  String get safetySubtitle => 'Comms & footprint';

  @override
  String safetyToggleFailed(String error) {
    return 'Failed to switch comms: $error';
  }

  @override
  String get safetyUpdateNoField =>
      'Not in a field yet — join or create one from the My tab.';

  @override
  String safetyUpdateSent(int count) {
    return 'Footprint updated ($count nearby devices)';
  }

  @override
  String get safetyUpdateQueued =>
      'Footprint queued; it will send once nearby devices come online';

  @override
  String get safetyUpdateAttempted => 'Footprint update attempted';

  @override
  String safetyUpdateFailed(String error) {
    return 'Failed to update footprint: $error';
  }

  @override
  String get safetyCommsOn => 'Nearby comms: on';

  @override
  String get safetyCommsOff => 'Nearby comms: off';

  @override
  String get safetyTurnOn => 'Turn on';

  @override
  String get safetyTurnOff => 'Turn off';

  @override
  String safetyCurrentPath(String path) {
    return 'Current path: $path';
  }

  @override
  String get safetyStatPeers => 'Nearby';

  @override
  String get safetyStatSent => 'Sent';

  @override
  String get safetyStatReceived => 'Received';

  @override
  String get safetyStatQueued => 'Queued';

  @override
  String safetyLastFootprint(String time) {
    return 'Last footprint: $time';
  }

  @override
  String get safetyFootprintTitle => 'Footprint';

  @override
  String get safetyFootprintBody =>
      'Let nearby people see your last trusted position.';

  @override
  String get safetyUpdateNow => 'Update footprint now';

  @override
  String get safetyAutoBeacon => 'Auto footprint beacon';

  @override
  String safetyMotion(String state) {
    return 'Motion: $state';
  }

  @override
  String safetyGpsFix(String age) {
    return 'GPS fix: $age';
  }

  @override
  String safetyGpsPolicy(String reason) {
    return 'Fix policy: $reason';
  }

  @override
  String get safetyRecentTitle => 'Recent footprints';

  @override
  String get safetyNoFootprint => 'No footprints yet';

  @override
  String get commsPathNoField => 'Not in a field yet';

  @override
  String get commsPathOffline => 'Offline (nearby comms off)';

  @override
  String get commsPathWaiting => 'Waiting for nearby devices…';

  @override
  String get commsPathMesh => 'Nearby mesh relay';

  @override
  String get cloudOffline => 'Cloud: offline';

  @override
  String get cloudConfigured => 'Cloud: configured (not active yet)';

  @override
  String get gpsNoFix => 'No fix yet';

  @override
  String get gpsReasonMovingRefresh => 'Refresh while moving';

  @override
  String get gpsReasonMovingReuse => 'Moving, reuse fresh fix';

  @override
  String get gpsReasonStationary => 'Stationary, reuse last';

  @override
  String get gpsReasonUnknown => 'Reuse last';

  @override
  String get gpsReasonManual => 'Manual update';

  @override
  String get gpsReasonUnavailable => 'Location unavailable';

  @override
  String get beaconOff => 'Off';

  @override
  String beaconStatus(int secs, int count, String low) {
    return 'Every ${secs}s · sent $count×$low';
  }

  @override
  String get beaconLowSuffix => ' (low battery, slowed)';

  @override
  String get motionMoving => 'Moving';

  @override
  String get motionStationary => 'Stationary';

  @override
  String get motionUnknown => 'Not enabled yet';

  @override
  String get eventsTitle => 'Events';

  @override
  String get eventsSubtitle =>
      'Hazards, broadcasts, checkpoints and system events';

  @override
  String get eventsRecentTitle => 'Recent events';

  @override
  String get eventsRefresh => 'Refresh';

  @override
  String get eventsEmpty => 'No events yet';

  @override
  String eventsRowType(String type) {
    return 'Type $type';
  }

  @override
  String get assistTitle => 'Help';

  @override
  String get assistSubtitle => 'Offline help and resources';

  @override
  String get assistOfflineTitle => 'Offline help';

  @override
  String get assistOfflineBody =>
      'Offline help resources and post-SOS guidance are coming soon. For an emergency, you can always use the on-screen global SOS button.';

  @override
  String get hazardCardTitleFormal => 'Hazard report';

  @override
  String get hazardCardTitleDebug => 'Hazard (HAZARD)';

  @override
  String get hazardCardReport => 'Report hazard';

  @override
  String get hazardCardManualDebug => 'Manual HAZARD';

  @override
  String get hazardCardManualDebugTitle => 'Manual HAZARD (debug)';

  @override
  String get hazardCardDebugSampleDesc => 'Test hazard (debug)';

  @override
  String get hazardCardBodyFormal =>
      'Nearby hazard events. Reports use your device\'s location; without a fix you can\'t report — get a location first.';

  @override
  String get hazardCardBodyDebug =>
      'Received typed HAZARD events (A3 receive side). Manual send is a debug stand-in (uses device GPS; no fix → no send).';

  @override
  String get hazardCardDescLabel => 'Description (≤800B)';

  @override
  String get hazardCardNoLocation =>
      'No location right now — get a fix before reporting';

  @override
  String hazardCardSentFormal(String type) {
    return 'Hazard \"$type\" reported · only broadcasts after you join a field';
  }

  @override
  String hazardCardSentDebug(String type, String id) {
    return 'HAZARD \"$type\" sent (id $id) · only broadcasts after you join a field';
  }

  @override
  String hazardCardSendFailed(String error) {
    return 'HAZARD send failed: $error';
  }

  @override
  String get hazardCardEmpty => '(no HAZARD yet)';

  @override
  String get hazardCardTypeFire => 'Fire (FIRE)';

  @override
  String get hazardCardTypeFlood => 'Flood (FLOOD)';

  @override
  String get hazardCardTypeCollapse => 'Collapse (COLLAPSE)';

  @override
  String get hazardCardTypeChemical => 'Chemical (CHEMICAL)';

  @override
  String get hazardCardTypeRoadblock => 'Roadblock (ROADBLOCK)';

  @override
  String get hazardCardTypeOther => 'Other (OTHER)';

  @override
  String get checkpointCardTitle => 'CHECKPOINT (roll-call)';

  @override
  String get checkpointCardManual => 'Manual CHECKPOINT';

  @override
  String get checkpointCardIdHint => 'Roll-call point / Field Node anchor id';

  @override
  String get checkpointCardBody =>
      'Received roll-call crossings (not LWW; each crossing is kept independently).';

  @override
  String get checkpointCardEmpty => '(no CHECKPOINT yet)';

  @override
  String get checkpointCardNoField =>
      'Not in a field yet — join or create one from the Field card first';

  @override
  String checkpointCardSent(String id, int count) {
    return 'CHECKPOINT \"$id\" sent ($count peers)';
  }

  @override
  String checkpointCardQueued(String id, int depth) {
    return 'CHECKPOINT \"$id\" queued (no online peers, depth $depth)';
  }

  @override
  String checkpointCardAttempted(String id, int count) {
    return 'CHECKPOINT \"$id\" attempted ($count peers, none accepted)';
  }

  @override
  String checkpointCardSendFailed(String error) {
    return 'CHECKPOINT send failed: $error';
  }

  @override
  String get adminScopeField => 'Field announcement';

  @override
  String get adminScopeAll => 'Network-wide announcement';

  @override
  String get adminScopeDefault => 'Announcement';

  @override
  String adminExpiry(String time) {
    return 'Until $time';
  }

  @override
  String get adminPublishTest => 'Send test ADMIN broadcast';

  @override
  String adminTestMessage(String time) {
    return 'Test admin broadcast $time';
  }

  @override
  String get adminNoField => 'Not in a field yet — join or create one first';

  @override
  String adminSent(int count) {
    return 'ADMIN broadcast sent ($count peers)';
  }

  @override
  String adminQueued(int depth) {
    return 'ADMIN broadcast queued (depth $depth)';
  }

  @override
  String adminAttempted(int count) {
    return 'ADMIN broadcast attempted ($count peers)';
  }

  @override
  String adminSendFailed(String error) {
    return 'ADMIN broadcast send failed: $error';
  }

  @override
  String get sosTitle => 'Emergency SOS';

  @override
  String get sosSubtitle =>
      'Hold the SOS button for 1.5s; after choosing a status you have 5s to cancel';

  @override
  String sosNearbyHeader(int count) {
    return 'Nearby SOS ($count)';
  }

  @override
  String get sosNoneNearby => 'No SOS signals received right now.';

  @override
  String get sosSending => 'Sending SOS…';

  @override
  String get sosTriggerTitle => 'Send an SOS';

  @override
  String get sosTriggerBody =>
      'Hold the button below for 1.5s, then choose your status. You still have 5s to cancel before it sends.';

  @override
  String get sosHoldButton => 'Hold to call for help';

  @override
  String get sosCountdownTrapped => 'Trapped SOS';

  @override
  String get sosCountdownInjured => 'Injured SOS';

  @override
  String get sosCountdownHint =>
      'seconds until it sends — you can still cancel';

  @override
  String get sosActiveTitle => 'You\'ve sent an SOS';

  @override
  String get sosChipTrapped => 'Trapped';

  @override
  String get sosChipInjured => 'Injured';

  @override
  String get sosMarkSafe => 'I\'m safe now';

  @override
  String get sosChooseStatus => 'Choose your status';

  @override
  String get sosSeverityTrapped => 'Trapped (highest priority)';

  @override
  String get sosMarkSafeNoField =>
      'Not in a field yet — can\'t send a status update';

  @override
  String get sosMarkSafeSent => 'Sent \"I\'m safe now\"';

  @override
  String get sosResolvedChip => 'Resolved';

  @override
  String get sosOutcomeSent => 'Sent.';

  @override
  String get sosOutcomeNoField =>
      'Not in a field yet — the SOS wasn\'t sent; join a field first.';

  @override
  String sosOutcomeAccepted(int count) {
    return 'Delivered to $count nearby devices.';
  }

  @override
  String sosOutcomeQueued(int depth) {
    return 'Queued (no nearby devices online, depth $depth).';
  }

  @override
  String sosOutcomeAttempted(int count) {
    return 'Send attempted ($count; nobody received yet).';
  }

  @override
  String get lastSeenTitle => 'Last trusted position';

  @override
  String get lastSeenSubtitle =>
      'Estimated from footprints / roll-calls, not live tracking';

  @override
  String get lastSeenNeedLocalPosition =>
      'Your own position is needed to show relative bearings';

  @override
  String get lastSeenToggleList => 'List';

  @override
  String get lastSeenToggleRadar => 'Radar';

  @override
  String get lastSeenEmpty =>
      'No position evidence yet — once footprints (PRESENCE) or roll-calls (CHECKPOINT) arrive, each person\'s last trusted position appears here.';

  @override
  String lastSeenUncertainty(int meters) {
    return '±~$meters m';
  }

  @override
  String lastSeenAnchor(String id) {
    return 'Anchor $id';
  }

  @override
  String get confidenceHigh => 'Confidence: high';

  @override
  String get confidenceMedium => 'Confidence: medium';

  @override
  String get confidenceLow => 'Confidence: low';

  @override
  String radarCaption(String range) {
    return 'North up · outer ring $range · centre is you (last trusted position)';
  }
}
