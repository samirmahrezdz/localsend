import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';

void main() {
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TransferNotification.init(
      NotificationStrings(
        titleIncoming: 'Incoming',
        titleOutgoing: 'Outgoing',
        text: ({required fileCount}) => '$fileCount files',
        titleListening: 'Listening',
        textListening: 'Ready to receive',
      ),
    );
    await TransferNotification.setPersistentListening(false);
  });

  tearDown(() async {
    await TransferNotification.setPersistentListening(false);
    debugDefaultTargetPlatformOverride = null;
  });

  test('NotificationStrings uses default listening strings when omitted', () {
    final strings = NotificationStrings(
      titleIncoming: 'In',
      titleOutgoing: 'Out',
      text: ({required fileCount}) => '$fileCount',
    );
    expect(strings.titleListening, isNotEmpty);
    expect(strings.textListening, isNotEmpty);
  });

  test('setPersistentListening tracks enabled state across transfer lifecycle', () async {
    expect(TransferNotification.isPersistentListening, isFalse);

    await TransferNotification.setPersistentListening(true);
    expect(TransferNotification.isPersistentListening, isTrue);

    await TransferNotification.start('session-1', incoming: true, fileCount: 2);
    await TransferNotification.stop('session-1');
    expect(TransferNotification.isPersistentListening, isTrue);

    await TransferNotification.setPersistentListening(false);
    expect(TransferNotification.isPersistentListening, isFalse);
  });
}
