import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_model.dart';

void main() {
  test('App Worker TC-05: Correctly serializes WorkerModel to JSON map', () {
    final worker = WorkerModel(
      id: 20,
      name: 'Sunil Perera',
      email: 'sunil@workio.lk',
      phoneNo: '0779998877',
      primaryServiceArea: 'Moratuwa',
      coverageRadiusKm: 20.0,
      pricingModel: 'Daily',
      hourlyRate: 0.0,
      dailyRate: 9000.0,
      isAvailable: true,
      isVerified: true,
      skillItems: [
        WorkerSkillItem(
          id: 50,
          serviceName: 'Carpentry',
          skills: ['Door Fitting', 'Cabinets'],
          experienceYears: 7,
        )
      ],
    );

    final map = worker.toJson();

    expect(map['id'], 20);
    expect(map['name'], 'Sunil Perera');
    expect(map['email'], 'sunil@workio.lk');
    expect(map['primaryServiceArea'], 'Moratuwa');
    expect(map['coverageRadiusKm'], 20.0);
    expect(map['pricingModel'], 'Daily');
    expect(map['dailyRate'], 9000.0);
    expect(map['isVerified'], isTrue);
    expect(map['skills'], isA<List>());
    expect((map['skills'] as List).length, 1);
  });
}
