/// Compare an independent set of observed flights with the unchanged aero fit.
/// Usage: dart run tool/validate_flight.dart observations.json
/// All distances are yards, speeds mph, angles degrees, times seconds.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../lib/features/launch_monitor/domain/entities/shot_trajectory.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/validate_flight.dart observations.json');
    exitCode = 64;
    return;
  }
  try {
    final document = jsonDecode(File(args.single).readAsStringSync());
    if (document is! Map<String, dynamic> || document['shots'] is! List ||
        document['source'] is! String ||
        (document['source'] as String).trim().isEmpty ||
        document['conditions'] is! String ||
        (document['conditions'] as String).trim().isEmpty) {
      throw const FormatException('Provide source, conditions and a shots array.');
    }
    final shots = document['shots'] as List;
    if (shots.isEmpty) throw const FormatException('No observations supplied.');
    const units = {'carry': 'yd', 'apex': 'yd', 'descent': 'deg',
      'flightTime': 's', 'offline': 'yd'};
    final errors = {for (final key in units.keys) key: <double>[]};
    final rows = <Map<String, Object>>[];
    for (var i = 0; i < shots.length; i++) {
      final row = shots[i];
      if (row is! Map<String, dynamic>) {
        throw FormatException('Shot ${i + 1} must be an object.');
      }
      double value(String key) {
        final v = row[key];
        if (v is! num || !v.isFinite) {
          throw FormatException('Shot ${i + 1}: $key must be a finite number.');
        }
        return v.toDouble();
      }
      final result = BallFlightModel.standard.simulate(
        ballSpeedMph: value('ballSpeed'), launchAngleDeg: value('launchAngle'),
        launchDirectionDeg: value('launchDirection'), spinRpm: value('spin'),
        spinAxisDeg: value('spinAxis'),
      );
      if (result.isEmpty) {
        throw FormatException('Shot ${i + 1}: ${result.failure?.name}.');
      }
      final predictions = {'carry': result.carry, 'apex': result.apex,
        'descent': result.descentAngle, 'flightTime': result.flightTime,
        'offline': result.offline};
      var observed = 0;
      for (final metric in predictions.keys) {
        if (!row.containsKey(metric)) continue;
        final reference = value(metric);
        if (metric != 'offline' && reference <= 0) {
          throw FormatException('Shot ${i + 1}: $metric must be positive.');
        }
        final error = predictions[metric]! - reference;
        errors[metric]!.add(error);
        rows.add({'shot': i + 1, 'metric': metric, 'observed': reference,
          'simulated': predictions[metric]!, 'error': error});
        observed++;
      }
      if (observed == 0) {
        throw FormatException('Shot ${i + 1} has no observed flight metrics.');
      }
    }
    final summary = <String, Object>{};
    for (final entry in errors.entries) {
      final values = entry.value;
      if (values.isEmpty) continue;
      summary[entry.key] = {'n': values.length, 'unit': units[entry.key]!,
        'bias': values.reduce((a, b) => a + b) / values.length,
        'rmse': math.sqrt(values.map((v) => v * v)
            .reduce((a, b) => a + b) / values.length)};
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'source': document['source'], 'conditions': document['conditions'],
      'modelVersion': BallFlightModel.version,
      'modelConditions': 'Sea level, 15 C, dry air, no wind',
      'summary': summary, 'shots': rows,
    }));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 66;
  }
}
