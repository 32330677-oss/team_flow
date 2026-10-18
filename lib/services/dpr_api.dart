// lib/services/dpr_api.dart
//
// Daily Progress Report (backend: /api/dpr). Every call is checked on the
// server with the permissions of the signed-in account (dpr.view, dpr.edit,
// dpr.override, dpr.registers, dpr.issue, dpr.revise, dpr.setup).
// Data comes back as JSON maps: the screens read them with the helpers below.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../constants.dart';

typedef Json = Map<String, dynamic>;

/// Error with the server message (and the server's extra data, e.g. the
/// missing fields when issuing).
class DprException implements Exception {
  final String message;
  final int? status;
  final Json data;
  const DprException(this.message, {this.status, this.data = const {}});
  String? get code => data['code']?.toString();
  @override
  String toString() => message;
}

/// Contract and date chosen in the DPR pages (kept when moving between pages).
class DprState {
  static final ValueNotifier<int?> contractId = ValueNotifier<int?>(null);
  static final ValueNotifier<DateTime> date = ValueNotifier<DateTime>(_today());
  static Set<String> permissions = <String>{};
  /// contract id -> 'ucc' (the client's form) or 'dpr' (the DPR workbook), filled by the contract bar.
  static final ValueNotifier<Map<int, String>> templates = ValueNotifier<Map<int, String>>(<int, String>{});

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static bool can(String p) => permissions.contains(p);
  static String get dateStr => ymd(date.value);
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseYmd(String s) => DateTime.parse(s.length >= 10 ? s.substring(0, 10) : s);

Json asJson(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Json> asList(dynamic v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Json>[];
String str(dynamic v) => v == null ? '' : v.toString();
int asInt(dynamic v) => v is int ? v : (int.tryParse(str(v)) ?? (num.tryParse(str(v))?.toInt() ?? 0));
double? asNum(dynamic v) => v == null || str(v).isEmpty ? null : num.tryParse(str(v))?.toDouble();

/// 1234.5 -> "1,234.5" with the exact decimals of the stored value (never rounded).
String fmtQty(dynamic v, {int minDecimals = 0, bool dash = false}) {
  final s = str(v);
  if (s.isEmpty) return '';
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) return s;
  if (dash && (num.tryParse(s) ?? 0) == 0) return '-';
  final neg = s.startsWith('-');
  final parts = s.replaceFirst('-', '').split('.');
  final intPart = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  var frac = parts.length > 1 ? parts[1].replaceFirst(RegExp(r'0+$'), '') : '';
  while (frac.length < minDecimals) {
    frac += '0';
  }
  return '${neg ? '-' : ''}$intPart${frac.isEmpty ? '' : '.$frac'}';
}

String fmtPct(dynamic v, {int decimals = 1}) {
  final n = asNum(v);
  if (n == null) return '';
  return '${(n * 100).toStringAsFixed(decimals)}%';
}

String fmtRatio(dynamic v, {int decimals = 2}) {
  final n = asNum(v);
  if (n == null) return '';
  return n.toStringAsFixed(decimals);
}

String fmtDay(dynamic v) {
  final s = str(v);
  if (s.length < 10) return s;
  try {
    return DateFormat('dd-MMM-yyyy').format(parseYmd(s));
  } catch (_) {
    return s;
  }
}

class DprApi {
  static final Dio _dio = ApiConfig.dio;

  static DprException _error(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (e.response == null) {
        return const DprException('Cannot reach the server. Check your connection and try again.');
      }
      if (data is Map) {
        return DprException(str(data['message']).isEmpty ? 'Request failed (${e.response?.statusCode}).' : str(data['message']),
            status: e.response?.statusCode, data: Map<String, dynamic>.from(data));
      }
      return DprException('Request failed (${e.response?.statusCode}).', status: e.response?.statusCode);
    }
    return DprException(e.toString());
  }

  static Future<dynamic> _get(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get(path, queryParameters: query, options: Options(receiveTimeout: const Duration(seconds: 90)));
      return (res.data is Map) ? res.data['data'] : null;
    } catch (e) {
      throw _error(e);
    }
  }

