import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_model.dart';

void main() {
  test('App Worker TC-04: Computes deduplicated serviceNames and primary trade correctly', () {
    final skillItems = [
      WorkerSkillItem(id: 1, serviceName: 'Plumbing', skills: ['Leak Repair']),
      WorkerSkillItem(id: 2, serviceName: 'Electrical', skills: ['Wiring']),
      WorkerSkillItem(id: 3, serviceName: 'Plumbing', skills: ['Pipe Fitting']), // duplicate service
    ];

    final worker = WorkerModel(
      id: 5,
      name: 'Nimal Bandara',
      email: 'nimal@workio.lk',
      skillItems: skillItems,
    );

    expect(worker.serviceNames.length, 2);
    expect(worker.serviceNames, contains('Plumbing'));
    expect(worker.serviceNames, contains('Electrical'));
    expect(worker.trade, 'Plumbing'); // Primary trade takes first unique service
  });
}
