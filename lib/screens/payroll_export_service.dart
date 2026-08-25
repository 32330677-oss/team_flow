import 'payroll_export_service_stub.dart'
    if (dart.library.html) 'payroll_export_service_web.dart'
    if (dart.library.io) 'payroll_export_service_io.dart';

class PayrollExportService {
  static Future<void> exportBytes(List<int> bytes, String fileName) =>
      exportPayrollBytes(bytes, fileName);
}
