"""Generate Drift tables without analysing Flutter UI dependencies.

The repository's pinned drift_dev uses an analyzer older than current Flutter
sources. Keep that generator and runtime pair, but analyse only the schema.
Run from the repository root with Dart available on PATH.
"""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--offline', action='store_true', help='Use cached Dart dependencies only')
args = parser.parse_args()
DATABASE = ROOT / 'lib/features/launch_monitor/data/database.dart'
source = DATABASE.read_text()
lock = (ROOT / 'pubspec.lock').read_text()


def version(package):
    block = re.search(r'^  ' + re.escape(package) + r':\n(.*?)(?=^  \w|\Z)',
                      lock, flags=re.M | re.S)
    return re.search(r'    version: "([^"]+)"', block.group(1)).group(1)


# Only table definitions affect generated output. Connection and domain mapping
# methods stay in the app and are checked by analysis and persistence tests.
start = source.index("@DataClassName('ActivityRow')")
end = source.index('// ── Database')
tables = source[start:end]
annotation = re.search(r'@DriftDatabase\([^\n]+\)', source).group(0)
schema_version = re.search(r'int get schemaVersion => (\d+)', source).group(1)
schema = (
    "import 'package:drift/drift.dart';\npart 'database.g.dart';\n" + tables +
    annotation + '\nclass AppDatabase extends _$AppDatabase {\n'
    '  AppDatabase(QueryExecutor executor) : super(executor);\n'
    '  @override\n  int get schemaVersion => ' + schema_version + ';\n}\n'
)
with tempfile.TemporaryDirectory(prefix='launch-monitor-schema-') as temp:
    folder = Path(temp)
    (folder / 'lib').mkdir()
    (folder / 'lib/database.dart').write_text(schema)
    (folder / 'pubspec.yaml').write_text(
        'name: launch_monitor_schema\nenvironment:\n  sdk: ^3.9.0\n'
        'dependencies:\n  drift: ' + version('drift') + '\n'
        'dev_dependencies:\n  drift_dev: ' + version('drift_dev') + '\n'
        '  build_runner: ' + version('build_runner') + '\n'
    )
    # Preserve transitive versions as well as the generator/runtime pair.
    (folder / 'pubspec.lock').write_text(lock)
    dart = os.environ.get('DART', 'dart')
    subprocess.run([dart, 'pub', 'get', *(['--offline'] if args.offline else [])],
                   cwd=folder, check=True)
    subprocess.run([dart, 'run', 'build_runner', 'build'], cwd=folder, check=True)
    generated = folder / 'lib/database.g.dart'
    if not generated.exists():
        raise RuntimeError('Drift did not generate the database')
    shutil.copyfile(generated, DATABASE.with_name('database.g.dart'))
