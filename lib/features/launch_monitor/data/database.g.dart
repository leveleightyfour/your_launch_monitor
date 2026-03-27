// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ActivitiesTable extends Activities
    with TableInfo<$ActivitiesTable, ActivityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActivityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ActivitiesTable createAlias(String alias) {
    return $ActivitiesTable(attachedDatabase, alias);
  }
}

class ActivityRow extends DataClass implements Insertable<ActivityRow> {
  final int id;
  final String name;
  final DateTime createdAt;
  const ActivityRow({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ActivitiesCompanion toCompanion(bool nullToAbsent) {
    return ActivitiesCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory ActivityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ActivityRow copyWith({int? id, String? name, DateTime? createdAt}) =>
      ActivityRow(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );
  ActivityRow copyWithCompanion(ActivitiesCompanion data) {
    return ActivityRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class ActivitiesCompanion extends UpdateCompanion<ActivityRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  const ActivitiesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ActivitiesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required DateTime createdAt,
  }) : name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<ActivityRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ActivitiesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
  }) {
    return ActivitiesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivitiesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ShotsTable extends Shots with TableInfo<$ShotsTable, ShotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<int> activityId = GeneratedColumn<int>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES activities (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _clubIdMeta = const VerificationMeta('clubId');
  @override
  late final GeneratedColumn<String> clubId = GeneratedColumn<String>(
    'club_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ballSpeedMeta = const VerificationMeta(
    'ballSpeed',
  );
  @override
  late final GeneratedColumn<double> ballSpeed = GeneratedColumn<double>(
    'ball_speed',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spinRateMeta = const VerificationMeta(
    'spinRate',
  );
  @override
  late final GeneratedColumn<double> spinRate = GeneratedColumn<double>(
    'spin_rate',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spinAxisMeta = const VerificationMeta(
    'spinAxis',
  );
  @override
  late final GeneratedColumn<double> spinAxis = GeneratedColumn<double>(
    'spin_axis',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _launchDirectionMeta = const VerificationMeta(
    'launchDirection',
  );
  @override
  late final GeneratedColumn<double> launchDirection = GeneratedColumn<double>(
    'launch_direction',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _launchAngleMeta = const VerificationMeta(
    'launchAngle',
  );
  @override
  late final GeneratedColumn<double> launchAngle = GeneratedColumn<double>(
    'launch_angle',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clubSpeedMeta = const VerificationMeta(
    'clubSpeed',
  );
  @override
  late final GeneratedColumn<double> clubSpeed = GeneratedColumn<double>(
    'club_speed',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _apexMeta = const VerificationMeta('apex');
  @override
  late final GeneratedColumn<double> apex = GeneratedColumn<double>(
    'apex',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _runMeta = const VerificationMeta('run');
  @override
  late final GeneratedColumn<double> run = GeneratedColumn<double>(
    'run',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _swingPathMeta = const VerificationMeta(
    'swingPath',
  );
  @override
  late final GeneratedColumn<double> swingPath = GeneratedColumn<double>(
    'swing_path',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _faceAngleMeta = const VerificationMeta(
    'faceAngle',
  );
  @override
  late final GeneratedColumn<double> faceAngle = GeneratedColumn<double>(
    'face_angle',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _angleOfAttackMeta = const VerificationMeta(
    'angleOfAttack',
  );
  @override
  late final GeneratedColumn<double> angleOfAttack = GeneratedColumn<double>(
    'angle_of_attack',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dynamicLoftMeta = const VerificationMeta(
    'dynamicLoft',
  );
  @override
  late final GeneratedColumn<double> dynamicLoft = GeneratedColumn<double>(
    'dynamic_loft',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _horizontalImpactMeta = const VerificationMeta(
    'horizontalImpact',
  );
  @override
  late final GeneratedColumn<double> horizontalImpact = GeneratedColumn<double>(
    'horizontal_impact',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verticalImpactMeta = const VerificationMeta(
    'verticalImpact',
  );
  @override
  late final GeneratedColumn<double> verticalImpact = GeneratedColumn<double>(
    'vertical_impact',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagIdsMeta = const VerificationMeta('tagIds');
  @override
  late final GeneratedColumn<String> tagIds = GeneratedColumn<String>(
    'tag_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    activityId,
    clubId,
    ballSpeed,
    spinRate,
    spinAxis,
    launchDirection,
    launchAngle,
    clubSpeed,
    apex,
    run,
    swingPath,
    faceAngle,
    angleOfAttack,
    dynamicLoft,
    horizontalImpact,
    verticalImpact,
    tagIds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shots';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('club_id')) {
      context.handle(
        _clubIdMeta,
        clubId.isAcceptableOrUnknown(data['club_id']!, _clubIdMeta),
      );
    }
    if (data.containsKey('ball_speed')) {
      context.handle(
        _ballSpeedMeta,
        ballSpeed.isAcceptableOrUnknown(data['ball_speed']!, _ballSpeedMeta),
      );
    } else if (isInserting) {
      context.missing(_ballSpeedMeta);
    }
    if (data.containsKey('spin_rate')) {
      context.handle(
        _spinRateMeta,
        spinRate.isAcceptableOrUnknown(data['spin_rate']!, _spinRateMeta),
      );
    } else if (isInserting) {
      context.missing(_spinRateMeta);
    }
    if (data.containsKey('spin_axis')) {
      context.handle(
        _spinAxisMeta,
        spinAxis.isAcceptableOrUnknown(data['spin_axis']!, _spinAxisMeta),
      );
    } else if (isInserting) {
      context.missing(_spinAxisMeta);
    }
    if (data.containsKey('launch_direction')) {
      context.handle(
        _launchDirectionMeta,
        launchDirection.isAcceptableOrUnknown(
          data['launch_direction']!,
          _launchDirectionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_launchDirectionMeta);
    }
    if (data.containsKey('launch_angle')) {
      context.handle(
        _launchAngleMeta,
        launchAngle.isAcceptableOrUnknown(
          data['launch_angle']!,
          _launchAngleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_launchAngleMeta);
    }
    if (data.containsKey('club_speed')) {
      context.handle(
        _clubSpeedMeta,
        clubSpeed.isAcceptableOrUnknown(data['club_speed']!, _clubSpeedMeta),
      );
    } else if (isInserting) {
      context.missing(_clubSpeedMeta);
    }
    if (data.containsKey('apex')) {
      context.handle(
        _apexMeta,
        apex.isAcceptableOrUnknown(data['apex']!, _apexMeta),
      );
    }
    if (data.containsKey('run')) {
      context.handle(
        _runMeta,
        run.isAcceptableOrUnknown(data['run']!, _runMeta),
      );
    }
    if (data.containsKey('swing_path')) {
      context.handle(
        _swingPathMeta,
        swingPath.isAcceptableOrUnknown(data['swing_path']!, _swingPathMeta),
      );
    }
    if (data.containsKey('face_angle')) {
      context.handle(
        _faceAngleMeta,
        faceAngle.isAcceptableOrUnknown(data['face_angle']!, _faceAngleMeta),
      );
    }
    if (data.containsKey('angle_of_attack')) {
      context.handle(
        _angleOfAttackMeta,
        angleOfAttack.isAcceptableOrUnknown(
          data['angle_of_attack']!,
          _angleOfAttackMeta,
        ),
      );
    }
    if (data.containsKey('dynamic_loft')) {
      context.handle(
        _dynamicLoftMeta,
        dynamicLoft.isAcceptableOrUnknown(
          data['dynamic_loft']!,
          _dynamicLoftMeta,
        ),
      );
    }
    if (data.containsKey('horizontal_impact')) {
      context.handle(
        _horizontalImpactMeta,
        horizontalImpact.isAcceptableOrUnknown(
          data['horizontal_impact']!,
          _horizontalImpactMeta,
        ),
      );
    }
    if (data.containsKey('vertical_impact')) {
      context.handle(
        _verticalImpactMeta,
        verticalImpact.isAcceptableOrUnknown(
          data['vertical_impact']!,
          _verticalImpactMeta,
        ),
      );
    }
    if (data.containsKey('tag_ids')) {
      context.handle(
        _tagIdsMeta,
        tagIds.isAcceptableOrUnknown(data['tag_ids']!, _tagIdsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShotRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}activity_id'],
      )!,
      clubId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}club_id'],
      ),
      ballSpeed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ball_speed'],
      )!,
      spinRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}spin_rate'],
      )!,
      spinAxis: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}spin_axis'],
      )!,
      launchDirection: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}launch_direction'],
      )!,
      launchAngle: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}launch_angle'],
      )!,
      clubSpeed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}club_speed'],
      )!,
      apex: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}apex'],
      ),
      run: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}run'],
      ),
      swingPath: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}swing_path'],
      ),
      faceAngle: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}face_angle'],
      ),
      angleOfAttack: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}angle_of_attack'],
      ),
      dynamicLoft: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dynamic_loft'],
      ),
      horizontalImpact: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}horizontal_impact'],
      ),
      verticalImpact: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}vertical_impact'],
      ),
      tagIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_ids'],
      )!,
    );
  }

  @override
  $ShotsTable createAlias(String alias) {
    return $ShotsTable(attachedDatabase, alias);
  }
}

