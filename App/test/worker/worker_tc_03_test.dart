import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_model.dart';

void main() {
  test('App Worker TC-03: Parses WorkerSkillItem with List and comma-separated skills', () {
    // Case 1: Skills as List
    final item1 = WorkerSkillItem.fromJson({
      'id': 10,
      'serviceName': 'Electrical',
      'skills': ['Wiring', 'Lighting', 'Circuit DB'],
      'experienceYears': 4,
    });

    expect(item1.serviceName, 'Electrical');
    expect(item1.skills.length, 3);
    expect(item1.skills, contains('Wiring'));
    expect(item1.experienceYears, 4);

    // Case 2: Skills as comma-separated string
    final item2 = WorkerSkillItem.fromJson({
      'id': 11,
      'service': 'Carpentry',
      'skills': 'Door Fitting, Wood Polishing, Lock Replacement',
      'experienceYears': '6',
    });

    expect(item2.serviceName, 'Carpentry');
    expect(item2.skills.length, 3);
    expect(item2.skills, contains('Wood Polishing'));
    expect(item2.experienceYears, 6);
  });
}