  static Future<dynamic> _send(String method, String path, [Object? body]) async {
    try {
      final res = await _dio.request(path, data: body ?? <String, dynamic>{},
          options: Options(method: method, receiveTimeout: const Duration(seconds: 90)));
      return (res.data is Map) ? res.data['data'] : null;
    } catch (e) {
      throw _error(e);
    }
  }

  static Future<Uint8List> _bytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(path,
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 120)));
      final data = res.data;
      if (data == null || data.isEmpty) throw const DprException('The file is empty.');
      return Uint8List.fromList(data);
    } on DprException {
      rethrow;
    } catch (e) {
      if (e is DioException && e.response?.data is List<int>) {
        // the error body came back as bytes
        try {
          final text = String.fromCharCodes(e.response!.data as List<int>);
          final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(text);
          if (m != null) throw DprException(m.group(1)!, status: e.response?.statusCode);
        } on DprException {
          rethrow;
        } catch (_) {}
      }
      throw _error(e);
    }
  }

  static String _day(int cid, String date) => '/dpr/contracts/$cid/days/$date';

  // general
  static Future<Json> options() async => asJson(await _get('/dpr/options'));
  static Future<Json> sourceOptions(List<int> tfSiteIds) async =>
      asJson(await _get('/dpr/source-options', query: {'tf_site_ids': tfSiteIds.join(',')}));
  static Future<List<Json>> differences({int? contractId, String? from, String? to, bool includeReverted = false}) async =>
      asList(await _get('/dpr/differences', query: {
        if (contractId != null) 'contract_id': contractId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (includeReverted) 'include_reverted': 'true',
      }));

  // contracts & setup
  static Future<List<Json>> contracts() async => asList(await _get('/dpr/contracts'));
  static Future<Json> createContract(Json body) async => asJson(await _send('POST', '/dpr/contracts', body));
  static Future<Json> setup(int cid) async => asJson(await _get('/dpr/contracts/$cid'));
  static Future<Json> updateContract(int cid, Json body) async => asJson(await _send('PUT', '/dpr/contracts/$cid', body));
  static Future<Json> copySetup(int cid, int fromId, List<String> parts) async =>
      asJson(await _send('POST', '/dpr/contracts/$cid/copy-setup', {'from_contract_id': fromId, 'parts': parts}));
  static Future<Json> saveEotVo(int cid, int? id, Json body) async =>
      asJson(await _send(id == null ? 'POST' : 'PUT', id == null ? '/dpr/contracts/$cid/eot-vo' : '/dpr/contracts/$cid/eot-vo/$id', body));
  static Future<void> deleteEotVo(int cid, int id) => _send('DELETE', '/dpr/contracts/$cid/eot-vo/$id');
  static Future<Json> saveLine(int cid, int? id, Json body) async =>
      asJson(await _send(id == null ? 'POST' : 'PUT', id == null ? '/dpr/contracts/$cid/lines' : '/dpr/contracts/$cid/lines/$id', body));
  static Future<Json> setLineActive(int cid, int id, bool active) async =>
      asJson(await _send('PATCH', '/dpr/contracts/$cid/lines/$id/active', {'is_active': active}));
  static Future<void> reorderLines(int cid, String kind, List<int> ids) =>
      _send('PUT', '/dpr/contracts/$cid/lines-order', {'kind': kind, 'line_ids': ids});
  static Future<Json> saveBoq(int cid, int? id, Json body) async =>
      asJson(await _send(id == null ? 'POST' : 'PUT', id == null ? '/dpr/contracts/$cid/boq' : '/dpr/contracts/$cid/boq/$id', body));
  static Future<Json> importBoq(int cid, List<int> bytes, String name) async =>
      asJson(await _send('POST', '/dpr/contracts/$cid/boq-import',
          FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: name)})));

  // the day
  static Future<Json> day(int cid, String date, {bool refresh = false}) async =>
      asJson(await _get(_day(cid, date), query: refresh ? {'refresh': '1'} : null));
  static Future<Json> patchDay(int cid, String date, int version, Json fields) async =>
      asJson(await _send('PATCH', _day(cid, date), {'version': version, 'fields': fields}));
  static Future<void> setCount(int cid, String date, int lineId, int value) =>
      _send('PUT', '${_day(cid, date)}/counts/$lineId', {'value': value});
  static Future<void> setOverride(int cid, String date, int lineId, int value, String reason) =>
      _send('PUT', '${_day(cid, date)}/overrides/$lineId', {'value': value, 'reason': reason});
  static Future<void> revertOverride(int cid, String date, int lineId) => _send('DELETE', '${_day(cid, date)}/overrides/$lineId');
  static Future<List<Json>> overrideHistory(int cid, String date, int lineId) async =>
      asList(await _get('${_day(cid, date)}/overrides/$lineId'));
  static Future<List<Json>> history(int cid, {String? date, String? entity, String? entityId, String? field}) async =>
      asList(await _get(date == null ? '/dpr/contracts/$cid/history' : '${_day(cid, date)}/history', query: {
        if (entity != null) 'entity': entity,
        if (entityId != null) 'entity_id': entityId,
        if (field != null) 'field': field,
      }));
  static Future<Json> saveActivity(int cid, String date, int? id, Json body) async => asJson(await _send(
      id == null ? 'POST' : 'PUT', id == null ? '${_day(cid, date)}/activities' : '${_day(cid, date)}/activities/$id', body));
  static Future<void> deleteActivity(int cid, String date, int id) => _send('DELETE', '${_day(cid, date)}/activities/$id');
  static Future<Json> saveQa(int cid, String date, int? id, Json body) async =>
      asJson(await _send(id == null ? 'POST' : 'PUT', id == null ? '${_day(cid, date)}/qa' : '${_day(cid, date)}/qa/$id', body));
  static Future<void> deleteQa(int cid, String date, int id) => _send('DELETE', '${_day(cid, date)}/qa/$id');
  static Future<Json> addPhoto(int cid, String date, List<int> bytes, String name, Json fields) async =>
      asJson(await _send('POST', '${_day(cid, date)}/photos', FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: name),
        ...fields.map((k, v) => MapEntry(k, v.toString())),
      })));
  static Future<void> updatePhoto(int cid, String date, int id, Json body) => _send('PUT', '${_day(cid, date)}/photos/$id', body);
  static Future<void> deletePhoto(int cid, String date, int id) => _send('DELETE', '${_day(cid, date)}/photos/$id');
  static Future<Uint8List> photoBytes(int cid, int photoId) => _bytes('/dpr/contracts/$cid/photos/$photoId/file');
  static Future<Json> copyDay(int cid, String date, int fromId, List<String> parts) async =>
      asJson(await _send('POST', '${_day(cid, date)}/copy', {'from_contract_id': fromId, 'parts': parts}));
  static Future<Uint8List> draftPdf(int cid, String date) => _bytes('${_day(cid, date)}/pdf');
  static Future<Uint8List> draftXlsx(int cid, String date) => _bytes('${_day(cid, date)}/xlsx');
  static Future<Json> issue(int cid, String date, Json body) async => asJson(await _send('POST', '${_day(cid, date)}/issue', body));
  static Future<Json> revise(int cid, String date, Json body) async => asJson(await _send('POST', '${_day(cid, date)}/revise', body));

  // archive, dashboard, registers
  static Future<List<Json>> reports(int cid, {String? from, String? to}) async =>
      asList(await _get('/dpr/contracts/$cid/reports', query: {if (from != null) 'from': from, if (to != null) 'to': to}));
  static Future<Uint8List> reportPdf(int cid, int rid) => _bytes('/dpr/contracts/$cid/reports/$rid/pdf');
  static Future<Uint8List> reportXlsx(int cid, int rid) => _bytes('/dpr/contracts/$cid/reports/$rid/xlsx');
  static Future<Json> dashboard(int cid, String date) async => asJson(await _get('/dpr/contracts/$cid/dashboard', query: {'date': date}));
  static Future<List<Json>> register(int cid, String kind, {String? status}) async =>
      asList(await _get('/dpr/contracts/$cid/registers/$kind', query: {if (status != null) 'status': status}));
  static Future<Json> saveRegister(int cid, String kind, int? id, Json body) async => asJson(await _send(
      id == null ? 'POST' : 'PUT', id == null ? '/dpr/contracts/$cid/registers/$kind' : '/dpr/contracts/$cid/registers/$kind/$id', body));
  static Future<void> deleteRegister(int cid, String kind, int id) => _send('DELETE', '/dpr/contracts/$cid/registers/$kind/$id');

  // ---------------------------------------------------------------- v2: the client's form
  /// Workers of the day on every Team Flow site (counts only).
  static Future<Json> teamFlowToday(String date, {int? contractId}) async =>
      asJson(await _get('/dpr/team-flow-today', query: {'date': date, if (contractId != null) 'contract_id': contractId}));
  static Future<Json> patchDayTo(int cid, String date, int version, Json fields, List<int> applyTo) async =>
      asJson(await _send('PATCH', _day(cid, date), {'version': version, 'fields': fields, 'apply_to': applyTo}));
  /// A manual value: scope 'day' (this report only), 'forward' (from this day on), 'chain' (counts in the cumulative).
  static Future<Json> setManual(int cid, String date, Json body) async => asJson(await _send('PUT', '${_day(cid, date)}/manual', body));
  static Future<Json> previewManual(int cid, String date, Json body) async =>
      asJson(await _send('POST', '${_day(cid, date)}/manual/preview', body));
  static Future<void> revertManual(int cid, String date, Json body) => _send('POST', '${_day(cid, date)}/manual/revert', body);
  static Future<List<Json>> manualHistory(int cid, String date, String key) async =>
      asList(await _get('${_day(cid, date)}/manual/history', query: {'key': key}));
  static Future<Json> saveMaterial(int cid, String date, int? id, Json body) async => asJson(await _send(
      id == null ? 'POST' : 'PUT', id == null ? '${_day(cid, date)}/materials' : '${_day(cid, date)}/materials/$id', body));
  static Future<void> deleteMaterial(int cid, String date, int id) => _send('DELETE', '${_day(cid, date)}/materials/$id');
  static Future<void> reorderActivities(int cid, String date, List<int> ids) =>
      _send('PUT', '${_day(cid, date)}/activities-order', {'activity_ids': ids});
  // setup
  static Future<Json> loadDefaultLines(int cid, List<String> kinds) async =>
      asJson(await _send('POST', '/dpr/contracts/$cid/default-lines', {'kinds': kinds}));
  static Future<void> reorderBoq(int cid, List<int> ids) => _send('PUT', '/dpr/contracts/$cid/boq-order', {'boq_ids': ids});
  static Future<void> deleteBoq(int cid, int id) => _send('DELETE', '/dpr/contracts/$cid/boq/$id');
  static Future<Json> saveArea(int cid, int? id, Json body) async =>
      asJson(await _send(id == null ? 'POST' : 'PUT', id == null ? '/dpr/contracts/$cid/areas' : '/dpr/contracts/$cid/areas/$id', body));
  static Future<Json> addFixedPage(int cid, List<int> bytes, String name, String title) async =>
      asJson(await _send('POST', '/dpr/contracts/$cid/fixed-pages', FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: name),
        'title': title,
      })));
  static Future<Json> updateFixedPage(int cid, int id, Json body) async => asJson(await _send('PUT', '/dpr/contracts/$cid/fixed-pages/$id', body));
  static Future<Uint8List> fixedPageBytes(int cid, int id) => _bytes('/dpr/contracts/$cid/fixed-pages/$id/file');
}
