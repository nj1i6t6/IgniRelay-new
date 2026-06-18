import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// 全域 GPS 定位服務 (Singleton)
/// 提供目前位置、距離計算和方位角。
///
/// UI-F5b / §4.2 motion-aware location: this service NO LONGER keeps a
/// high-accuracy [Geolocator.getPositionStream] hot in the background. It takes
/// ONE initial fix at [init], then refreshes ON DEMAND via [refreshOnce] — the
/// presence beacon calls it only when moving & the last fix is stale, and manual
/// safety events call it with a short timeout. While stationary nothing refreshes
/// (no hot GPS). [lastFixAt] records when the current fix was obtained so callers
/// can reason about its age.
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  LatLng? _currentLocation;
  DateTime? _lastFixAt;
  bool _initialized = false;

  // Reassignable so the singleton can self-heal after [dispose] closes it — see
  // [_ensureLocationControllerOpen] (Owner UI-F5b-polish refinement).
  StreamController<LatLng> _locationController =
      StreamController<LatLng>.broadcast();

  // ── Test seams ────────────────────────────────────────────────────────────
  // The Geolocator calls go through these (mapped to plain LatLng so tests need
  // no `Position` construction) so `refreshOnce` / fix-time / "init takes no
  // continuous subscription" are unit-testable without the platform plugin.
  // [resetForTest] restores the real Geolocator + clears singleton state so the
  // shared instance never leaks across tests (Owner boundary 7).
  @visibleForTesting
  Future<bool> Function() isServiceEnabledFn = Geolocator.isLocationServiceEnabled;
  @visibleForTesting
  Future<LocationPermission> Function() checkPermissionFn =
      Geolocator.checkPermission;
  @visibleForTesting
  Future<LatLng?> Function() getLastKnownFn = _defaultGetLastKnown;
  @visibleForTesting
  Future<LatLng?> Function() getCurrentFn = _defaultGetCurrent;
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  static Future<LatLng?> _defaultGetLastKnown() async {
    final p = await Geolocator.getLastKnownPosition();
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  static Future<LatLng?> _defaultGetCurrent() async {
    final p =
        await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    return LatLng(p.latitude, p.longitude);
  }

  /// 目前已知位置 (可能為 null)
  LatLng? get currentLocation => _currentLocation;

  /// 位置是否可用
  bool get hasLocation => _currentLocation != null;

  /// When the current fix was obtained (null = no fix yet). Drives §4.2 fix-age
  /// decisions and the A11 "last GPS fix age" diagnostic.
  DateTime? get lastFixAt => _lastFixAt;

  /// 是否已完成 init()
  bool get isInitialized => _initialized;

  /// 位置更新 stream（broadcast）。每次取得新 fix（init 或 [refreshOnce]）會 push。
  /// 注意：UI-F5b 起不再有背景連續 high-accuracy stream，僅在 refresh 時推送。
  Stream<LatLng> get locationStream {
    _ensureLocationControllerOpen();
    return _locationController.stream;
  }

  /// GPS 不可用原因 (null = 正常可用或尚未檢查)
  String? _unavailableReason;
  String? get unavailableReason => _unavailableReason;

  /// GPS 是否永久拒絕 (需要到系統設定手動開啟)
  bool _permDeniedForever = false;
  bool get permDeniedForever => _permDeniedForever;

  /// GPS 首次就緒時的回呼（用於自動加入聊天室等）
  void Function()? onFirstFix;

  /// Rebuild the broadcast controller if it was closed (e.g. by [dispose]) so the
  /// shared singleton self-heals: a fix obtained after dispose still publishes and
  /// a fresh listener gets a live stream. Called before every add/listen — events
  /// are never silently dropped after dispose (Owner UI-F5b-polish refinement).
  void _ensureLocationControllerOpen() {
    if (_locationController.isClosed) {
      _locationController = StreamController<LatLng>.broadcast();
    }
  }

  void _adoptFix(LatLng loc) {
    final wasNull = _currentLocation == null;
    _currentLocation = loc;
    _lastFixAt = now();
    _ensureLocationControllerOpen();
    _locationController.add(loc);
    if (_unavailableReason != null) {
      _unavailableReason = null;
    }
    if (wasNull && onFirstFix != null) {
      onFirstFix!();
      onFirstFix = null; // 只觸發一次
    }
  }

  /// 初始化 GPS（若已初始化則 no-op）。取得一次起始 fix；**不**掛背景連續 stream
  /// （§4.2：靜止時不熱跑 GPS — 之後改由 [refreshOnce] 按需更新）。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _unavailableReason = null;
    _permDeniedForever = false;

    try {
      final serviceEnabled = await isServiceEnabledFn();
      if (!serviceEnabled) {
        _unavailableReason = 'GPS 服務未開啟，請前往系統設定啟用定位功能';
        debugPrint('[LocationService] GPS 服務未開啟');
        return;
      }

      final perm = await checkPermissionFn();
      if (perm == LocationPermission.deniedForever) {
        _permDeniedForever = true;
        _unavailableReason = 'GPS 權限已被永久拒絕，請前往系統設定 → 應用程式 → 授予定位權限';
        debugPrint('[LocationService] GPS 權限被永久拒絕');
        return;
      }
      if (perm == LocationPermission.denied) {
        _unavailableReason = '請授予 GPS 定位權限以取得更準確的媒合結果';
        debugPrint('[LocationService] GPS 權限被拒（由 _requestPermissions 統一處理）');
        return;
      }

      // 先嘗試取得上次已知位置（瞬間回傳，GPS 冷啟動前先有座標可用）
      try {
        final lastLoc = await getLastKnownFn();
        if (lastLoc != null) {
          _adoptFix(lastLoc);
          debugPrint('[LocationService] 使用上次已知位置');
        }
      } catch (e) {
        debugPrint('[LocationService] getLastKnownPosition 失敗: $e');
      }

      // 取得一次精確位置（20 秒 timeout，低階機 GPS 冷啟動需要較長時間）。
      // UI-F5b：這是起始 fix，之後不再掛連續 stream。
      try {
        final loc =
            await getCurrentFn().timeout(const Duration(seconds: 20));
        if (loc != null) _adoptFix(loc);
      } on TimeoutException {
        debugPrint('[LocationService] getCurrentPosition 逾時 (20s)');
        if (_currentLocation == null) {
          _unavailableReason = 'GPS 定位逾時，請確認已開啟定位功能或移到開闊處';
        }
      } catch (e) {
        debugPrint('[LocationService] getCurrentPosition 失敗: $e');
        if (_currentLocation == null) {
          _unavailableReason = 'GPS 定位失敗: $e';
        }
      }
    } catch (e) {
      debugPrint('[LocationService] 初始化失敗: $e');
      _unavailableReason = '定位服務初始化失敗: $e';
    }
  }

  Future<LatLng?>? _inFlightRefresh;

  /// One-shot high-accuracy fix on demand (§4.2). Returns the fresh fix, or the
  /// last-known fix on timeout/failure (which it leaves intact). NEVER throws —
  /// safe to `await` directly inside a publish path. Concurrent calls share one
  /// in-flight request (dedup), so the beacon + a manual event don't double-hit
  /// the GPS.
  Future<LatLng?> refreshOnce({
    Duration timeout = const Duration(seconds: 8),
  }) {
    final existing = _inFlightRefresh;
    if (existing != null) return existing;
    final future = _doRefresh(timeout);
    _inFlightRefresh = future;
    return future;
  }

  Future<LatLng?> _doRefresh(Duration timeout) async {
    try {
      final loc = await getCurrentFn().timeout(timeout);
      if (loc != null) _adoptFix(loc);
      return _currentLocation;
    } catch (e) {
      debugPrint('[LocationService] refreshOnce 失敗（沿用上次 fix）: $e');
      return _currentLocation; // last-known left intact
    } finally {
      _inFlightRefresh = null;
    }
  }

  /// 計算兩點間 Haversine 距離 (公尺)
  static double haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final h = sinDLat * sinDLat +
        cos(_toRad(a.latitude)) * cos(_toRad(b.latitude)) * sinDLng * sinDLng;
    return R * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  /// 計算從 a 到 b 的方位角 (degrees, 0=北, 90=東)
  static double bearing(LatLng from, LatLng to) {
    final dLng = _toRad(to.longitude - from.longitude);
    final lat1 = _toRad(from.latitude);
    final lat2 = _toRad(to.latitude);
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final brng = atan2(y, x) * 180 / pi;
    return (brng + 360) % 360;
  }

  /// 方位角轉中文方向
  static String bearingToDirection(double deg) {
    if (deg >= 337.5 || deg < 22.5) return '北方';
    if (deg < 67.5) return '東北方';
    if (deg < 112.5) return '東方';
    if (deg < 157.5) return '東南方';
    if (deg < 202.5) return '南方';
    if (deg < 247.5) return '西南方';
    if (deg < 292.5) return '西方';
    return '西北方';
  }

  /// 距離格式化
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.toInt()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  /// 歸一化距離用於評分 (0~1, 越近越高)
  /// maxRange 為參考最大距離
  static double normalizeDistance(double meters, {double maxRange = 20000}) {
    if (meters <= 0) return 1.0;
    if (meters >= maxRange) return 0.0;
    return 1.0 - (meters / maxRange);
  }

  static double _toRad(double deg) => deg * pi / 180;

  /// Restore the real Geolocator seams + clear all mutable state. Tests MUST call
  /// this in tearDown so the shared singleton never leaks fakes/state across the
  /// suite (Owner boundary 7).
  @visibleForTesting
  void resetForTest() {
    isServiceEnabledFn = Geolocator.isLocationServiceEnabled;
    checkPermissionFn = Geolocator.checkPermission;
    getLastKnownFn = _defaultGetLastKnown;
    getCurrentFn = _defaultGetCurrent;
    now = DateTime.now;
    _currentLocation = null;
    _lastFixAt = null;
    _initialized = false;
    _unavailableReason = null;
    _permDeniedForever = false;
    _inFlightRefresh = null;
    onFirstFix = null;
    _ensureLocationControllerOpen();
  }

  void dispose() {
    _locationController.close();
    _initialized = false;
  }
}
