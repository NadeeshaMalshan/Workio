import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_model.dart';

void main() {
  test('App Worker TC-10: Parses location coordinates and proximity distance', () {
    final json = {
      'id': 50,
      'name': 'Kasun Perera',
      'email': 'kasun@workio.lk',
      'locationLat': 6.9271,
      'locationLng': 79.8612,
      'distance': 3.45,
    };

    final worker = WorkerModel.fromJson(json);

    expect(worker.locationLat, 6.9271);
    expect(worker.locationLng, 79.8612);
    expect(worker.distance, 3.45);
  });
}
