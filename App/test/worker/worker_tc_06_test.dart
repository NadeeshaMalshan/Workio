import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_services_data.dart';

void main() {
  test('App Worker TC-06: Verifies WorkerServicesCatalog contains official categories', () {
    final categories = WorkerServicesCatalog.categories;

    expect(categories, isNotEmpty);
    expect(categories.length, greaterThanOrEqualTo(20));

    final names = categories.map((c) => c.name).toList();
    expect(names, contains('Plumbing'));
    expect(names, contains('Electrical'));
    expect(names, contains('Carpentry'));
    expect(names, contains('Painting'));
    expect(names, contains('Masonry & Construction'));
    expect(names, contains('Vehicle Repair & Mechanic'));

    for (final cat in categories) {
      expect(cat.id, isNotEmpty);
      expect(cat.name, isNotEmpty);
      expect(cat.icon, isNotEmpty);
    }
  });
}