class ShotRow extends DataClass implements Insertable<ShotRow> {
  final int id;

  /// CASCADE delete — removing an activity removes all its shots.
  final int activityId;
  final String? clubId;
  final double ballSpeed;
  final double spinRate;
  final double spinAxis;
  final double launchDirection;
  final double launchAngle;
  final double clubSpeed;
  final double? apex;
  final double? run;
  final double? swingPath;
  final double? faceAngle;
  final double? angleOfAttack;
  final double? dynamicLoft;
  final double? horizontalImpact;
  final double? verticalImpact;

  /// Comma-separated tag IDs, e.g. "1,3,7". Empty string = no tags.
  final String tagIds;
  const ShotRow({
    required this.id,
    required this.activityId,
    this.clubId,
    required this.ballSpeed,
    required this.spinRate,
    required this.spinAxis,
    required this.launchDirection,
    required this.launchAngle,
    required this.clubSpeed,
    this.apex,
    this.run,
    this.swingPath,
    this.faceAngle,
    this.angleOfAttack,
    this.dynamicLoft,
    this.horizontalImpact,
    this.verticalImpact,
    required this.tagIds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['activity_id'] = Variable<int>(activityId);
    if (!nullToAbsent || clubId != null) {
      map['club_id'] = Variable<String>(clubId);
    }
    map['ball_speed'] = Variable<double>(ballSpeed);
    map['spin_rate'] = Variable<double>(spinRate);
    map['spin_axis'] = Variable<double>(spinAxis);
    map['launch_direction'] = Variable<double>(launchDirection);
    map['launch_angle'] = Variable<double>(launchAngle);
    map['club_speed'] = Variable<double>(clubSpeed);
    if (!nullToAbsent || apex != null) {
      map['apex'] = Variable<double>(apex);
    }
    if (!nullToAbsent || run != null) {
      map['run'] = Variable<double>(run);
    }
    if (!nullToAbsent || swingPath != null) {
      map['swing_path'] = Variable<double>(swingPath);
    }
    if (!nullToAbsent || faceAngle != null) {
      map['face_angle'] = Variable<double>(faceAngle);
    }
    if (!nullToAbsent || angleOfAttack != null) {
      map['angle_of_attack'] = Variable<double>(angleOfAttack);
    }
    if (!nullToAbsent || dynamicLoft != null) {
      map['dynamic_loft'] = Variable<double>(dynamicLoft);
    }
    if (!nullToAbsent || horizontalImpact != null) {
      map['horizontal_impact'] = Variable<double>(horizontalImpact);
    }
    if (!nullToAbsent || verticalImpact != null) {
      map['vertical_impact'] = Variable<double>(verticalImpact);
    }
    map['tag_ids'] = Variable<String>(tagIds);
    return map;
  }

  ShotsCompanion toCompanion(bool nullToAbsent) {
    return ShotsCompanion(
      id: Value(id),
      activityId: Value(activityId),
      clubId: clubId == null && nullToAbsent
          ? const Value.absent()
          : Value(clubId),
      ballSpeed: Value(ballSpeed),
      spinRate: Value(spinRate),
      spinAxis: Value(spinAxis),
      launchDirection: Value(launchDirection),
      launchAngle: Value(launchAngle),
      clubSpeed: Value(clubSpeed),
      apex: apex == null && nullToAbsent ? const Value.absent() : Value(apex),
      run: run == null && nullToAbsent ? const Value.absent() : Value(run),
      swingPath: swingPath == null && nullToAbsent
          ? const Value.absent()
          : Value(swingPath),
      faceAngle: faceAngle == null && nullToAbsent
          ? const Value.absent()
          : Value(faceAngle),
      angleOfAttack: angleOfAttack == null && nullToAbsent
          ? const Value.absent()
          : Value(angleOfAttack),
      dynamicLoft: dynamicLoft == null && nullToAbsent
          ? const Value.absent()
          : Value(dynamicLoft),
      horizontalImpact: horizontalImpact == null && nullToAbsent
          ? const Value.absent()
          : Value(horizontalImpact),
      verticalImpact: verticalImpact == null && nullToAbsent
          ? const Value.absent()
          : Value(verticalImpact),
      tagIds: Value(tagIds),
    );
  }

  factory ShotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShotRow(
      id: serializer.fromJson<int>(json['id']),
      activityId: serializer.fromJson<int>(json['activityId']),
      clubId: serializer.fromJson<String?>(json['clubId']),
      ballSpeed: serializer.fromJson<double>(json['ballSpeed']),
      spinRate: serializer.fromJson<double>(json['spinRate']),
      spinAxis: serializer.fromJson<double>(json['spinAxis']),
      launchDirection: serializer.fromJson<double>(json['launchDirection']),
      launchAngle: serializer.fromJson<double>(json['launchAngle']),
      clubSpeed: serializer.fromJson<double>(json['clubSpeed']),
      apex: serializer.fromJson<double?>(json['apex']),
      run: serializer.fromJson<double?>(json['run']),
      swingPath: serializer.fromJson<double?>(json['swingPath']),
      faceAngle: serializer.fromJson<double?>(json['faceAngle']),
      angleOfAttack: serializer.fromJson<double?>(json['angleOfAttack']),
      dynamicLoft: serializer.fromJson<double?>(json['dynamicLoft']),
      horizontalImpact: serializer.fromJson<double?>(json['horizontalImpact']),
      verticalImpact: serializer.fromJson<double?>(json['verticalImpact']),
      tagIds: serializer.fromJson<String>(json['tagIds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'activityId': serializer.toJson<int>(activityId),
      'clubId': serializer.toJson<String?>(clubId),
      'ballSpeed': serializer.toJson<double>(ballSpeed),
      'spinRate': serializer.toJson<double>(spinRate),
      'spinAxis': serializer.toJson<double>(spinAxis),
      'launchDirection': serializer.toJson<double>(launchDirection),
      'launchAngle': serializer.toJson<double>(launchAngle),
      'clubSpeed': serializer.toJson<double>(clubSpeed),
      'apex': serializer.toJson<double?>(apex),
      'run': serializer.toJson<double?>(run),
      'swingPath': serializer.toJson<double?>(swingPath),
      'faceAngle': serializer.toJson<double?>(faceAngle),
      'angleOfAttack': serializer.toJson<double?>(angleOfAttack),
      'dynamicLoft': serializer.toJson<double?>(dynamicLoft),
      'horizontalImpact': serializer.toJson<double?>(horizontalImpact),
      'verticalImpact': serializer.toJson<double?>(verticalImpact),
      'tagIds': serializer.toJson<String>(tagIds),
    };
  }

  ShotRow copyWith({
    int? id,
    int? activityId,
    Value<String?> clubId = const Value.absent(),
    double? ballSpeed,
    double? spinRate,
    double? spinAxis,
    double? launchDirection,
    double? launchAngle,
    double? clubSpeed,
    Value<double?> apex = const Value.absent(),
    Value<double?> run = const Value.absent(),
    Value<double?> swingPath = const Value.absent(),
    Value<double?> faceAngle = const Value.absent(),
    Value<double?> angleOfAttack = const Value.absent(),
    Value<double?> dynamicLoft = const Value.absent(),
    Value<double?> horizontalImpact = const Value.absent(),
    Value<double?> verticalImpact = const Value.absent(),
    String? tagIds,
  }) => ShotRow(
    id: id ?? this.id,
    activityId: activityId ?? this.activityId,
    clubId: clubId.present ? clubId.value : this.clubId,
    ballSpeed: ballSpeed ?? this.ballSpeed,
    spinRate: spinRate ?? this.spinRate,
    spinAxis: spinAxis ?? this.spinAxis,
    launchDirection: launchDirection ?? this.launchDirection,
    launchAngle: launchAngle ?? this.launchAngle,
    clubSpeed: clubSpeed ?? this.clubSpeed,
    apex: apex.present ? apex.value : this.apex,
    run: run.present ? run.value : this.run,
    swingPath: swingPath.present ? swingPath.value : this.swingPath,
    faceAngle: faceAngle.present ? faceAngle.value : this.faceAngle,
    angleOfAttack: angleOfAttack.present
        ? angleOfAttack.value
        : this.angleOfAttack,
    dynamicLoft: dynamicLoft.present ? dynamicLoft.value : this.dynamicLoft,
    horizontalImpact: horizontalImpact.present
        ? horizontalImpact.value
        : this.horizontalImpact,
    verticalImpact: verticalImpact.present
        ? verticalImpact.value
        : this.verticalImpact,
    tagIds: tagIds ?? this.tagIds,
  );
  ShotRow copyWithCompanion(ShotsCompanion data) {
    return ShotRow(
      id: data.id.present ? data.id.value : this.id,
      activityId: data.activityId.present
          ? data.activityId.value
          : this.activityId,
      clubId: data.clubId.present ? data.clubId.value : this.clubId,
      ballSpeed: data.ballSpeed.present ? data.ballSpeed.value : this.ballSpeed,
      spinRate: data.spinRate.present ? data.spinRate.value : this.spinRate,
      spinAxis: data.spinAxis.present ? data.spinAxis.value : this.spinAxis,
      launchDirection: data.launchDirection.present
          ? data.launchDirection.value
          : this.launchDirection,
      launchAngle: data.launchAngle.present
          ? data.launchAngle.value
          : this.launchAngle,
      clubSpeed: data.clubSpeed.present ? data.clubSpeed.value : this.clubSpeed,
      apex: data.apex.present ? data.apex.value : this.apex,
      run: data.run.present ? data.run.value : this.run,
      swingPath: data.swingPath.present ? data.swingPath.value : this.swingPath,
      faceAngle: data.faceAngle.present ? data.faceAngle.value : this.faceAngle,
      angleOfAttack: data.angleOfAttack.present
          ? data.angleOfAttack.value
          : this.angleOfAttack,
      dynamicLoft: data.dynamicLoft.present
          ? data.dynamicLoft.value
          : this.dynamicLoft,
      horizontalImpact: data.horizontalImpact.present
          ? data.horizontalImpact.value
          : this.horizontalImpact,
      verticalImpact: data.verticalImpact.present
          ? data.verticalImpact.value
          : this.verticalImpact,
      tagIds: data.tagIds.present ? data.tagIds.value : this.tagIds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShotRow(')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('clubId: $clubId, ')
          ..write('ballSpeed: $ballSpeed, ')
          ..write('spinRate: $spinRate, ')
          ..write('spinAxis: $spinAxis, ')
          ..write('launchDirection: $launchDirection, ')
          ..write('launchAngle: $launchAngle, ')
          ..write('clubSpeed: $clubSpeed, ')
          ..write('apex: $apex, ')
          ..write('run: $run, ')
          ..write('swingPath: $swingPath, ')
          ..write('faceAngle: $faceAngle, ')
          ..write('angleOfAttack: $angleOfAttack, ')
          ..write('dynamicLoft: $dynamicLoft, ')
          ..write('horizontalImpact: $horizontalImpact, ')
          ..write('verticalImpact: $verticalImpact, ')
          ..write('tagIds: $tagIds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    activityId,
    clubId,
    ballSpeed,
    spinRate,
    spinAxis,
    launchDirection,
    launchAngle,
    clubSpeed,
    apex,
    run,
    swingPath,
    faceAngle,
    angleOfAttack,
    dynamicLoft,
    horizontalImpact,
    verticalImpact,
    tagIds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShotRow &&
          other.id == this.id &&
          other.activityId == this.activityId &&
          other.clubId == this.clubId &&
          other.ballSpeed == this.ballSpeed &&
          other.spinRate == this.spinRate &&
          other.spinAxis == this.spinAxis &&
          other.launchDirection == this.launchDirection &&
          other.launchAngle == this.launchAngle &&
          other.clubSpeed == this.clubSpeed &&
          other.apex == this.apex &&
          other.run == this.run &&
          other.swingPath == this.swingPath &&
          other.faceAngle == this.faceAngle &&
          other.angleOfAttack == this.angleOfAttack &&
          other.dynamicLoft == this.dynamicLoft &&
          other.horizontalImpact == this.horizontalImpact &&
          other.verticalImpact == this.verticalImpact &&
          other.tagIds == this.tagIds);
}

class ShotsCompanion extends UpdateCompanion<ShotRow> {
  final Value<int> id;
  final Value<int> activityId;
  final Value<String?> clubId;
  final Value<double> ballSpeed;
  final Value<double> spinRate;
  final Value<double> spinAxis;
  final Value<double> launchDirection;
  final Value<double> launchAngle;
  final Value<double> clubSpeed;
  final Value<double?> apex;
  final Value<double?> run;
  final Value<double?> swingPath;
  final Value<double?> faceAngle;
  final Value<double?> angleOfAttack;
  final Value<double?> dynamicLoft;
  final Value<double?> horizontalImpact;
  final Value<double?> verticalImpact;
  final Value<String> tagIds;
  const ShotsCompanion({
    this.id = const Value.absent(),
    this.activityId = const Value.absent(),
    this.clubId = const Value.absent(),
    this.ballSpeed = const Value.absent(),
    this.spinRate = const Value.absent(),
    this.spinAxis = const Value.absent(),
    this.launchDirection = const Value.absent(),
    this.launchAngle = const Value.absent(),
    this.clubSpeed = const Value.absent(),
    this.apex = const Value.absent(),
    this.run = const Value.absent(),
    this.swingPath = const Value.absent(),
    this.faceAngle = const Value.absent(),
    this.angleOfAttack = const Value.absent(),
    this.dynamicLoft = const Value.absent(),
    this.horizontalImpact = const Value.absent(),
    this.verticalImpact = const Value.absent(),
    this.tagIds = const Value.absent(),
  });
  ShotsCompanion.insert({
    this.id = const Value.absent(),
    required int activityId,
    this.clubId = const Value.absent(),
    required double ballSpeed,
    required double spinRate,
    required double spinAxis,
    required double launchDirection,
    required double launchAngle,
    required double clubSpeed,
    this.apex = const Value.absent(),
    this.run = const Value.absent(),
    this.swingPath = const Value.absent(),
    this.faceAngle = const Value.absent(),
    this.angleOfAttack = const Value.absent(),
    this.dynamicLoft = const Value.absent(),
    this.horizontalImpact = const Value.absent(),
    this.verticalImpact = const Value.absent(),
    this.tagIds = const Value.absent(),
  }) : activityId = Value(activityId),
       ballSpeed = Value(ballSpeed),
       spinRate = Value(spinRate),
       spinAxis = Value(spinAxis),
       launchDirection = Value(launchDirection),
       launchAngle = Value(launchAngle),
       clubSpeed = Value(clubSpeed);
  static Insertable<ShotRow> custom({
    Expression<int>? id,
    Expression<int>? activityId,
    Expression<String>? clubId,
    Expression<double>? ballSpeed,
    Expression<double>? spinRate,
    Expression<double>? spinAxis,
    Expression<double>? launchDirection,
    Expression<double>? launchAngle,
    Expression<double>? clubSpeed,
    Expression<double>? apex,
    Expression<double>? run,
    Expression<double>? swingPath,
    Expression<double>? faceAngle,
    Expression<double>? angleOfAttack,
    Expression<double>? dynamicLoft,
    Expression<double>? horizontalImpact,
    Expression<double>? verticalImpact,
    Expression<String>? tagIds,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (activityId != null) 'activity_id': activityId,
      if (clubId != null) 'club_id': clubId,
      if (ballSpeed != null) 'ball_speed': ballSpeed,
      if (spinRate != null) 'spin_rate': spinRate,
      if (spinAxis != null) 'spin_axis': spinAxis,
      if (launchDirection != null) 'launch_direction': launchDirection,
      if (launchAngle != null) 'launch_angle': launchAngle,
      if (clubSpeed != null) 'club_speed': clubSpeed,
      if (apex != null) 'apex': apex,
      if (run != null) 'run': run,
      if (swingPath != null) 'swing_path': swingPath,
      if (faceAngle != null) 'face_angle': faceAngle,
      if (angleOfAttack != null) 'angle_of_attack': angleOfAttack,
      if (dynamicLoft != null) 'dynamic_loft': dynamicLoft,
      if (horizontalImpact != null) 'horizontal_impact': horizontalImpact,
      if (verticalImpact != null) 'vertical_impact': verticalImpact,
      if (tagIds != null) 'tag_ids': tagIds,
    });
  }

  ShotsCompanion copyWith({
    Value<int>? id,
    Value<int>? activityId,
    Value<String?>? clubId,
    Value<double>? ballSpeed,
    Value<double>? spinRate,
    Value<double>? spinAxis,
    Value<double>? launchDirection,
    Value<double>? launchAngle,
    Value<double>? clubSpeed,
    Value<double?>? apex,
    Value<double?>? run,
    Value<double?>? swingPath,
    Value<double?>? faceAngle,
    Value<double?>? angleOfAttack,
    Value<double?>? dynamicLoft,
    Value<double?>? horizontalImpact,
    Value<double?>? verticalImpact,
    Value<String>? tagIds,
  }) {
    return ShotsCompanion(
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      clubId: clubId ?? this.clubId,
      ballSpeed: ballSpeed ?? this.ballSpeed,
      spinRate: spinRate ?? this.spinRate,
      spinAxis: spinAxis ?? this.spinAxis,
      launchDirection: launchDirection ?? this.launchDirection,
      launchAngle: launchAngle ?? this.launchAngle,
      clubSpeed: clubSpeed ?? this.clubSpeed,
      apex: apex ?? this.apex,
      run: run ?? this.run,
      swingPath: swingPath ?? this.swingPath,
      faceAngle: faceAngle ?? this.faceAngle,
      angleOfAttack: angleOfAttack ?? this.angleOfAttack,
      dynamicLoft: dynamicLoft ?? this.dynamicLoft,
      horizontalImpact: horizontalImpact ?? this.horizontalImpact,
      verticalImpact: verticalImpact ?? this.verticalImpact,
      tagIds: tagIds ?? this.tagIds,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<int>(activityId.value);
    }
    if (clubId.present) {
      map['club_id'] = Variable<String>(clubId.value);
    }
    if (ballSpeed.present) {
      map['ball_speed'] = Variable<double>(ballSpeed.value);
    }
    if (spinRate.present) {
      map['spin_rate'] = Variable<double>(spinRate.value);
    }
    if (spinAxis.present) {
      map['spin_axis'] = Variable<double>(spinAxis.value);
    }
    if (launchDirection.present) {
      map['launch_direction'] = Variable<double>(launchDirection.value);
    }
    if (launchAngle.present) {
      map['launch_angle'] = Variable<double>(launchAngle.value);
    }
    if (clubSpeed.present) {
      map['club_speed'] = Variable<double>(clubSpeed.value);
    }
    if (apex.present) {
      map['apex'] = Variable<double>(apex.value);
    }
    if (run.present) {
      map['run'] = Variable<double>(run.value);
    }
    if (swingPath.present) {
      map['swing_path'] = Variable<double>(swingPath.value);
    }
    if (faceAngle.present) {
      map['face_angle'] = Variable<double>(faceAngle.value);
    }
    if (angleOfAttack.present) {
      map['angle_of_attack'] = Variable<double>(angleOfAttack.value);
    }
    if (dynamicLoft.present) {
      map['dynamic_loft'] = Variable<double>(dynamicLoft.value);
    }
    if (horizontalImpact.present) {
      map['horizontal_impact'] = Variable<double>(horizontalImpact.value);
    }
    if (verticalImpact.present) {
      map['vertical_impact'] = Variable<double>(verticalImpact.value);
    }
    if (tagIds.present) {
      map['tag_ids'] = Variable<String>(tagIds.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShotsCompanion(')
          ..write('id: $id, ')
          ..write('activityId: $activityId, ')
          ..write('clubId: $clubId, ')
          ..write('ballSpeed: $ballSpeed, ')
          ..write('spinRate: $spinRate, ')
          ..write('spinAxis: $spinAxis, ')
          ..write('launchDirection: $launchDirection, ')
          ..write('launchAngle: $launchAngle, ')
          ..write('clubSpeed: $clubSpeed, ')
          ..write('apex: $apex, ')
          ..write('run: $run, ')
          ..write('swingPath: $swingPath, ')
          ..write('faceAngle: $faceAngle, ')
          ..write('angleOfAttack: $angleOfAttack, ')
          ..write('dynamicLoft: $dynamicLoft, ')
          ..write('horizontalImpact: $horizontalImpact, ')
          ..write('verticalImpact: $verticalImpact, ')
          ..write('tagIds: $tagIds')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, colorValue];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagRow extends DataClass implements Insertable<TagRow> {
  final int id;
  final String name;

  /// Stored as ARGB integer — reconstruct with Color(colorValue).
  final int colorValue;
  const TagRow({
    required this.id,
    required this.name,
    required this.colorValue,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      colorValue: Value(colorValue),
    );
  }

  factory TagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
    };
  }

  TagRow copyWith({int? id, String? name, int? colorValue}) => TagRow(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
  );
  TagRow copyWithCompanion(TagsCompanion data) {
    return TagRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, colorValue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorValue == this.colorValue);
}

class TagsCompanion extends UpdateCompanion<TagRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> colorValue;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
  });
  TagsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int colorValue,
  }) : name = Value(name),
       colorValue = Value(colorValue);
  static Insertable<TagRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? colorValue,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
    });
  }

  TagsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? colorValue,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue')
          ..write(')'))
        .toString();
  }
}

