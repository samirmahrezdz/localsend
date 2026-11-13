import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:test/test.dart';

void main() {
  group('buildContextMenuLabel', () {
    test('uses defaultLabel when targetAlias is null or blank', () {
      expect(
        buildContextMenuLabel(
          targetAlias: null,
          defaultLabel: 'Send with LocalSend',
          targetLabel: (target) => 'Send to $target',
        ),
        'Send with LocalSend',
      );
      expect(
        buildContextMenuLabel(
          targetAlias: '   ',
          defaultLabel: 'Send with LocalSend',
          targetLabel: (target) => 'Send to $target',
        ),
        'Send with LocalSend',
      );
    });

    test('formats trimmed alias via targetLabel and clips overly long aliases', () {
      expect(
        buildContextMenuLabel(
          targetAlias: '  Galaxy S24  ',
          defaultLabel: 'Send with LocalSend',
          targetLabel: (target) => 'Send to $target',
        ),
        'Send to Galaxy S24',
      );

      final clipped = buildContextMenuLabel(
        targetAlias: 'A very long Android phone alias exceeding thirty-two characters',
        defaultLabel: 'Send with LocalSend',
        targetLabel: (target) => 'Send to $target',
      );
      expect(clipped, startsWith('Send to A very long'));
      expect(clipped.length, lessThanOrEqualTo('Send to '.length + 32));
    });
  });

  group('buildQuickSendCommand', () {
    test('quotes executable path and appends --quick-send with placeholder arg', () {
      expect(
        buildQuickSendCommand(r'C:\Program Files\LocalSend\localsend_app.exe'),
        r'"C:\Program Files\LocalSend\localsend_app.exe" --quick-send "%1"',
      );
    });
  });
}
