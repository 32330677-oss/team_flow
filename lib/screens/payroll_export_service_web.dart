import 'dart:html' as html;
import 'dart:typed_data';

String _mimeTypeFor(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  return 'application/octet-stream';
}

Future<void> exportPayrollBytes(List<int> bytes, String fileName) async {
  // لازم Uint8List حقيقية، مش List<int> عادية، وإلا ممكن يتشوه أي بايت
  // خارج مجال ASCII عند بناء الـ Blob في المتصفح.
  final Uint8List typedBytes =
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  final blob = html.Blob(<Object>[typedBytes.buffer], _mimeTypeFor(fileName));
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
   await Future<void>.delayed(const Duration(seconds: 1));
  html.Url.revokeObjectUrl(url);
}