import 'package:flutter_test/flutter_test.dart';
import 'package:omni_sniffer/features/launch_monitor/domain/entities/shot_trajectory.dart';

TrajectoryPoint point(double t, double z, {double y = 0, double speed = 10}) =>
    TrajectoryPoint(t: t, x: 0, y: y, z: z, speed: speed);

void main() {
  test('irregular contact samples preserve elapsed time and tracer endpoint', () {
    final points = [point(6, 0), point(6.04, 4), point(6.041, 4.1), point(6.08, 8)];
    final ball = trajectoryPointAtTime(points, 6.06)!;
    final path = trajectoryThroughTime(points, 6.06);
    expect(ball.z, closeTo(6, 1e-9));
    expect(path.last.z, ball.z);
    expect(path.last.t, 6.06);
    expect(path.every((p) => p.t <= 6.06), isTrue);
    expect(path.length, 4);
  });

  test('duplicate touchdown times choose the post-contact state', () {
    final points = [point(0, 0), point(1, 10, speed: 20),
      point(1, 10, speed: 5), point(2, 12, speed: 0)];
    expect(trajectoryPointAtTime(points, 1)!.speed, 5);
    expect(trajectoryPointAtTime(points, 1.5)!.z, 11);
    expect(trajectoryThroughTime(points, 1).last.speed, 5);
  });

  test('empty paths and clamped endpoints are safe', () {
    expect(trajectoryPointAtTime([], 1), isNull);
    expect(trajectoryThroughTime([], 1), isEmpty);
    final points = [point(3, 0), point(4, 2)];
    expect(trajectoryThroughTime(points, 3).length, 1);
    expect(trajectoryThroughTime(points, 3).last.z, 0);
    expect(trajectoryPointAtTime(points, -1), same(points.first));
    expect(trajectoryPointAtTime(points, double.nan), same(points.first));
    expect(trajectoryPointAtTime(points, 99), same(points.last));
    expect(trajectoryThroughTime(points, 99), same(points));
    expect(trajectoryPointAtTime([points.first], 4), same(points.first));
  });

  test('a short final interval is not stretched to a full sample interval', () {
    final points = [point(0, 0), point(0.02, 2), point(0.025, 2.5)];
    expect(trajectoryPointAtTime(points, 0.02)!.z, 2);
    expect(trajectoryPointAtTime(points, 0.0225)!.z, closeTo(2.25, 1e-9));
  });
}
