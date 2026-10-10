import 'package:flutter_test/flutter_test.dart';
import 'package:superbass/models/worker_model.dart';

void main() {
  test('App Worker TC-08: Evaluates rating getter and performance stats accurately', () {
    // Case 1: Rating is present
    final workerWithRating = WorkerModel(
      id: 1,
      name: 'Amal',
      email: 'amal@workio.lk',
      overallRating: 4.65,
      completedJobs: 18,
      acceptedJobs: 20,
      rejectedJobs: 1,
      cancelledJobs: 1,
    );

    expect(workerWithRating.rating, 4.65);
    expect(workerWithRating.completedJobs, 18);
    expect(workerWithRating.cancelledJobs, 1);

    // Case 2: Rating is null (new worker) -> returns 0.0
    final newWorker = WorkerModel(
      id: 2,
      name: 'Bimal',
      email: 'bimal@workio.lk',
      overallRating: null,
    );

    expect(newWorker.rating, 0.0);
  });
}
