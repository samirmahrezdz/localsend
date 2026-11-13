import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TransferNotification.init(
      NotificationStrings(
        titleReceiving: 'Receiving',
        titleSending: 'Sending',
        titleListening: 'Listening',
        textListening: 'Ready to receive',
        remainingTimeMinutes: ({required m, required ss}) => '$m:$ss',
        remainingTimeLong: ({required h, required m}) => '${h}h ${m}m',
      ),
    );
    TransferNotification.setPersistentListening(false);
  });

  tearDown(() {
    TransferNotification.setPersistentListening(false);
    debugDefaultTargetPlatformOverride = null;
  });

  test('NotificationStrings uses default listening strings when omitted', () {
    final strings = NotificationStrings(
      titleReceiving: 'In',
      titleSending: 'Out',
      remainingTimeMinutes: ({required m, required ss}) => '$m:$ss',
      remainingTimeLong: ({required h, required m}) => '${h}h ${m}m',
    );
    expect(strings.titleListening, isNotEmpty);
    expect(strings.textListening, isNotEmpty);
  });

  test('setPersistentListening tracks enabled state across transfer lifecycle', () {
    expect(TransferNotification.isPersistentListening, isFalse);

    TransferNotification.setPersistentListening(true);
    expect(TransferNotification.isPersistentListening, isTrue);

    TransferNotification.start(sessionId: 'session-1', receiving: true);
    TransferNotification.stop('session-1');
    expect(TransferNotification.isPersistentListening, isTrue);

    TransferNotification.setPersistentListening(false);
    expect(TransferNotification.isPersistentListening, isFalse);
  });
}
