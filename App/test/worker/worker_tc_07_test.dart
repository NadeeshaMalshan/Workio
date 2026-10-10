import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_services_data.dart';

void main() {
  test('App Worker TC-07: getSkillsForService retrieves default skills for category', () {
    final plumbingSkills = WorkerServicesCatalog.getSkillsForService('Plumbing');
    expect(plumbingSkills, isNotEmpty);
    expect(plumbingSkills, contains('Pipe Fitting & Installation'));
    expect(plumbingSkills, contains('Leak Detection & Repair'));

    final electricalSkills = WorkerServicesCatalog.getSkillsForService('electrical');
    expect(electricalSkills, isNotEmpty);
    expect(electricalSkills, contains('House Wiring & Rewiring'));

    // Unknown category falls back to empty or others
    final unknownSkills = WorkerServicesCatalog.getSkillsForService('UnknownTradeXYZ');
    expect(unknownSkills, isA<List<String>>());
  });
}
