/// قناة SMS (المرحلة C): ثبات التقسيم وإعادة التجميع ذهاباً وإياباً،
/// ملاءمة GSM-7 وسقف الرسالة الواحدة، تسامح الإدخال اليدوي، ورفض
/// التلف والنقص والخلط والتزوير — بوابة إلزامية قبل بناء تدفق الواجهة.
library;

import 'package:test/test.dart';
import 'package:wasla_core/wasla_core.dart';

import 'support.dart';

/// محارف GSM-7 الأساسية المسموح بها في مقطع مرسَل: أبجدية Base45 بلا
/// مسافة (مدروعة) + فاصل الحقول + درع المسافة.
const String _gsm7Allowed =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\$%*+-./:#(';

Future<String> _realPayload() async {
  final identity = await DeviceIdentity.generate();
  final token = await craft(
    identity,
    recipientId: 'fedcba9876543210',
    amount: 250000,
    seq: 0,
    prevHash: 'a1' * 32,
    issuedAt: t0,
  );
  return encodeToken(token);
}

void main() {
  group('تقسيم الحمولة لمقاطع SMS', () {
    test('توكن حقيقي: كل مقطع يتسع في رسالة GSM-7 واحدة بلا فراغات', () async {
      final payload = await _realPayload();
      final segments = splitTokenPayloadForSms(payload);
      expect(segments.length, (payload.length + smsChunkChars - 1) ~/ smsChunkChars);
      expect(segments.length, greaterThan(1), reason: 'توكن كامل لا يتسع في رسالة واحدة');
      for (final s in segments) {
        expect(s.length, lessThanOrEqualTo(maxSmsChars));
        expect(s.split('').every(_gsm7Allowed.contains), isTrue,
            reason: 'محرف خارج GSM-7 الآمنة في: $s');
        expect(s.contains(RegExp(r'\s')), isFalse);
        expect(s, startsWith('$smsSegmentPrefix#'));
      }
    });

    test('حتمية: نفس التوكن ينتج نفس المقاطع حرفياً', () async {
      final payload = await _realPayload();
      expect(splitTokenPayloadForSms(payload), splitTokenPayloadForSms(payload));
    });

    test('حمولة قصيرة: مقطع واحد 1/1 يكتمل فوراً', () {
      final segments = splitTokenPayloadForSms('W1:TEST99');
      expect(segments, hasLength(1));
      expect(SmsInbox().add(segments.single), 'W1:TEST99');
    });

    test('طول من مضاعفات الشريحة بالضبط: لا مقطع فارغاً ولا محرف يضيع', () {
      final payload = 'W1:${'A' * (2 * smsChunkChars - 3)}';
      final segments = splitTokenPayloadForSms(payload);
      expect(segments, hasLength(2));
      final inbox = SmsInbox();
      expect(inbox.add(segments[0]), isNull);
      expect(inbox.add(segments[1]), payload);
    });

    test('مسافة Base45 في الحمولة تُدرَّع بـ( وتعود سالمة', () {
      final withSpace = 'W1:${base45Encode([0, 36, 7, 7])}';
      expect(withSpace, contains(' '), reason: 'البايتات مختارة لتنتج مسافة');
      final segments = splitTokenPayloadForSms(withSpace);
      expect(segments.single.contains(' '), isFalse);
      expect(segments.single, contains('('));
      expect(SmsInbox().add(segments.single), withSpace);
    });

    test('يرفض حمولة بلا بادئة W1: أو بمحرف خارج الأبجدية أو أضخم من القناة', () {
      expect(() => splitTokenPayloadForSms('X9:AAAA'),
          throwsA(isA<MalformedTokenException>()));
      expect(() => splitTokenPayloadForSms('W1:abc'),
          throwsA(isA<MalformedTokenException>()),
          reason: 'الحروف الصغيرة خارج أبجدية Base45');
      expect(
          () => splitTokenPayloadForSms(
              'W1:${'A' * (maxSmsSegments * smsChunkChars + 1)}'),
          throwsA(isA<MalformedTokenException>()));
    });
  });

  group('إعادة التجميع الكاملة ذهاباً وإياباً', () {
    test('مقاطع مخلوطة الترتيب تعيد الحمولة والتوكن حرفياً', () async {
      final payload = await _realPayload();
      final segments = splitTokenPayloadForSms(payload)..shuffle();
      final inbox = SmsInbox();
      String? completed;
      for (final s in segments) {
        expect(completed, isNull, reason: 'لا اكتمال قبل آخر جزء');
        completed = inbox.add(s);
      }
      expect(completed, payload);
      expect(encodeToken(decodeToken(completed!)), payload,
          reason: 'التوكن المفكوك يعيد ترميز نفسه بايتاً بايتاً');
      expect(inbox.pending, isEmpty);
    });

    test('الإدخال اليدوي: حروف صغيرة وفراغات وأسطر مقحمة تُقبل', () async {
      final payload = await _realPayload();
      final segments = splitTokenPayloadForSms(payload);
      final inbox = SmsInbox();
      String? completed;
      for (final s in segments) {
        final mangled = s
            .toLowerCase()
            .split('')
            .asMap()
            .entries
            .map((e) => e.key % 7 == 6 ? '${e.value}\n ' : e.value)
            .join();
        completed = inbox.add(mangled);
      }
      expect(completed, payload);
    });

    test('المكرر المطابق يُتجاهل بصمت ولا يمنع الاكتمال', () async {
      final payload = await _realPayload();
      final segments = splitTokenPayloadForSms(payload);
      final inbox = SmsInbox();
      expect(inbox.add(segments.first), isNull);
      expect(inbox.add(segments.first), isNull);
      for (final s in segments.skip(1).take(segments.length - 2)) {
        inbox.add(s);
      }
      expect(inbox.add(segments.last), payload);
    });

    test('pending يسمّي الأجزاء الناقصة وforget يلغي الرسالة', () async {
      final payload = await _realPayload();
      final segments = splitTokenPayloadForSms(payload);
      final inbox = SmsInbox()..add(segments.last);
      final status = inbox.pending.single;
      expect(status.total, segments.length);
      expect(status.receivedParts, [segments.length]);
      expect(status.missingParts,
          [for (var p = 1; p < segments.length; p++) p]);
      inbox.forget(status.msgId);
      expect(inbox.pending, isEmpty);
    });

    test('رسالتان متداخلتان من مرسلين تكتملان مستقلتين', () async {
      final payloadA = await _realPayload();
      final payloadB = await _realPayload();
      final segsA = splitTokenPayloadForSms(payloadA);
      final segsB = splitTokenPayloadForSms(payloadB);
      final inbox = SmsInbox();
      final results = <String>[];
      for (var i = 0; i < segsA.length || i < segsB.length; i++) {
        if (i < segsA.length) {
          final r = inbox.add(segsA[i]);
          if (r != null) results.add(r);
        }
        if (i < segsB.length) {
          final r = inbox.add(segsB[i]);
          if (r != null) results.add(r);
        }
      }
      expect(results, containsAll([payloadA, payloadB]));
    });
  });

  group('رفض التلف والتزوير', () {
    test('خطأ إدخال بمحرف واحد يُكشف ويُسمّى جزؤه', () async {
      final segments = splitTokenPayloadForSms(await _realPayload());
      final s = segments[1];
      final tampered =
          s.substring(0, s.length - 1) + (s.endsWith('7') ? '9' : '7');
      expect(
        () => SmsInbox().add(tampered),
        throwsA(isA<SmsChecksumException>()
            .having((e) => e.part, 'part', 2)),
      );
    });

    test('نصوص ليست مقاطع تُرفض بنوع بنية لا بنوع تحقق', () {
      final inbox = SmsInbox();
      for (final garbage in [
        '',
        'مرحبا',
        'W1S#SHORT',
        'W1S#ABCDEF#1#2', // حقول ناقصة
        'W2S#ABCDEF#1#1#XX#AAA', // بادئة إصدار آخر
      ]) {
        expect(() => inbox.add(garbage),
            throwsA(isA<MalformedSmsSegmentException>()),
            reason: 'قُبل: «$garbage»');
      }
    });

    test('أرقام أجزاء غير قانونية تُرفض: صفر بادئ، صفر، تجاوز', () {
      String craftText({required int part, required int total}) =>
          SmsSegment(msgId: 'ABCDEF', part: part, total: total, chunk: 'AAA')
              .text;
      // صفر بادئ: نفس القيمة بشكل غير قانوني يجب ألا يمرّ.
      final legal = craftText(part: 1, total: 2);
      expect(() => SmsSegment.parse(legal.replaceFirst('#1#2#', '#01#2#')),
          throwsA(isA<MalformedSmsSegmentException>()));
      expect(() => SmsSegment(msgId: 'ABCDEF', part: 0, total: 1, chunk: 'A'),
          throwsA(isA<MalformedSmsSegmentException>()));
      expect(() => SmsSegment(msgId: 'ABCDEF', part: 3, total: 2, chunk: 'A'),
          throwsA(isA<MalformedSmsSegmentException>()));
      expect(
          () => SmsSegment(
              msgId: 'ABCDEF', part: 1, total: maxSmsSegments + 1, chunk: 'A'),
          throwsA(isA<MalformedSmsSegmentException>()));
    });

    test('إجمالي متناقض لنفس الرسالة يُرفض تعارضاً', () async {
      final segments = splitTokenPayloadForSms(await _realPayload());
      final first = SmsSegment.parse(segments.first);
      final inbox = SmsInbox()..add(segments.first);
      final liar = SmsSegment(
        msgId: first.msgId,
        part: 1,
        total: first.total + 1,
        chunk: first.chunk,
      );
      expect(() => inbox.add(liar.text),
          throwsA(isA<SmsReassemblyException>()));
    });

    test('جزء يصل مرتين بمحتوى مختلف يُسقط الرسالة كلها', () async {
      final segments = splitTokenPayloadForSms(await _realPayload());
      final first = SmsSegment.parse(segments.first);
      final inbox = SmsInbox()..add(segments.first);
      final conflicting = SmsSegment(
        msgId: first.msgId,
        part: first.part,
        total: first.total,
        chunk: 'Z${first.chunk.substring(1)}',
      );
      expect(() => inbox.add(conflicting.text),
          throwsA(isA<SmsReassemblyException>()));
      expect(inbox.pending, isEmpty, reason: 'الحالة المسمومة لا تبقى');
    });

    test('مقطع مزوَّر متسق ذاتياً يفشل سلامة التجميع النهائي ثم تنجح الإعادة',
        () async {
      final payload = await _realPayload();
      final segments = splitTokenPayloadForSms(payload);
      final last = SmsSegment.parse(segments.last);
      final forged = SmsSegment(
        msgId: last.msgId,
        part: last.part,
        total: last.total,
        chunk: 'Q${last.chunk.substring(1)}',
      );
      final inbox = SmsInbox();
      for (final s in segments.take(segments.length - 1)) {
        inbox.add(s);
      }
      expect(
        () => inbox.add(forged.text),
        throwsA(isA<SmsChecksumException>()
            .having((e) => e.part, 'part', isNull)),
      );
      // الرسالة أُسقطت — إعادة إدخال الأجزاء الصحيحة كلها تنجح.
      expect(inbox.pending, isEmpty);
      String? completed;
      for (final s in segments) {
        completed = inbox.add(s);
      }
      expect(completed, payload);
    });
  });
}