class $SavedClubsTable extends SavedClubs
    with TableInfo<$SavedClubsTable, SavedClubRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedClubsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shortNameMeta = const VerificationMeta(
    'shortName',
  );
  @override
  late final GeneratedColumn<String> shortName = GeneratedColumn<String>(
    'short_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manufacturerMeta = const VerificationMeta(
    'manufacturer',
  );
  @override
  late final GeneratedColumn<String> manufacturer = GeneratedColumn<String>(
    'manufacturer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    shortName,
    manufacturer,
    model,
    colorValue,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_clubs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedClubRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('short_name')) {
      context.handle(
        _shortNameMeta,
        shortName.isAcceptableOrUnknown(data['short_name']!, _shortNameMeta),
      );
    } else if (isInserting) {
      context.missing(_shortNameMeta);
    }
    if (data.containsKey('manufacturer')) {
      context.handle(
        _manufacturerMeta,
        manufacturer.isAcceptableOrUnknown(
          data['manufacturer']!,
          _manufacturerMeta,
        ),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedClubRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedClubRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      shortName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}short_name'],
      )!,
      manufacturer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manufacturer'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
    );
  }

  @override
  $SavedClubsTable createAlias(String alias) {
    return $SavedClubsTable(attachedDatabase, alias);
  }
}

