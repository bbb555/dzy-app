import 'package:flutter_test/flutter_test.dart';
import 'package:flux/services/traffic_speed_service.dart';
import 'package:flux/services/update_service.dart';

void main() {
  test('compareVersions', () {
    expect(UpdateService.compareVersions('1.1.2', '1.2.0'), lessThan(0));
    expect(UpdateService.compareVersions('1.2.0', '1.2.0'), 0);
    expect(UpdateService.compareVersions('v1.2.0', '1.2'), 0);
    expect(UpdateService.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(UpdateService.compareVersions('1.2.0-beta', '1.2.0'), 0);
    expect(UpdateService.compareVersions('1.0.0', '1.0.1'), lessThan(0));
  });

  test('formatSpeed / formatBytes', () {
    expect(formatSpeed(0), '0.0 KB/s');
    expect(formatSpeed(5 * 1024), '5.0 KB/s');
    expect(formatSpeed(512 * 1024), '512 KB/s');
    expect(formatSpeed(1.5 * 1024 * 1024), '1.50 MB/s');
    expect(formatSpeed(150 * 1024 * 1024), '150.0 MB/s');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(35 * 1024 * 1024), '35.0 MB');
    expect(formatBytes(1288490188), '1.20 GB');
  });
}
