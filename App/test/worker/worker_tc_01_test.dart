import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_model.dart';

void main() {
  test('App Worker TC-01: Correctly parses valid JSON into WorkerModel', () {
    final json = {
      'id': 101,
      'name': 'Kamal Perera',
      'email': 'kamal@workio.lk',
      'phoneNo': '0771234567',
      'primaryServiceArea': 'Colombo',
      'coverageRadiusKm': 15.0,
      'pricingModel': 'Hourly',
      'hourlyRate': 2500.0,
      'dailyRate': 12000.0,
      'isAvailable': true,
      'overallRating': 4.8,
      'completedJobs': 24,
      'isVerified': true,
      'skills': [
        {
          'id': 1,
          'serviceName': 'Plumbing',
          'skills': ['Pipe Fitting', 'Leak Repair'],
          'experienceYears': 5,
        }
      ],
    };

    final worker = WorkerModel.fromJson(json);

    expect(worker.id, 101);
    expect(worker.name, 'Kamal Perera');
    expect(worker.email, 'kamal@workio.lk');
    expect(worker.pricingModel, 'Hourly');
    expect(worker.hourlyRate, 2500.0);
    expect(worker.overallRating, 4.8);
    expect(worker.completedJobs, 24);
    expect(worker.isVerified, isTrue);
    expect(worker.skillItems.length, 1);
    expect(worker.skillItems.first.serviceName, 'Plumbing');
  });
}