class SavedClubRow extends DataClass implements Insertable<SavedClubRow> {
  /// Matches [Club.id] — natural primary key (e.g. 'dr', '7i').
  final String id;
  final String shortName;
  final String? manufacturer;
  final String? model;

  /// Color stored as ARGB integer — reconstruct with Color(colorValue).
  final int colorValue;
  const SavedClubRow({
    required this.id,
    required this.shortName,
    this.manufacturer,
    this.model,
    required this.colorValue,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['short_name'] = Variable<String>(shortName);
    if (!nullToAbsent || manufacturer != null) {
      map['manufacturer'] = Variable<String>(manufacturer);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    map['color_value'] = Variable<int>(colorValue);
    return map;
  }

  SavedClubsCompanion toCompanion(bool nullToAbsent) {
    return SavedClubsCompanion(
      id: Value(id),
      shortName: Value(shortName),
      manufacturer: manufacturer == null && nullToAbsent
          ? const Value.absent()
          : Value(manufacturer),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      colorValue: Value(colorValue),
    );
  }

  factory SavedClubRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedClubRow(
      id: serializer.fromJson<String>(json['id']),
      shortName: serializer.fromJson<String>(json['shortName']),
      manufacturer: serializer.fromJson<String?>(json['manufacturer']),
      model: serializer.fromJson<String?>(json['model']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'shortName': serializer.toJson<String>(shortName),
      'manufacturer': serializer.toJson<String?>(manufacturer),
      'model': serializer.toJson<String?>(model),
      'colorValue': serializer.toJson<int>(colorValue),
    };
  }

  SavedClubRow copyWith({
    String? id,
    String? shortName,
    Value<String?> manufacturer = const Value.absent(),
    Value<String?> model = const Value.absent(),
    int? colorValue,
  }) => SavedClubRow(
    id: id ?? this.id,
    shortName: shortName ?? this.shortName,
    manufacturer: manufacturer.present ? manufacturer.value : this.manufacturer,
    model: model.present ? model.value : this.model,
    colorValue: colorValue ?? this.colorValue,
  );
  SavedClubRow copyWithCompanion(SavedClubsCompanion data) {
    return SavedClubRow(
      id: data.id.present ? data.id.value : this.id,
      shortName: data.shortName.present ? data.shortName.value : this.shortName,
      manufacturer: data.manufacturer.present
          ? data.manufacturer.value
          : this.manufacturer,
      model: data.model.present ? data.model.value : this.model,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedClubRow(')
          ..write('id: $id, ')
          ..write('shortName: $shortName, ')
          ..write('manufacturer: $manufacturer, ')
          ..write('model: $model, ')
          ..write('colorValue: $colorValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, shortName, manufacturer, model, colorValue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedClubRow &&
          other.id == this.id &&
          other.shortName == this.shortName &&
          other.manufacturer == this.manufacturer &&
          other.model == this.model &&
          other.colorValue == this.colorValue);
}

class SavedClubsCompanion extends UpdateCompanion<SavedClubRow> {
  final Value<String> id;
  final Value<String> shortName;
  final Value<String?> manufacturer;
  final Value<String?> model;
  final Value<int> colorValue;
  final Value<int> rowid;
  const SavedClubsCompanion({
    this.id = const Value.absent(),
    this.shortName = const Value.absent(),
    this.manufacturer = const Value.absent(),
    this.model = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedClubsCompanion.insert({
    required String id,
    required String shortName,
    this.manufacturer = const Value.absent(),
    this.model = const Value.absent(),
    required int colorValue,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       shortName = Value(shortName),
       colorValue = Value(colorValue);
  static Insertable<SavedClubRow> custom({
    Expression<String>? id,
    Expression<String>? shortName,
    Expression<String>? manufacturer,
    Expression<String>? model,
    Expression<int>? colorValue,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (shortName != null) 'short_name': shortName,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (model != null) 'model': model,
      if (colorValue != null) 'color_value': colorValue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedClubsCompanion copyWith({
    Value<String>? id,
    Value<String>? shortName,
    Value<String?>? manufacturer,
    Value<String?>? model,
    Value<int>? colorValue,
    Value<int>? rowid,
  }) {
    return SavedClubsCompanion(
      id: id ?? this.id,
      shortName: shortName ?? this.shortName,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      colorValue: colorValue ?? this.colorValue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (shortName.present) {
      map['short_name'] = Variable<String>(shortName.value);
    }
    if (manufacturer.present) {
      map['manufacturer'] = Variable<String>(manufacturer.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedClubsCompanion(')
          ..write('id: $id, ')
          ..write('shortName: $shortName, ')
          ..write('manufacturer: $manufacturer, ')
          ..write('model: $model, ')
          ..write('colorValue: $colorValue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ActivitiesTable activities = $ActivitiesTable(this);
  late final $ShotsTable shots = $ShotsTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $SavedClubsTable savedClubs = $SavedClubsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    activities,
    shots,
    tags,
    savedClubs,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('shots', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ActivitiesTableCreateCompanionBuilder =
    ActivitiesCompanion Function({
      Value<int> id,
      required String name,
      required DateTime createdAt,
    });
typedef $$ActivitiesTableUpdateCompanionBuilder =
    ActivitiesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<DateTime> createdAt,
    });

final class $$ActivitiesTableReferences
    extends BaseReferences<_$AppDatabase, $ActivitiesTable, ActivityRow> {
  $$ActivitiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ShotsTable, List<ShotRow>> _shotsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.shots,
    aliasName: $_aliasNameGenerator(db.activities.id, db.shots.activityId),
  );

  $$ShotsTableProcessedTableManager get shotsRefs {
    final manager = $$ShotsTableTableManager(
      $_db,
      $_db.shots,
    ).filter((f) => f.activityId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_shotsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActivitiesTableFilterComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> shotsRefs(
    Expression<bool> Function($$ShotsTableFilterComposer f) f,
  ) {
    final $$ShotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shots,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotsTableFilterComposer(
            $db: $db,
            $table: $db.shots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivitiesTable> {
  $$ActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> shotsRefs<T extends Object>(
    Expression<T> Function($$ShotsTableAnnotationComposer a) f,
  ) {
    final $$ShotsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shots,
      getReferencedColumn: (t) => t.activityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShotsTableAnnotationComposer(
            $db: $db,
            $table: $db.shots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivitiesTable,
          ActivityRow,
          $$ActivitiesTableFilterComposer,
          $$ActivitiesTableOrderingComposer,
          $$ActivitiesTableAnnotationComposer,
          $$ActivitiesTableCreateCompanionBuilder,
          $$ActivitiesTableUpdateCompanionBuilder,
          (ActivityRow, $$ActivitiesTableReferences),
          ActivityRow,
          PrefetchHooks Function({bool shotsRefs})
        > {
  $$ActivitiesTableTableManager(_$AppDatabase db, $ActivitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) =>
                  ActivitiesCompanion(id: id, name: name, createdAt: createdAt),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required DateTime createdAt,
              }) => ActivitiesCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActivitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shotsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (shotsRefs) db.shots],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (shotsRefs)
                    await $_getPrefetchedData<
                      ActivityRow,
                      $ActivitiesTable,
                      ShotRow
                    >(
                      currentTable: table,
                      referencedTable: $$ActivitiesTableReferences
                          ._shotsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ActivitiesTableReferences(db, table, p0).shotsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.activityId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivitiesTable,
      ActivityRow,
      $$ActivitiesTableFilterComposer,
      $$ActivitiesTableOrderingComposer,
      $$ActivitiesTableAnnotationComposer,
      $$ActivitiesTableCreateCompanionBuilder,
      $$ActivitiesTableUpdateCompanionBuilder,
      (ActivityRow, $$ActivitiesTableReferences),
      ActivityRow,
      PrefetchHooks Function({bool shotsRefs})
    >;
typedef $$ShotsTableCreateCompanionBuilder =
    ShotsCompanion Function({
      Value<int> id,
      required int activityId,
      Value<String?> clubId,
      required double ballSpeed,
      required double spinRate,
      required double spinAxis,
      required double launchDirection,
      required double launchAngle,
      required double clubSpeed,
      Value<double?> apex,
      Value<double?> run,
      Value<double?> swingPath,
      Value<double?> faceAngle,
      Value<double?> angleOfAttack,
      Value<double?> dynamicLoft,
      Value<double?> horizontalImpact,
      Value<double?> verticalImpact,
      Value<String> tagIds,
    });
typedef $$ShotsTableUpdateCompanionBuilder =
    ShotsCompanion Function({
      Value<int> id,
      Value<int> activityId,
      Value<String?> clubId,
      Value<double> ballSpeed,
      Value<double> spinRate,
      Value<double> spinAxis,
      Value<double> launchDirection,
      Value<double> launchAngle,
      Value<double> clubSpeed,
      Value<double?> apex,
      Value<double?> run,
      Value<double?> swingPath,
      Value<double?> faceAngle,
      Value<double?> angleOfAttack,
      Value<double?> dynamicLoft,
      Value<double?> horizontalImpact,
      Value<double?> verticalImpact,
      Value<String> tagIds,
    });

final class $$ShotsTableReferences
    extends BaseReferences<_$AppDatabase, $ShotsTable, ShotRow> {
  $$ShotsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ActivitiesTable _activityIdTable(_$AppDatabase db) => db.activities
      .createAlias($_aliasNameGenerator(db.shots.activityId, db.activities.id));

  $$ActivitiesTableProcessedTableManager get activityId {
    final $_column = $_itemColumn<int>('activity_id')!;

    final manager = $$ActivitiesTableTableManager(
      $_db,
      $_db.activities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_activityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ShotsTableFilterComposer extends Composer<_$AppDatabase, $ShotsTable> {
  $$ShotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clubId => $composableBuilder(
    column: $table.clubId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ballSpeed => $composableBuilder(
    column: $table.ballSpeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get spinRate => $composableBuilder(
    column: $table.spinRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get spinAxis => $composableBuilder(
    column: $table.spinAxis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get launchDirection => $composableBuilder(
    column: $table.launchDirection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get launchAngle => $composableBuilder(
    column: $table.launchAngle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get clubSpeed => $composableBuilder(
    column: $table.clubSpeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get apex => $composableBuilder(
    column: $table.apex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get run => $composableBuilder(
    column: $table.run,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get swingPath => $composableBuilder(
    column: $table.swingPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get faceAngle => $composableBuilder(
    column: $table.faceAngle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get angleOfAttack => $composableBuilder(
    column: $table.angleOfAttack,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get dynamicLoft => $composableBuilder(
    column: $table.dynamicLoft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get horizontalImpact => $composableBuilder(
    column: $table.horizontalImpact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get verticalImpact => $composableBuilder(
    column: $table.verticalImpact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagIds => $composableBuilder(
    column: $table.tagIds,
    builder: (column) => ColumnFilters(column),
  );

  $$ActivitiesTableFilterComposer get activityId {
    final $$ActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShotsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShotsTable> {
  $$ShotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clubId => $composableBuilder(
    column: $table.clubId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ballSpeed => $composableBuilder(
    column: $table.ballSpeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get spinRate => $composableBuilder(
    column: $table.spinRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get spinAxis => $composableBuilder(
    column: $table.spinAxis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get launchDirection => $composableBuilder(
    column: $table.launchDirection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get launchAngle => $composableBuilder(
    column: $table.launchAngle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get clubSpeed => $composableBuilder(
    column: $table.clubSpeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get apex => $composableBuilder(
    column: $table.apex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get run => $composableBuilder(
    column: $table.run,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get swingPath => $composableBuilder(
    column: $table.swingPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get faceAngle => $composableBuilder(
    column: $table.faceAngle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get angleOfAttack => $composableBuilder(
    column: $table.angleOfAttack,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get dynamicLoft => $composableBuilder(
    column: $table.dynamicLoft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get horizontalImpact => $composableBuilder(
    column: $table.horizontalImpact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get verticalImpact => $composableBuilder(
    column: $table.verticalImpact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagIds => $composableBuilder(
    column: $table.tagIds,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivitiesTableOrderingComposer get activityId {
    final $$ActivitiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableOrderingComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShotsTable> {
  $$ShotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clubId =>
      $composableBuilder(column: $table.clubId, builder: (column) => column);

  GeneratedColumn<double> get ballSpeed =>
      $composableBuilder(column: $table.ballSpeed, builder: (column) => column);

  GeneratedColumn<double> get spinRate =>
      $composableBuilder(column: $table.spinRate, builder: (column) => column);

  GeneratedColumn<double> get spinAxis =>
      $composableBuilder(column: $table.spinAxis, builder: (column) => column);

  GeneratedColumn<double> get launchDirection => $composableBuilder(
    column: $table.launchDirection,
    builder: (column) => column,
  );

  GeneratedColumn<double> get launchAngle => $composableBuilder(
    column: $table.launchAngle,
    builder: (column) => column,
  );

  GeneratedColumn<double> get clubSpeed =>
      $composableBuilder(column: $table.clubSpeed, builder: (column) => column);

  GeneratedColumn<double> get apex =>
      $composableBuilder(column: $table.apex, builder: (column) => column);

  GeneratedColumn<double> get run =>
      $composableBuilder(column: $table.run, builder: (column) => column);

  GeneratedColumn<double> get swingPath =>
      $composableBuilder(column: $table.swingPath, builder: (column) => column);

  GeneratedColumn<double> get faceAngle =>
      $composableBuilder(column: $table.faceAngle, builder: (column) => column);

  GeneratedColumn<double> get angleOfAttack => $composableBuilder(
    column: $table.angleOfAttack,
    builder: (column) => column,
  );

  GeneratedColumn<double> get dynamicLoft => $composableBuilder(
    column: $table.dynamicLoft,
    builder: (column) => column,
  );

  GeneratedColumn<double> get horizontalImpact => $composableBuilder(
    column: $table.horizontalImpact,
    builder: (column) => column,
  );

  GeneratedColumn<double> get verticalImpact => $composableBuilder(
    column: $table.verticalImpact,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tagIds =>
      $composableBuilder(column: $table.tagIds, builder: (column) => column);

  $$ActivitiesTableAnnotationComposer get activityId {
    final $$ActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activityId,
      referencedTable: $db.activities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.activities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShotsTable,
          ShotRow,
          $$ShotsTableFilterComposer,
          $$ShotsTableOrderingComposer,
          $$ShotsTableAnnotationComposer,
          $$ShotsTableCreateCompanionBuilder,
          $$ShotsTableUpdateCompanionBuilder,
          (ShotRow, $$ShotsTableReferences),
          ShotRow,
          PrefetchHooks Function({bool activityId})
        > {
  $$ShotsTableTableManager(_$AppDatabase db, $ShotsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> activityId = const Value.absent(),
                Value<String?> clubId = const Value.absent(),
                Value<double> ballSpeed = const Value.absent(),
                Value<double> spinRate = const Value.absent(),
                Value<double> spinAxis = const Value.absent(),
                Value<double> launchDirection = const Value.absent(),
                Value<double> launchAngle = const Value.absent(),
                Value<double> clubSpeed = const Value.absent(),
                Value<double?> apex = const Value.absent(),
                Value<double?> run = const Value.absent(),
                Value<double?> swingPath = const Value.absent(),
                Value<double?> faceAngle = const Value.absent(),
                Value<double?> angleOfAttack = const Value.absent(),
                Value<double?> dynamicLoft = const Value.absent(),
                Value<double?> horizontalImpact = const Value.absent(),
                Value<double?> verticalImpact = const Value.absent(),
                Value<String> tagIds = const Value.absent(),
              }) => ShotsCompanion(
                id: id,
                activityId: activityId,
                clubId: clubId,
                ballSpeed: ballSpeed,
                spinRate: spinRate,
                spinAxis: spinAxis,
                launchDirection: launchDirection,
                launchAngle: launchAngle,
                clubSpeed: clubSpeed,
                apex: apex,
                run: run,
                swingPath: swingPath,
                faceAngle: faceAngle,
                angleOfAttack: angleOfAttack,
                dynamicLoft: dynamicLoft,
                horizontalImpact: horizontalImpact,
                verticalImpact: verticalImpact,
                tagIds: tagIds,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int activityId,
                Value<String?> clubId = const Value.absent(),
                required double ballSpeed,
                required double spinRate,
                required double spinAxis,
                required double launchDirection,
                required double launchAngle,
                required double clubSpeed,
                Value<double?> apex = const Value.absent(),
                Value<double?> run = const Value.absent(),
                Value<double?> swingPath = const Value.absent(),
                Value<double?> faceAngle = const Value.absent(),
                Value<double?> angleOfAttack = const Value.absent(),
                Value<double?> dynamicLoft = const Value.absent(),
                Value<double?> horizontalImpact = const Value.absent(),
                Value<double?> verticalImpact = const Value.absent(),
                Value<String> tagIds = const Value.absent(),
              }) => ShotsCompanion.insert(
                id: id,
                activityId: activityId,
                clubId: clubId,
                ballSpeed: ballSpeed,
                spinRate: spinRate,
                spinAxis: spinAxis,
                launchDirection: launchDirection,
                launchAngle: launchAngle,
                clubSpeed: clubSpeed,
                apex: apex,
                run: run,
                swingPath: swingPath,
                faceAngle: faceAngle,
                angleOfAttack: angleOfAttack,
                dynamicLoft: dynamicLoft,
                horizontalImpact: horizontalImpact,
                verticalImpact: verticalImpact,
                tagIds: tagIds,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$ShotsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({activityId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activityId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.activityId,
                                referencedTable: $$ShotsTableReferences
                                    ._activityIdTable(db),
                                referencedColumn: $$ShotsTableReferences
                                    ._activityIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ShotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShotsTable,
      ShotRow,
      $$ShotsTableFilterComposer,
      $$ShotsTableOrderingComposer,
      $$ShotsTableAnnotationComposer,
      $$ShotsTableCreateCompanionBuilder,
      $$ShotsTableUpdateCompanionBuilder,
      (ShotRow, $$ShotsTableReferences),
      ShotRow,
      PrefetchHooks Function({bool activityId})
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      Value<int> id,
      required String name,
      required int colorValue,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> colorValue,
    });

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          TagRow,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagRow, BaseReferences<_$AppDatabase, $TagsTable, TagRow>),
          TagRow,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
              }) => TagsCompanion(id: id, name: name, colorValue: colorValue),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int colorValue,
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                colorValue: colorValue,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      TagRow,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagRow, BaseReferences<_$AppDatabase, $TagsTable, TagRow>),
      TagRow,
      PrefetchHooks Function()
    >;
typedef $$SavedClubsTableCreateCompanionBuilder =
    SavedClubsCompanion Function({
      required String id,
      required String shortName,
      Value<String?> manufacturer,
      Value<String?> model,
      required int colorValue,
      Value<int> rowid,
    });
typedef $$SavedClubsTableUpdateCompanionBuilder =
    SavedClubsCompanion Function({
      Value<String> id,
      Value<String> shortName,
      Value<String?> manufacturer,
      Value<String?> model,
      Value<int> colorValue,
      Value<int> rowid,
    });

class $$SavedClubsTableFilterComposer
    extends Composer<_$AppDatabase, $SavedClubsTable> {
  $$SavedClubsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manufacturer => $composableBuilder(
    column: $table.manufacturer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedClubsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedClubsTable> {
  $$SavedClubsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shortName => $composableBuilder(
    column: $table.shortName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manufacturer => $composableBuilder(
    column: $table.manufacturer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedClubsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedClubsTable> {
  $$SavedClubsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get shortName =>
      $composableBuilder(column: $table.shortName, builder: (column) => column);

  GeneratedColumn<String> get manufacturer => $composableBuilder(
    column: $table.manufacturer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );
}

class $$SavedClubsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedClubsTable,
          SavedClubRow,
          $$SavedClubsTableFilterComposer,
          $$SavedClubsTableOrderingComposer,
          $$SavedClubsTableAnnotationComposer,
          $$SavedClubsTableCreateCompanionBuilder,
          $$SavedClubsTableUpdateCompanionBuilder,
          (
            SavedClubRow,
            BaseReferences<_$AppDatabase, $SavedClubsTable, SavedClubRow>,
          ),
          SavedClubRow,
          PrefetchHooks Function()
        > {
  $$SavedClubsTableTableManager(_$AppDatabase db, $SavedClubsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedClubsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedClubsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedClubsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> shortName = const Value.absent(),
                Value<String?> manufacturer = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedClubsCompanion(
                id: id,
                shortName: shortName,
                manufacturer: manufacturer,
                model: model,
                colorValue: colorValue,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String shortName,
                Value<String?> manufacturer = const Value.absent(),
                Value<String?> model = const Value.absent(),
                required int colorValue,
                Value<int> rowid = const Value.absent(),
              }) => SavedClubsCompanion.insert(
                id: id,
                shortName: shortName,
                manufacturer: manufacturer,
                model: model,
                colorValue: colorValue,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedClubsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedClubsTable,
      SavedClubRow,
      $$SavedClubsTableFilterComposer,
      $$SavedClubsTableOrderingComposer,
      $$SavedClubsTableAnnotationComposer,
      $$SavedClubsTableCreateCompanionBuilder,
      $$SavedClubsTableUpdateCompanionBuilder,
      (
        SavedClubRow,
        BaseReferences<_$AppDatabase, $SavedClubsTable, SavedClubRow>,
      ),
      SavedClubRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ActivitiesTableTableManager get activities =>
      $$ActivitiesTableTableManager(_db, _db.activities);
  $$ShotsTableTableManager get shots =>
      $$ShotsTableTableManager(_db, _db.shots);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$SavedClubsTableTableManager get savedClubs =>
      $$SavedClubsTableTableManager(_db, _db.savedClubs);
}
