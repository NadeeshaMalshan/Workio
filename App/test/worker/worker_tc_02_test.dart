import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_model.dart';

void main() {
  test('App Worker TC-02: Handles null, missing, and fallback fields in WorkerModel', () {
    final json = {
      'id': 102,
      'name': null,
      'email': null,
      'skills': null,
    };

    final worker = WorkerModel.fromJson(json);

    expect(worker.id, 102);
    expect(worker.name, 'Worker'); // Default name fallback
    expect(worker.email, '');
    expect(worker.coverageRadiusKm, 10.0); // Default coverage
    expect(worker.pricingModel, 'Hourly');
    expect(worker.isAvailable, isTrue); // Default availability
    expect(worker.completedJobs, 0);
    expect(worker.skills, isEmpty);
    expect(worker.skillItems, isEmpty);
    expect(worker.trade, 'Pro'); // Fallback trade when no skills provided
  });
}
