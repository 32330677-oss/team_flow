import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportPayrollBytes(List<int> bytes, String fileName) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  await Share.shareXFiles([XFile(file.path)], text: 'Payroll Excel report');
}
