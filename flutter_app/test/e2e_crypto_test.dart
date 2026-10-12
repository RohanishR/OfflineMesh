import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('corrupt file test', () async {
    final tempDir = Directory.systemTemp.createTempSync('corrupt_debug_');
    final file = File('${tempDir.path}/test.bin');
    await file.writeAsBytes([1, 2, 3, 4, 5]);

    expect(await file.exists(), isTrue);

    final bytes = await file.readAsBytes();
    bytes[0] ^= 0xFF;
    await file.writeAsBytes(bytes);

    expect(await file.exists(), isTrue);
    final raf = await file.open(mode: FileMode.read);
    await raf.close();

    tempDir.deleteSync(recursive: true);
  });
}
