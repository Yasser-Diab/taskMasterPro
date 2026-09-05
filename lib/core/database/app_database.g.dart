// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalProfilesTable extends LocalProfiles
    with TableInfo<$LocalProfilesTable, LocalProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genderIdentityMeta = const VerificationMeta(
    'genderIdentity',
  );
  @override
  late final GeneratedColumn<String> genderIdentity = GeneratedColumn<String>(
    'gender_identity',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateOfBirthMeta = const VerificationMeta(
    'dateOfBirth',
  );
  @override
  late final GeneratedColumn<DateTime> dateOfBirth = GeneratedColumn<DateTime>(
    'date_of_birth',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightCmMeta = const VerificationMeta(
    'heightCm',
  );
  @override
  late final GeneratedColumn<double> heightCm = GeneratedColumn<double>(
    'height_cm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _onboardingCompletedMeta =
      const VerificationMeta('onboardingCompleted');
  @override
  late final GeneratedColumn<bool> onboardingCompleted = GeneratedColumn<bool>(
    'onboarding_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("onboarding_completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceIdMeta = const VerificationMeta(
    'updatedByDeviceId',
  );
  @override
  late final GeneratedColumn<String> updatedByDeviceId =
      GeneratedColumn<String>(
        'updated_by_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCommandIdMeta = const VerificationMeta(
    'lastCommandId',
  );
  @override
  late final GeneratedColumn<String> lastCommandId = GeneratedColumn<String>(
    'last_command_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    displayName,
    email,
    imagePath,
    genderIdentity,
    dateOfBirth,
    heightCm,
    onboardingCompleted,
    revision,
    createdAt,
    updatedAt,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('gender_identity')) {
      context.handle(
        _genderIdentityMeta,
        genderIdentity.isAcceptableOrUnknown(
          data['gender_identity']!,
          _genderIdentityMeta,
        ),
      );
    }
    if (data.containsKey('date_of_birth')) {
      context.handle(
        _dateOfBirthMeta,
        dateOfBirth.isAcceptableOrUnknown(
          data['date_of_birth']!,
          _dateOfBirthMeta,
        ),
      );
    }
    if (data.containsKey('height_cm')) {
      context.handle(
        _heightCmMeta,
        heightCm.isAcceptableOrUnknown(data['height_cm']!, _heightCmMeta),
      );
    }
    if (data.containsKey('onboarding_completed')) {
      context.handle(
        _onboardingCompletedMeta,
        onboardingCompleted.isAcceptableOrUnknown(
          data['onboarding_completed']!,
          _onboardingCompletedMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device_id')) {
      context.handle(
        _updatedByDeviceIdMeta,
        updatedByDeviceId.isAcceptableOrUnknown(
          data['updated_by_device_id']!,
          _updatedByDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('last_command_id')) {
      context.handle(
        _lastCommandIdMeta,
        lastCommandId.isAcceptableOrUnknown(
          data['last_command_id']!,
          _lastCommandIdMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      genderIdentity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender_identity'],
      ),
      dateOfBirth: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_of_birth'],
      ),
      heightCm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height_cm'],
      ),
      onboardingCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}onboarding_completed'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device_id'],
      ),
      lastCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_command_id'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalProfilesTable createAlias(String alias) {
    return $LocalProfilesTable(attachedDatabase, alias);
  }
}

class LocalProfile extends DataClass implements Insertable<LocalProfile> {
  final String id;
  final String userId;
  final String displayName;
  final String? email;
  final String? imagePath;
  final String? genderIdentity;
  final DateTime? dateOfBirth;
  final double? heightCm;
  final bool onboardingCompleted;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? updatedByDeviceId;
  final String? lastCommandId;
  final DateTime? deletedAt;
  const LocalProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    this.email,
    this.imagePath,
    this.genderIdentity,
    this.dateOfBirth,
    this.heightCm,
    required this.onboardingCompleted,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.updatedByDeviceId,
    this.lastCommandId,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    if (!nullToAbsent || genderIdentity != null) {
      map['gender_identity'] = Variable<String>(genderIdentity);
    }
    if (!nullToAbsent || dateOfBirth != null) {
      map['date_of_birth'] = Variable<DateTime>(dateOfBirth);
    }
    if (!nullToAbsent || heightCm != null) {
      map['height_cm'] = Variable<double>(heightCm);
    }
    map['onboarding_completed'] = Variable<bool>(onboardingCompleted);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || updatedByDeviceId != null) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId);
    }
    if (!nullToAbsent || lastCommandId != null) {
      map['last_command_id'] = Variable<String>(lastCommandId);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalProfilesCompanion toCompanion(bool nullToAbsent) {
    return LocalProfilesCompanion(
      id: Value(id),
      userId: Value(userId),
      displayName: Value(displayName),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      genderIdentity: genderIdentity == null && nullToAbsent
          ? const Value.absent()
          : Value(genderIdentity),
      dateOfBirth: dateOfBirth == null && nullToAbsent
          ? const Value.absent()
          : Value(dateOfBirth),
      heightCm: heightCm == null && nullToAbsent
          ? const Value.absent()
          : Value(heightCm),
      onboardingCompleted: Value(onboardingCompleted),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updatedByDeviceId: updatedByDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedByDeviceId),
      lastCommandId: lastCommandId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommandId),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalProfile(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      email: serializer.fromJson<String?>(json['email']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      genderIdentity: serializer.fromJson<String?>(json['genderIdentity']),
      dateOfBirth: serializer.fromJson<DateTime?>(json['dateOfBirth']),
      heightCm: serializer.fromJson<double?>(json['heightCm']),
      onboardingCompleted: serializer.fromJson<bool>(
        json['onboardingCompleted'],
      ),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDeviceId: serializer.fromJson<String?>(
        json['updatedByDeviceId'],
      ),
      lastCommandId: serializer.fromJson<String?>(json['lastCommandId']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String>(displayName),
      'email': serializer.toJson<String?>(email),
      'imagePath': serializer.toJson<String?>(imagePath),
      'genderIdentity': serializer.toJson<String?>(genderIdentity),
      'dateOfBirth': serializer.toJson<DateTime?>(dateOfBirth),
      'heightCm': serializer.toJson<double?>(heightCm),
      'onboardingCompleted': serializer.toJson<bool>(onboardingCompleted),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDeviceId': serializer.toJson<String?>(updatedByDeviceId),
      'lastCommandId': serializer.toJson<String?>(lastCommandId),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalProfile copyWith({
    String? id,
    String? userId,
    String? displayName,
    Value<String?> email = const Value.absent(),
    Value<String?> imagePath = const Value.absent(),
    Value<String?> genderIdentity = const Value.absent(),
    Value<DateTime?> dateOfBirth = const Value.absent(),
    Value<double?> heightCm = const Value.absent(),
    bool? onboardingCompleted,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> updatedByDeviceId = const Value.absent(),
    Value<String?> lastCommandId = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalProfile(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    email: email.present ? email.value : this.email,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    genderIdentity: genderIdentity.present
        ? genderIdentity.value
        : this.genderIdentity,
    dateOfBirth: dateOfBirth.present ? dateOfBirth.value : this.dateOfBirth,
    heightCm: heightCm.present ? heightCm.value : this.heightCm,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDeviceId: updatedByDeviceId.present
        ? updatedByDeviceId.value
        : this.updatedByDeviceId,
    lastCommandId: lastCommandId.present
        ? lastCommandId.value
        : this.lastCommandId,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalProfile copyWithCompanion(LocalProfilesCompanion data) {
    return LocalProfile(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      email: data.email.present ? data.email.value : this.email,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      genderIdentity: data.genderIdentity.present
          ? data.genderIdentity.value
          : this.genderIdentity,
      dateOfBirth: data.dateOfBirth.present
          ? data.dateOfBirth.value
          : this.dateOfBirth,
      heightCm: data.heightCm.present ? data.heightCm.value : this.heightCm,
      onboardingCompleted: data.onboardingCompleted.present
          ? data.onboardingCompleted.value
          : this.onboardingCompleted,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDeviceId: data.updatedByDeviceId.present
          ? data.updatedByDeviceId.value
          : this.updatedByDeviceId,
      lastCommandId: data.lastCommandId.present
          ? data.lastCommandId.value
          : this.lastCommandId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalProfile(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('email: $email, ')
          ..write('imagePath: $imagePath, ')
          ..write('genderIdentity: $genderIdentity, ')
          ..write('dateOfBirth: $dateOfBirth, ')
          ..write('heightCm: $heightCm, ')
          ..write('onboardingCompleted: $onboardingCompleted, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    displayName,
    email,
    imagePath,
    genderIdentity,
    dateOfBirth,
    heightCm,
    onboardingCompleted,
    revision,
    createdAt,
    updatedAt,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalProfile &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.email == this.email &&
          other.imagePath == this.imagePath &&
          other.genderIdentity == this.genderIdentity &&
          other.dateOfBirth == this.dateOfBirth &&
          other.heightCm == this.heightCm &&
          other.onboardingCompleted == this.onboardingCompleted &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDeviceId == this.updatedByDeviceId &&
          other.lastCommandId == this.lastCommandId &&
          other.deletedAt == this.deletedAt);
}

class LocalProfilesCompanion extends UpdateCompanion<LocalProfile> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> displayName;
  final Value<String?> email;
  final Value<String?> imagePath;
  final Value<String?> genderIdentity;
  final Value<DateTime?> dateOfBirth;
  final Value<double?> heightCm;
  final Value<bool> onboardingCompleted;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> updatedByDeviceId;
  final Value<String?> lastCommandId;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalProfilesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.email = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.genderIdentity = const Value.absent(),
    this.dateOfBirth = const Value.absent(),
    this.heightCm = const Value.absent(),
    this.onboardingCompleted = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalProfilesCompanion.insert({
    required String id,
    required String userId,
    this.displayName = const Value.absent(),
    this.email = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.genderIdentity = const Value.absent(),
    this.dateOfBirth = const Value.absent(),
    this.heightCm = const Value.absent(),
    this.onboardingCompleted = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalProfile> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<String>? email,
    Expression<String>? imagePath,
    Expression<String>? genderIdentity,
    Expression<DateTime>? dateOfBirth,
    Expression<double>? heightCm,
    Expression<bool>? onboardingCompleted,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDeviceId,
    Expression<String>? lastCommandId,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (email != null) 'email': email,
      if (imagePath != null) 'image_path': imagePath,
      if (genderIdentity != null) 'gender_identity': genderIdentity,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (heightCm != null) 'height_cm': heightCm,
      if (onboardingCompleted != null)
        'onboarding_completed': onboardingCompleted,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDeviceId != null) 'updated_by_device_id': updatedByDeviceId,
      if (lastCommandId != null) 'last_command_id': lastCommandId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? displayName,
    Value<String?>? email,
    Value<String?>? imagePath,
    Value<String?>? genderIdentity,
    Value<DateTime?>? dateOfBirth,
    Value<double?>? heightCm,
    Value<bool>? onboardingCompleted,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? updatedByDeviceId,
    Value<String?>? lastCommandId,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalProfilesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      imagePath: imagePath ?? this.imagePath,
      genderIdentity: genderIdentity ?? this.genderIdentity,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      heightCm: heightCm ?? this.heightCm,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDeviceId: updatedByDeviceId ?? this.updatedByDeviceId,
      lastCommandId: lastCommandId ?? this.lastCommandId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (genderIdentity.present) {
      map['gender_identity'] = Variable<String>(genderIdentity.value);
    }
    if (dateOfBirth.present) {
      map['date_of_birth'] = Variable<DateTime>(dateOfBirth.value);
    }
    if (heightCm.present) {
      map['height_cm'] = Variable<double>(heightCm.value);
    }
    if (onboardingCompleted.present) {
      map['onboarding_completed'] = Variable<bool>(onboardingCompleted.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDeviceId.present) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId.value);
    }
    if (lastCommandId.present) {
      map['last_command_id'] = Variable<String>(lastCommandId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalProfilesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('email: $email, ')
          ..write('imagePath: $imagePath, ')
          ..write('genderIdentity: $genderIdentity, ')
          ..write('dateOfBirth: $dateOfBirth, ')
          ..write('heightCm: $heightCm, ')
          ..write('onboardingCompleted: $onboardingCompleted, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalAppSettingsTable extends LocalAppSettings
    with TableInfo<$LocalAppSettingsTable, LocalAppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _localeCodeMeta = const VerificationMeta(
    'localeCode',
  );
  @override
  late final GeneratedColumn<String> localeCode = GeneratedColumn<String>(
    'locale_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('en'),
  );
  static const VerificationMeta _themeKeyMeta = const VerificationMeta(
    'themeKey',
  );
  @override
  late final GeneratedColumn<String> themeKey = GeneratedColumn<String>(
    'theme_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('system'),
  );
  static const VerificationMeta _accentColorMeta = const VerificationMeta(
    'accentColor',
  );
  @override
  late final GeneratedColumn<int> accentColor = GeneratedColumn<int>(
    'accent_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFF0B78D1),
  );
  static const VerificationMeta _timeZoneMeta = const VerificationMeta(
    'timeZone',
  );
  @override
  late final GeneratedColumn<String> timeZone = GeneratedColumn<String>(
    'time_zone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('UTC'),
  );
  static const VerificationMeta _useDeviceTimeZoneMeta = const VerificationMeta(
    'useDeviceTimeZone',
  );
  @override
  late final GeneratedColumn<bool> useDeviceTimeZone = GeneratedColumn<bool>(
    'use_device_time_zone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("use_device_time_zone" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _clockFormatMeta = const VerificationMeta(
    'clockFormat',
  );
  @override
  late final GeneratedColumn<String> clockFormat = GeneratedColumn<String>(
    'clock_format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('24h'),
  );
  static const VerificationMeta _notificationSoundKeyMeta =
      const VerificationMeta('notificationSoundKey');
  @override
  late final GeneratedColumn<String> notificationSoundKey =
      GeneratedColumn<String>(
        'notification_sound_key',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('system'),
      );
  static const VerificationMeta _healthConnectEnabledMeta =
      const VerificationMeta('healthConnectEnabled');
  @override
  late final GeneratedColumn<bool> healthConnectEnabled = GeneratedColumn<bool>(
    'health_connect_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("health_connect_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _cycleTrackingEnabledMeta =
      const VerificationMeta('cycleTrackingEnabled');
  @override
  late final GeneratedColumn<bool> cycleTrackingEnabled = GeneratedColumn<bool>(
    'cycle_tracking_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("cycle_tracking_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _cycleStorageModeMeta = const VerificationMeta(
    'cycleStorageMode',
  );
  @override
  late final GeneratedColumn<String> cycleStorageMode = GeneratedColumn<String>(
    'cycle_storage_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local_only'),
  );
  static const VerificationMeta _calendarShowCompletedMeta =
      const VerificationMeta('calendarShowCompleted');
  @override
  late final GeneratedColumn<bool> calendarShowCompleted =
      GeneratedColumn<bool>(
        'calendar_show_completed',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("calendar_show_completed" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _applicationTrackingEnabledMeta =
      const VerificationMeta('applicationTrackingEnabled');
  @override
  late final GeneratedColumn<bool> applicationTrackingEnabled =
      GeneratedColumn<bool>(
        'application_tracking_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("application_tracking_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _windowTitleTrackingEnabledMeta =
      const VerificationMeta('windowTitleTrackingEnabled');
  @override
  late final GeneratedColumn<bool> windowTitleTrackingEnabled =
      GeneratedColumn<bool>(
        'window_title_tracking_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("window_title_tracking_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _idleDetectionEnabledMeta =
      const VerificationMeta('idleDetectionEnabled');
  @override
  late final GeneratedColumn<bool> idleDetectionEnabled = GeneratedColumn<bool>(
    'idle_detection_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("idle_detection_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _idleThresholdSecondsMeta =
      const VerificationMeta('idleThresholdSeconds');
  @override
  late final GeneratedColumn<int> idleThresholdSeconds = GeneratedColumn<int>(
    'idle_threshold_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(30),
  );
  static const VerificationMeta _detectBreakActivityMeta =
      const VerificationMeta('detectBreakActivity');
  @override
  late final GeneratedColumn<bool> detectBreakActivity = GeneratedColumn<bool>(
    'detect_break_activity',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("detect_break_activity" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _detectCrossTaskActivityMeta =
      const VerificationMeta('detectCrossTaskActivity');
  @override
  late final GeneratedColumn<bool> detectCrossTaskActivity =
      GeneratedColumn<bool>(
        'detect_cross_task_activity',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("detect_cross_task_activity" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _retainUnclassifiedActivityMeta =
      const VerificationMeta('retainUnclassifiedActivity');
  @override
  late final GeneratedColumn<bool> retainUnclassifiedActivity =
      GeneratedColumn<bool>(
        'retain_unclassified_activity',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("retain_unclassified_activity" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _retainTechnicalIdleMeta =
      const VerificationMeta('retainTechnicalIdle');
  @override
  late final GeneratedColumn<bool> retainTechnicalIdle = GeneratedColumn<bool>(
    'retain_technical_idle',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("retain_technical_idle" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _automaticTrustedRulesMeta =
      const VerificationMeta('automaticTrustedRules');
  @override
  late final GeneratedColumn<bool> automaticTrustedRules =
      GeneratedColumn<bool>(
        'automatic_trusted_rules',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("automatic_trusted_rules" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _activitySyncEnabledMeta =
      const VerificationMeta('activitySyncEnabled');
  @override
  late final GeneratedColumn<bool> activitySyncEnabled = GeneratedColumn<bool>(
    'activity_sync_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activity_sync_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _activityRuleSyncEnabledMeta =
      const VerificationMeta('activityRuleSyncEnabled');
  @override
  late final GeneratedColumn<bool> activityRuleSyncEnabled =
      GeneratedColumn<bool>(
        'activity_rule_sync_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("activity_rule_sync_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _detailedActivitySyncEnabledMeta =
      const VerificationMeta('detailedActivitySyncEnabled');
  @override
  late final GeneratedColumn<bool> detailedActivitySyncEnabled =
      GeneratedColumn<bool>(
        'detailed_activity_sync_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("detailed_activity_sync_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _localActivityRetentionDaysMeta =
      const VerificationMeta('localActivityRetentionDays');
  @override
  late final GeneratedColumn<int> localActivityRetentionDays =
      GeneratedColumn<int>(
        'local_activity_retention_days',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(30),
      );
  static const VerificationMeta _hideConfirmedSystemActivityMeta =
      const VerificationMeta('hideConfirmedSystemActivity');
  @override
  late final GeneratedColumn<bool> hideConfirmedSystemActivity =
      GeneratedColumn<bool>(
        'hide_confirmed_system_activity',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("hide_confirmed_system_activity" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _showPossibleSystemActivityMeta =
      const VerificationMeta('showPossibleSystemActivity');
  @override
  late final GeneratedColumn<bool> showPossibleSystemActivity =
      GeneratedColumn<bool>(
        'show_possible_system_activity',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("show_possible_system_activity" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _automaticConfidenceThresholdMeta =
      const VerificationMeta('automaticConfidenceThreshold');
  @override
  late final GeneratedColumn<double> automaticConfidenceThreshold =
      GeneratedColumn<double>(
        'automatic_confidence_threshold',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.9),
      );
  static const VerificationMeta _minimumSuggestionDurationMsMeta =
      const VerificationMeta('minimumSuggestionDurationMs');
  @override
  late final GeneratedColumn<int> minimumSuggestionDurationMs =
      GeneratedColumn<int>(
        'minimum_suggestion_duration_ms',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(30000),
      );
  static const VerificationMeta _wakeTimeMinutesMeta = const VerificationMeta(
    'wakeTimeMinutes',
  );
  @override
  late final GeneratedColumn<int> wakeTimeMinutes = GeneratedColumn<int>(
    'wake_time_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(420),
  );
  static const VerificationMeta _sleepTimeMinutesMeta = const VerificationMeta(
    'sleepTimeMinutes',
  );
  @override
  late final GeneratedColumn<int> sleepTimeMinutes = GeneratedColumn<int>(
    'sleep_time_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1380),
  );
  static const VerificationMeta _workingDaysJsonMeta = const VerificationMeta(
    'workingDaysJson',
  );
  @override
  late final GeneratedColumn<String> workingDaysJson = GeneratedColumn<String>(
    'working_days_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[1,2,3,4,5]'),
  );
  static const VerificationMeta _workStartMinutesMeta = const VerificationMeta(
    'workStartMinutes',
  );
  @override
  late final GeneratedColumn<int> workStartMinutes = GeneratedColumn<int>(
    'work_start_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(540),
  );
  static const VerificationMeta _workEndMinutesMeta = const VerificationMeta(
    'workEndMinutes',
  );
  @override
  late final GeneratedColumn<int> workEndMinutes = GeneratedColumn<int>(
    'work_end_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1020),
  );
  static const VerificationMeta _workScheduleEnabledMeta =
      const VerificationMeta('workScheduleEnabled');
  @override
  late final GeneratedColumn<bool> workScheduleEnabled = GeneratedColumn<bool>(
    'work_schedule_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("work_schedule_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _workScheduleRotationJsonMeta =
      const VerificationMeta('workScheduleRotationJson');
  @override
  late final GeneratedColumn<String> workScheduleRotationJson =
      GeneratedColumn<String>(
        'work_schedule_rotation_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _workScheduleAnchorDateMeta =
      const VerificationMeta('workScheduleAnchorDate');
  @override
  late final GeneratedColumn<String> workScheduleAnchorDate =
      GeneratedColumn<String>(
        'work_schedule_anchor_date',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('2026-01-05'),
      );
  static const VerificationMeta _workReminderEnabledMeta =
      const VerificationMeta('workReminderEnabled');
  @override
  late final GeneratedColumn<bool> workReminderEnabled = GeneratedColumn<bool>(
    'work_reminder_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("work_reminder_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _workReminderOffsetMinutesMeta =
      const VerificationMeta('workReminderOffsetMinutes');
  @override
  late final GeneratedColumn<int> workReminderOffsetMinutes =
      GeneratedColumn<int>(
        'work_reminder_offset_minutes',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(15),
      );
  static const VerificationMeta _workPomodoroEnabledMeta =
      const VerificationMeta('workPomodoroEnabled');
  @override
  late final GeneratedColumn<bool> workPomodoroEnabled = GeneratedColumn<bool>(
    'work_pomodoro_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("work_pomodoro_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _workActivityCreditEnabledMeta =
      const VerificationMeta('workActivityCreditEnabled');
  @override
  late final GeneratedColumn<bool> workActivityCreditEnabled =
      GeneratedColumn<bool>(
        'work_activity_credit_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("work_activity_credit_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _quietStartMinutesMeta = const VerificationMeta(
    'quietStartMinutes',
  );
  @override
  late final GeneratedColumn<int> quietStartMinutes = GeneratedColumn<int>(
    'quiet_start_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1320),
  );
  static const VerificationMeta _quietEndMinutesMeta = const VerificationMeta(
    'quietEndMinutes',
  );
  @override
  late final GeneratedColumn<int> quietEndMinutes = GeneratedColumn<int>(
    'quiet_end_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(420),
  );
  static const VerificationMeta _sleepReminderEnabledMeta =
      const VerificationMeta('sleepReminderEnabled');
  @override
  late final GeneratedColumn<bool> sleepReminderEnabled = GeneratedColumn<bool>(
    'sleep_reminder_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sleep_reminder_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sleepReminderOffsetMinutesMeta =
      const VerificationMeta('sleepReminderOffsetMinutes');
  @override
  late final GeneratedColumn<int> sleepReminderOffsetMinutes =
      GeneratedColumn<int>(
        'sleep_reminder_offset_minutes',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(30),
      );
  static const VerificationMeta _phoneUsageAnalysisEnabledMeta =
      const VerificationMeta('phoneUsageAnalysisEnabled');
  @override
  late final GeneratedColumn<bool> phoneUsageAnalysisEnabled =
      GeneratedColumn<bool>(
        'phone_usage_analysis_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("phone_usage_analysis_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _coachingSensitivityMeta =
      const VerificationMeta('coachingSensitivity');
  @override
  late final GeneratedColumn<String> coachingSensitivity =
      GeneratedColumn<String>(
        'coaching_sensitivity',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('standard'),
      );
  static const VerificationMeta _coachingToneMeta = const VerificationMeta(
    'coachingTone',
  );
  @override
  late final GeneratedColumn<String> coachingTone = GeneratedColumn<String>(
    'coaching_tone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('balanced'),
  );
  static const VerificationMeta _healthSummarySyncEnabledMeta =
      const VerificationMeta('healthSummarySyncEnabled');
  @override
  late final GeneratedColumn<bool> healthSummarySyncEnabled =
      GeneratedColumn<bool>(
        'health_summary_sync_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("health_summary_sync_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _healthReportPrivacyMeta =
      const VerificationMeta('healthReportPrivacy');
  @override
  late final GeneratedColumn<String> healthReportPrivacy =
      GeneratedColumn<String>(
        'health_report_privacy',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('ask'),
      );
  static const VerificationMeta _notificationPreferencesJsonMeta =
      const VerificationMeta('notificationPreferencesJson');
  @override
  late final GeneratedColumn<String> notificationPreferencesJson =
      GeneratedColumn<String>(
        'notification_preferences_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(
          '{"task_reminders":true,"scheduled_starts":true,'
          '"overdue_tasks":true,"focus_completed":true,'
          '"short_break_completed":true,"long_break_completed":true,'
          '"roadmaps":true,"activity_review":true,"coaching":true,'
          '"sleep_health":true,"synchronization":true,"security":true,'
          '"vibration":true}',
        ),
      );
  static const VerificationMeta _countryCodeMeta = const VerificationMeta(
    'countryCode',
  );
  @override
  late final GeneratedColumn<String> countryCode = GeneratedColumn<String>(
    'country_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dateFormatMeta = const VerificationMeta(
    'dateFormat',
  );
  @override
  late final GeneratedColumn<String> dateFormat = GeneratedColumn<String>(
    'date_format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('locale'),
  );
  static const VerificationMeta _firstDayOfWeekMeta = const VerificationMeta(
    'firstDayOfWeek',
  );
  @override
  late final GeneratedColumn<int> firstDayOfWeek = GeneratedColumn<int>(
    'first_day_of_week',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastCommandIdMeta = const VerificationMeta(
    'lastCommandId',
  );
  @override
  late final GeneratedColumn<String> lastCommandId = GeneratedColumn<String>(
    'last_command_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    localeCode,
    themeKey,
    accentColor,
    timeZone,
    useDeviceTimeZone,
    clockFormat,
    notificationSoundKey,
    healthConnectEnabled,
    cycleTrackingEnabled,
    cycleStorageMode,
    calendarShowCompleted,
    applicationTrackingEnabled,
    windowTitleTrackingEnabled,
    idleDetectionEnabled,
    idleThresholdSeconds,
    detectBreakActivity,
    detectCrossTaskActivity,
    retainUnclassifiedActivity,
    retainTechnicalIdle,
    automaticTrustedRules,
    activitySyncEnabled,
    activityRuleSyncEnabled,
    detailedActivitySyncEnabled,
    localActivityRetentionDays,
    hideConfirmedSystemActivity,
    showPossibleSystemActivity,
    automaticConfidenceThreshold,
    minimumSuggestionDurationMs,
    wakeTimeMinutes,
    sleepTimeMinutes,
    workingDaysJson,
    workStartMinutes,
    workEndMinutes,
    workScheduleEnabled,
    workScheduleRotationJson,
    workScheduleAnchorDate,
    workReminderEnabled,
    workReminderOffsetMinutes,
    workPomodoroEnabled,
    workActivityCreditEnabled,
    quietStartMinutes,
    quietEndMinutes,
    sleepReminderEnabled,
    sleepReminderOffsetMinutes,
    phoneUsageAnalysisEnabled,
    coachingSensitivity,
    coachingTone,
    healthSummarySyncEnabled,
    healthReportPrivacy,
    notificationPreferencesJson,
    countryCode,
    dateFormat,
    firstDayOfWeek,
    revision,
    createdAt,
    updatedAt,
    lastCommandId,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('locale_code')) {
      context.handle(
        _localeCodeMeta,
        localeCode.isAcceptableOrUnknown(data['locale_code']!, _localeCodeMeta),
      );
    }
    if (data.containsKey('theme_key')) {
      context.handle(
        _themeKeyMeta,
        themeKey.isAcceptableOrUnknown(data['theme_key']!, _themeKeyMeta),
      );
    }
    if (data.containsKey('accent_color')) {
      context.handle(
        _accentColorMeta,
        accentColor.isAcceptableOrUnknown(
          data['accent_color']!,
          _accentColorMeta,
        ),
      );
    }
    if (data.containsKey('time_zone')) {
      context.handle(
        _timeZoneMeta,
        timeZone.isAcceptableOrUnknown(data['time_zone']!, _timeZoneMeta),
      );
    }
    if (data.containsKey('use_device_time_zone')) {
      context.handle(
        _useDeviceTimeZoneMeta,
        useDeviceTimeZone.isAcceptableOrUnknown(
          data['use_device_time_zone']!,
          _useDeviceTimeZoneMeta,
        ),
      );
    }
    if (data.containsKey('clock_format')) {
      context.handle(
        _clockFormatMeta,
        clockFormat.isAcceptableOrUnknown(
          data['clock_format']!,
          _clockFormatMeta,
        ),
      );
    }
    if (data.containsKey('notification_sound_key')) {
      context.handle(
        _notificationSoundKeyMeta,
        notificationSoundKey.isAcceptableOrUnknown(
          data['notification_sound_key']!,
          _notificationSoundKeyMeta,
        ),
      );
    }
    if (data.containsKey('health_connect_enabled')) {
      context.handle(
        _healthConnectEnabledMeta,
        healthConnectEnabled.isAcceptableOrUnknown(
          data['health_connect_enabled']!,
          _healthConnectEnabledMeta,
        ),
      );
    }
    if (data.containsKey('cycle_tracking_enabled')) {
      context.handle(
        _cycleTrackingEnabledMeta,
        cycleTrackingEnabled.isAcceptableOrUnknown(
          data['cycle_tracking_enabled']!,
          _cycleTrackingEnabledMeta,
        ),
      );
    }
    if (data.containsKey('cycle_storage_mode')) {
      context.handle(
        _cycleStorageModeMeta,
        cycleStorageMode.isAcceptableOrUnknown(
          data['cycle_storage_mode']!,
          _cycleStorageModeMeta,
        ),
      );
    }
    if (data.containsKey('calendar_show_completed')) {
      context.handle(
        _calendarShowCompletedMeta,
        calendarShowCompleted.isAcceptableOrUnknown(
          data['calendar_show_completed']!,
          _calendarShowCompletedMeta,
        ),
      );
    }
    if (data.containsKey('application_tracking_enabled')) {
      context.handle(
        _applicationTrackingEnabledMeta,
        applicationTrackingEnabled.isAcceptableOrUnknown(
          data['application_tracking_enabled']!,
          _applicationTrackingEnabledMeta,
        ),
      );
    }
    if (data.containsKey('window_title_tracking_enabled')) {
      context.handle(
        _windowTitleTrackingEnabledMeta,
        windowTitleTrackingEnabled.isAcceptableOrUnknown(
          data['window_title_tracking_enabled']!,
          _windowTitleTrackingEnabledMeta,
        ),
      );
    }
    if (data.containsKey('idle_detection_enabled')) {
      context.handle(
        _idleDetectionEnabledMeta,
        idleDetectionEnabled.isAcceptableOrUnknown(
          data['idle_detection_enabled']!,
          _idleDetectionEnabledMeta,
        ),
      );
    }
    if (data.containsKey('idle_threshold_seconds')) {
      context.handle(
        _idleThresholdSecondsMeta,
        idleThresholdSeconds.isAcceptableOrUnknown(
          data['idle_threshold_seconds']!,
          _idleThresholdSecondsMeta,
        ),
      );
    }
    if (data.containsKey('detect_break_activity')) {
      context.handle(
        _detectBreakActivityMeta,
        detectBreakActivity.isAcceptableOrUnknown(
          data['detect_break_activity']!,
          _detectBreakActivityMeta,
        ),
      );
    }
    if (data.containsKey('detect_cross_task_activity')) {
      context.handle(
        _detectCrossTaskActivityMeta,
        detectCrossTaskActivity.isAcceptableOrUnknown(
          data['detect_cross_task_activity']!,
          _detectCrossTaskActivityMeta,
        ),
      );
    }
    if (data.containsKey('retain_unclassified_activity')) {
      context.handle(
        _retainUnclassifiedActivityMeta,
        retainUnclassifiedActivity.isAcceptableOrUnknown(
          data['retain_unclassified_activity']!,
          _retainUnclassifiedActivityMeta,
        ),
      );
    }
    if (data.containsKey('retain_technical_idle')) {
      context.handle(
        _retainTechnicalIdleMeta,
        retainTechnicalIdle.isAcceptableOrUnknown(
          data['retain_technical_idle']!,
          _retainTechnicalIdleMeta,
        ),
      );
    }
    if (data.containsKey('automatic_trusted_rules')) {
      context.handle(
        _automaticTrustedRulesMeta,
        automaticTrustedRules.isAcceptableOrUnknown(
          data['automatic_trusted_rules']!,
          _automaticTrustedRulesMeta,
        ),
      );
    }
    if (data.containsKey('activity_sync_enabled')) {
      context.handle(
        _activitySyncEnabledMeta,
        activitySyncEnabled.isAcceptableOrUnknown(
          data['activity_sync_enabled']!,
          _activitySyncEnabledMeta,
        ),
      );
    }
    if (data.containsKey('activity_rule_sync_enabled')) {
      context.handle(
        _activityRuleSyncEnabledMeta,
        activityRuleSyncEnabled.isAcceptableOrUnknown(
          data['activity_rule_sync_enabled']!,
          _activityRuleSyncEnabledMeta,
        ),
      );
    }
    if (data.containsKey('detailed_activity_sync_enabled')) {
      context.handle(
        _detailedActivitySyncEnabledMeta,
        detailedActivitySyncEnabled.isAcceptableOrUnknown(
          data['detailed_activity_sync_enabled']!,
          _detailedActivitySyncEnabledMeta,
        ),
      );
    }
    if (data.containsKey('local_activity_retention_days')) {
      context.handle(
        _localActivityRetentionDaysMeta,
        localActivityRetentionDays.isAcceptableOrUnknown(
          data['local_activity_retention_days']!,
          _localActivityRetentionDaysMeta,
        ),
      );
    }
    if (data.containsKey('hide_confirmed_system_activity')) {
      context.handle(
        _hideConfirmedSystemActivityMeta,
        hideConfirmedSystemActivity.isAcceptableOrUnknown(
          data['hide_confirmed_system_activity']!,
          _hideConfirmedSystemActivityMeta,
        ),
      );
    }
    if (data.containsKey('show_possible_system_activity')) {
      context.handle(
        _showPossibleSystemActivityMeta,
        showPossibleSystemActivity.isAcceptableOrUnknown(
          data['show_possible_system_activity']!,
          _showPossibleSystemActivityMeta,
        ),
      );
    }
    if (data.containsKey('automatic_confidence_threshold')) {
      context.handle(
        _automaticConfidenceThresholdMeta,
        automaticConfidenceThreshold.isAcceptableOrUnknown(
          data['automatic_confidence_threshold']!,
          _automaticConfidenceThresholdMeta,
        ),
      );
    }
    if (data.containsKey('minimum_suggestion_duration_ms')) {
      context.handle(
        _minimumSuggestionDurationMsMeta,
        minimumSuggestionDurationMs.isAcceptableOrUnknown(
          data['minimum_suggestion_duration_ms']!,
          _minimumSuggestionDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('wake_time_minutes')) {
      context.handle(
        _wakeTimeMinutesMeta,
        wakeTimeMinutes.isAcceptableOrUnknown(
          data['wake_time_minutes']!,
          _wakeTimeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('sleep_time_minutes')) {
      context.handle(
        _sleepTimeMinutesMeta,
        sleepTimeMinutes.isAcceptableOrUnknown(
          data['sleep_time_minutes']!,
          _sleepTimeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('working_days_json')) {
      context.handle(
        _workingDaysJsonMeta,
        workingDaysJson.isAcceptableOrUnknown(
          data['working_days_json']!,
          _workingDaysJsonMeta,
        ),
      );
    }
    if (data.containsKey('work_start_minutes')) {
      context.handle(
        _workStartMinutesMeta,
        workStartMinutes.isAcceptableOrUnknown(
          data['work_start_minutes']!,
          _workStartMinutesMeta,
        ),
      );
    }
    if (data.containsKey('work_end_minutes')) {
      context.handle(
        _workEndMinutesMeta,
        workEndMinutes.isAcceptableOrUnknown(
          data['work_end_minutes']!,
          _workEndMinutesMeta,
        ),
      );
    }
    if (data.containsKey('work_schedule_enabled')) {
      context.handle(
        _workScheduleEnabledMeta,
        workScheduleEnabled.isAcceptableOrUnknown(
          data['work_schedule_enabled']!,
          _workScheduleEnabledMeta,
        ),
      );
    }
    if (data.containsKey('work_schedule_rotation_json')) {
      context.handle(
        _workScheduleRotationJsonMeta,
        workScheduleRotationJson.isAcceptableOrUnknown(
          data['work_schedule_rotation_json']!,
          _workScheduleRotationJsonMeta,
        ),
      );
    }
    if (data.containsKey('work_schedule_anchor_date')) {
      context.handle(
        _workScheduleAnchorDateMeta,
        workScheduleAnchorDate.isAcceptableOrUnknown(
          data['work_schedule_anchor_date']!,
          _workScheduleAnchorDateMeta,
        ),
      );
    }
    if (data.containsKey('work_reminder_enabled')) {
      context.handle(
        _workReminderEnabledMeta,
        workReminderEnabled.isAcceptableOrUnknown(
          data['work_reminder_enabled']!,
          _workReminderEnabledMeta,
        ),
      );
    }
    if (data.containsKey('work_reminder_offset_minutes')) {
      context.handle(
        _workReminderOffsetMinutesMeta,
        workReminderOffsetMinutes.isAcceptableOrUnknown(
          data['work_reminder_offset_minutes']!,
          _workReminderOffsetMinutesMeta,
        ),
      );
    }
    if (data.containsKey('work_pomodoro_enabled')) {
      context.handle(
        _workPomodoroEnabledMeta,
        workPomodoroEnabled.isAcceptableOrUnknown(
          data['work_pomodoro_enabled']!,
          _workPomodoroEnabledMeta,
        ),
      );
    }
    if (data.containsKey('work_activity_credit_enabled')) {
      context.handle(
        _workActivityCreditEnabledMeta,
        workActivityCreditEnabled.isAcceptableOrUnknown(
          data['work_activity_credit_enabled']!,
          _workActivityCreditEnabledMeta,
        ),
      );
    }
    if (data.containsKey('quiet_start_minutes')) {
      context.handle(
        _quietStartMinutesMeta,
        quietStartMinutes.isAcceptableOrUnknown(
          data['quiet_start_minutes']!,
          _quietStartMinutesMeta,
        ),
      );
    }
    if (data.containsKey('quiet_end_minutes')) {
      context.handle(
        _quietEndMinutesMeta,
        quietEndMinutes.isAcceptableOrUnknown(
          data['quiet_end_minutes']!,
          _quietEndMinutesMeta,
        ),
      );
    }
    if (data.containsKey('sleep_reminder_enabled')) {
      context.handle(
        _sleepReminderEnabledMeta,
        sleepReminderEnabled.isAcceptableOrUnknown(
          data['sleep_reminder_enabled']!,
          _sleepReminderEnabledMeta,
        ),
      );
    }
    if (data.containsKey('sleep_reminder_offset_minutes')) {
      context.handle(
        _sleepReminderOffsetMinutesMeta,
        sleepReminderOffsetMinutes.isAcceptableOrUnknown(
          data['sleep_reminder_offset_minutes']!,
          _sleepReminderOffsetMinutesMeta,
        ),
      );
    }
    if (data.containsKey('phone_usage_analysis_enabled')) {
      context.handle(
        _phoneUsageAnalysisEnabledMeta,
        phoneUsageAnalysisEnabled.isAcceptableOrUnknown(
          data['phone_usage_analysis_enabled']!,
          _phoneUsageAnalysisEnabledMeta,
        ),
      );
    }
    if (data.containsKey('coaching_sensitivity')) {
      context.handle(
        _coachingSensitivityMeta,
        coachingSensitivity.isAcceptableOrUnknown(
          data['coaching_sensitivity']!,
          _coachingSensitivityMeta,
        ),
      );
    }
    if (data.containsKey('coaching_tone')) {
      context.handle(
        _coachingToneMeta,
        coachingTone.isAcceptableOrUnknown(
          data['coaching_tone']!,
          _coachingToneMeta,
        ),
      );
    }
    if (data.containsKey('health_summary_sync_enabled')) {
      context.handle(
        _healthSummarySyncEnabledMeta,
        healthSummarySyncEnabled.isAcceptableOrUnknown(
          data['health_summary_sync_enabled']!,
          _healthSummarySyncEnabledMeta,
        ),
      );
    }
    if (data.containsKey('health_report_privacy')) {
      context.handle(
        _healthReportPrivacyMeta,
        healthReportPrivacy.isAcceptableOrUnknown(
          data['health_report_privacy']!,
          _healthReportPrivacyMeta,
        ),
      );
    }
    if (data.containsKey('notification_preferences_json')) {
      context.handle(
        _notificationPreferencesJsonMeta,
        notificationPreferencesJson.isAcceptableOrUnknown(
          data['notification_preferences_json']!,
          _notificationPreferencesJsonMeta,
        ),
      );
    }
    if (data.containsKey('country_code')) {
      context.handle(
        _countryCodeMeta,
        countryCode.isAcceptableOrUnknown(
          data['country_code']!,
          _countryCodeMeta,
        ),
      );
    }
    if (data.containsKey('date_format')) {
      context.handle(
        _dateFormatMeta,
        dateFormat.isAcceptableOrUnknown(data['date_format']!, _dateFormatMeta),
      );
    }
    if (data.containsKey('first_day_of_week')) {
      context.handle(
        _firstDayOfWeekMeta,
        firstDayOfWeek.isAcceptableOrUnknown(
          data['first_day_of_week']!,
          _firstDayOfWeekMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('last_command_id')) {
      context.handle(
        _lastCommandIdMeta,
        lastCommandId.isAcceptableOrUnknown(
          data['last_command_id']!,
          _lastCommandIdMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalAppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAppSetting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      localeCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locale_code'],
      )!,
      themeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_key'],
      )!,
      accentColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accent_color'],
      )!,
      timeZone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_zone'],
      )!,
      useDeviceTimeZone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}use_device_time_zone'],
      )!,
      clockFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clock_format'],
      )!,
      notificationSoundKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notification_sound_key'],
      )!,
      healthConnectEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}health_connect_enabled'],
      )!,
      cycleTrackingEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}cycle_tracking_enabled'],
      )!,
      cycleStorageMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cycle_storage_mode'],
      )!,
      calendarShowCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}calendar_show_completed'],
      )!,
      applicationTrackingEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}application_tracking_enabled'],
      )!,
      windowTitleTrackingEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}window_title_tracking_enabled'],
      )!,
      idleDetectionEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}idle_detection_enabled'],
      )!,
      idleThresholdSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}idle_threshold_seconds'],
      )!,
      detectBreakActivity: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}detect_break_activity'],
      )!,
      detectCrossTaskActivity: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}detect_cross_task_activity'],
      )!,
      retainUnclassifiedActivity: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}retain_unclassified_activity'],
      )!,
      retainTechnicalIdle: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}retain_technical_idle'],
      )!,
      automaticTrustedRules: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}automatic_trusted_rules'],
      )!,
      activitySyncEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}activity_sync_enabled'],
      )!,
      activityRuleSyncEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}activity_rule_sync_enabled'],
      )!,
      detailedActivitySyncEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}detailed_activity_sync_enabled'],
      )!,
      localActivityRetentionDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_activity_retention_days'],
      )!,
      hideConfirmedSystemActivity: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hide_confirmed_system_activity'],
      )!,
      showPossibleSystemActivity: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_possible_system_activity'],
      )!,
      automaticConfidenceThreshold: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}automatic_confidence_threshold'],
      )!,
      minimumSuggestionDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minimum_suggestion_duration_ms'],
      )!,
      wakeTimeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wake_time_minutes'],
      )!,
      sleepTimeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sleep_time_minutes'],
      )!,
      workingDaysJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}working_days_json'],
      )!,
      workStartMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}work_start_minutes'],
      )!,
      workEndMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}work_end_minutes'],
      )!,
      workScheduleEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}work_schedule_enabled'],
      )!,
      workScheduleRotationJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_schedule_rotation_json'],
      )!,
      workScheduleAnchorDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_schedule_anchor_date'],
      )!,
      workReminderEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}work_reminder_enabled'],
      )!,
      workReminderOffsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}work_reminder_offset_minutes'],
      )!,
      workPomodoroEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}work_pomodoro_enabled'],
      )!,
      workActivityCreditEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}work_activity_credit_enabled'],
      )!,
      quietStartMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quiet_start_minutes'],
      )!,
      quietEndMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quiet_end_minutes'],
      )!,
      sleepReminderEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sleep_reminder_enabled'],
      )!,
      sleepReminderOffsetMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sleep_reminder_offset_minutes'],
      )!,
      phoneUsageAnalysisEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}phone_usage_analysis_enabled'],
      )!,
      coachingSensitivity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coaching_sensitivity'],
      )!,
      coachingTone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coaching_tone'],
      )!,
      healthSummarySyncEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}health_summary_sync_enabled'],
      )!,
      healthReportPrivacy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health_report_privacy'],
      )!,
      notificationPreferencesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notification_preferences_json'],
      )!,
      countryCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country_code'],
      )!,
      dateFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date_format'],
      )!,
      firstDayOfWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_day_of_week'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_command_id'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalAppSettingsTable createAlias(String alias) {
    return $LocalAppSettingsTable(attachedDatabase, alias);
  }
}

class LocalAppSetting extends DataClass implements Insertable<LocalAppSetting> {
  final String id;
  final String userId;
  final String localeCode;
  final String themeKey;
  final int accentColor;
  final String timeZone;
  final bool useDeviceTimeZone;
  final String clockFormat;
  final String notificationSoundKey;
  final bool healthConnectEnabled;
  final bool cycleTrackingEnabled;
  final String cycleStorageMode;
  final bool calendarShowCompleted;
  final bool applicationTrackingEnabled;
  final bool windowTitleTrackingEnabled;
  final bool idleDetectionEnabled;
  final int idleThresholdSeconds;
  final bool detectBreakActivity;
  final bool detectCrossTaskActivity;
  final bool retainUnclassifiedActivity;
  final bool retainTechnicalIdle;
  final bool automaticTrustedRules;
  final bool activitySyncEnabled;
  final bool activityRuleSyncEnabled;
  final bool detailedActivitySyncEnabled;
  final int localActivityRetentionDays;
  final bool hideConfirmedSystemActivity;
  final bool showPossibleSystemActivity;
  final double automaticConfidenceThreshold;
  final int minimumSuggestionDurationMs;
  final int wakeTimeMinutes;
  final int sleepTimeMinutes;
  final String workingDaysJson;
  final int workStartMinutes;
  final int workEndMinutes;

  /// Native work scheduling stays separate from tasks.  The values mirror the
  /// synchronized `user_settings.data` contract, so a rotating shift never
  /// needs a fake recurring task merely to trigger a reminder.
  final bool workScheduleEnabled;
  final String workScheduleRotationJson;
  final String workScheduleAnchorDate;
  final bool workReminderEnabled;
  final int workReminderOffsetMinutes;
  final bool workPomodoroEnabled;
  final bool workActivityCreditEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;
  final bool sleepReminderEnabled;
  final int sleepReminderOffsetMinutes;
  final bool phoneUsageAnalysisEnabled;
  final String coachingSensitivity;
  final String coachingTone;
  final bool healthSummarySyncEnabled;
  final String healthReportPrivacy;
  final String notificationPreferencesJson;
  final String countryCode;
  final String dateFormat;
  final int firstDayOfWeek;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastCommandId;
  final DateTime? deletedAt;
  const LocalAppSetting({
    required this.id,
    required this.userId,
    required this.localeCode,
    required this.themeKey,
    required this.accentColor,
    required this.timeZone,
    required this.useDeviceTimeZone,
    required this.clockFormat,
    required this.notificationSoundKey,
    required this.healthConnectEnabled,
    required this.cycleTrackingEnabled,
    required this.cycleStorageMode,
    required this.calendarShowCompleted,
    required this.applicationTrackingEnabled,
    required this.windowTitleTrackingEnabled,
    required this.idleDetectionEnabled,
    required this.idleThresholdSeconds,
    required this.detectBreakActivity,
    required this.detectCrossTaskActivity,
    required this.retainUnclassifiedActivity,
    required this.retainTechnicalIdle,
    required this.automaticTrustedRules,
    required this.activitySyncEnabled,
    required this.activityRuleSyncEnabled,
    required this.detailedActivitySyncEnabled,
    required this.localActivityRetentionDays,
    required this.hideConfirmedSystemActivity,
    required this.showPossibleSystemActivity,
    required this.automaticConfidenceThreshold,
    required this.minimumSuggestionDurationMs,
    required this.wakeTimeMinutes,
    required this.sleepTimeMinutes,
    required this.workingDaysJson,
    required this.workStartMinutes,
    required this.workEndMinutes,
    required this.workScheduleEnabled,
    required this.workScheduleRotationJson,
    required this.workScheduleAnchorDate,
    required this.workReminderEnabled,
    required this.workReminderOffsetMinutes,
    required this.workPomodoroEnabled,
    required this.workActivityCreditEnabled,
    required this.quietStartMinutes,
    required this.quietEndMinutes,
    required this.sleepReminderEnabled,
    required this.sleepReminderOffsetMinutes,
    required this.phoneUsageAnalysisEnabled,
    required this.coachingSensitivity,
    required this.coachingTone,
    required this.healthSummarySyncEnabled,
    required this.healthReportPrivacy,
    required this.notificationPreferencesJson,
    required this.countryCode,
    required this.dateFormat,
    required this.firstDayOfWeek,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.lastCommandId,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['locale_code'] = Variable<String>(localeCode);
    map['theme_key'] = Variable<String>(themeKey);
    map['accent_color'] = Variable<int>(accentColor);
    map['time_zone'] = Variable<String>(timeZone);
    map['use_device_time_zone'] = Variable<bool>(useDeviceTimeZone);
    map['clock_format'] = Variable<String>(clockFormat);
    map['notification_sound_key'] = Variable<String>(notificationSoundKey);
    map['health_connect_enabled'] = Variable<bool>(healthConnectEnabled);
    map['cycle_tracking_enabled'] = Variable<bool>(cycleTrackingEnabled);
    map['cycle_storage_mode'] = Variable<String>(cycleStorageMode);
    map['calendar_show_completed'] = Variable<bool>(calendarShowCompleted);
    map['application_tracking_enabled'] = Variable<bool>(
      applicationTrackingEnabled,
    );
    map['window_title_tracking_enabled'] = Variable<bool>(
      windowTitleTrackingEnabled,
    );
    map['idle_detection_enabled'] = Variable<bool>(idleDetectionEnabled);
    map['idle_threshold_seconds'] = Variable<int>(idleThresholdSeconds);
    map['detect_break_activity'] = Variable<bool>(detectBreakActivity);
    map['detect_cross_task_activity'] = Variable<bool>(detectCrossTaskActivity);
    map['retain_unclassified_activity'] = Variable<bool>(
      retainUnclassifiedActivity,
    );
    map['retain_technical_idle'] = Variable<bool>(retainTechnicalIdle);
    map['automatic_trusted_rules'] = Variable<bool>(automaticTrustedRules);
    map['activity_sync_enabled'] = Variable<bool>(activitySyncEnabled);
    map['activity_rule_sync_enabled'] = Variable<bool>(activityRuleSyncEnabled);
    map['detailed_activity_sync_enabled'] = Variable<bool>(
      detailedActivitySyncEnabled,
    );
    map['local_activity_retention_days'] = Variable<int>(
      localActivityRetentionDays,
    );
    map['hide_confirmed_system_activity'] = Variable<bool>(
      hideConfirmedSystemActivity,
    );
    map['show_possible_system_activity'] = Variable<bool>(
      showPossibleSystemActivity,
    );
    map['automatic_confidence_threshold'] = Variable<double>(
      automaticConfidenceThreshold,
    );
    map['minimum_suggestion_duration_ms'] = Variable<int>(
      minimumSuggestionDurationMs,
    );
    map['wake_time_minutes'] = Variable<int>(wakeTimeMinutes);
    map['sleep_time_minutes'] = Variable<int>(sleepTimeMinutes);
    map['working_days_json'] = Variable<String>(workingDaysJson);
    map['work_start_minutes'] = Variable<int>(workStartMinutes);
    map['work_end_minutes'] = Variable<int>(workEndMinutes);
    map['work_schedule_enabled'] = Variable<bool>(workScheduleEnabled);
    map['work_schedule_rotation_json'] = Variable<String>(
      workScheduleRotationJson,
    );
    map['work_schedule_anchor_date'] = Variable<String>(workScheduleAnchorDate);
    map['work_reminder_enabled'] = Variable<bool>(workReminderEnabled);
    map['work_reminder_offset_minutes'] = Variable<int>(
      workReminderOffsetMinutes,
    );
    map['work_pomodoro_enabled'] = Variable<bool>(workPomodoroEnabled);
    map['work_activity_credit_enabled'] = Variable<bool>(
      workActivityCreditEnabled,
    );
    map['quiet_start_minutes'] = Variable<int>(quietStartMinutes);
    map['quiet_end_minutes'] = Variable<int>(quietEndMinutes);
    map['sleep_reminder_enabled'] = Variable<bool>(sleepReminderEnabled);
    map['sleep_reminder_offset_minutes'] = Variable<int>(
      sleepReminderOffsetMinutes,
    );
    map['phone_usage_analysis_enabled'] = Variable<bool>(
      phoneUsageAnalysisEnabled,
    );
    map['coaching_sensitivity'] = Variable<String>(coachingSensitivity);
    map['coaching_tone'] = Variable<String>(coachingTone);
    map['health_summary_sync_enabled'] = Variable<bool>(
      healthSummarySyncEnabled,
    );
    map['health_report_privacy'] = Variable<String>(healthReportPrivacy);
    map['notification_preferences_json'] = Variable<String>(
      notificationPreferencesJson,
    );
    map['country_code'] = Variable<String>(countryCode);
    map['date_format'] = Variable<String>(dateFormat);
    map['first_day_of_week'] = Variable<int>(firstDayOfWeek);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || lastCommandId != null) {
      map['last_command_id'] = Variable<String>(lastCommandId);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalAppSettingsCompanion toCompanion(bool nullToAbsent) {
    return LocalAppSettingsCompanion(
      id: Value(id),
      userId: Value(userId),
      localeCode: Value(localeCode),
      themeKey: Value(themeKey),
      accentColor: Value(accentColor),
      timeZone: Value(timeZone),
      useDeviceTimeZone: Value(useDeviceTimeZone),
      clockFormat: Value(clockFormat),
      notificationSoundKey: Value(notificationSoundKey),
      healthConnectEnabled: Value(healthConnectEnabled),
      cycleTrackingEnabled: Value(cycleTrackingEnabled),
      cycleStorageMode: Value(cycleStorageMode),
      calendarShowCompleted: Value(calendarShowCompleted),
      applicationTrackingEnabled: Value(applicationTrackingEnabled),
      windowTitleTrackingEnabled: Value(windowTitleTrackingEnabled),
      idleDetectionEnabled: Value(idleDetectionEnabled),
      idleThresholdSeconds: Value(idleThresholdSeconds),
      detectBreakActivity: Value(detectBreakActivity),
      detectCrossTaskActivity: Value(detectCrossTaskActivity),
      retainUnclassifiedActivity: Value(retainUnclassifiedActivity),
      retainTechnicalIdle: Value(retainTechnicalIdle),
      automaticTrustedRules: Value(automaticTrustedRules),
      activitySyncEnabled: Value(activitySyncEnabled),
      activityRuleSyncEnabled: Value(activityRuleSyncEnabled),
      detailedActivitySyncEnabled: Value(detailedActivitySyncEnabled),
      localActivityRetentionDays: Value(localActivityRetentionDays),
      hideConfirmedSystemActivity: Value(hideConfirmedSystemActivity),
      showPossibleSystemActivity: Value(showPossibleSystemActivity),
      automaticConfidenceThreshold: Value(automaticConfidenceThreshold),
      minimumSuggestionDurationMs: Value(minimumSuggestionDurationMs),
      wakeTimeMinutes: Value(wakeTimeMinutes),
      sleepTimeMinutes: Value(sleepTimeMinutes),
      workingDaysJson: Value(workingDaysJson),
      workStartMinutes: Value(workStartMinutes),
      workEndMinutes: Value(workEndMinutes),
      workScheduleEnabled: Value(workScheduleEnabled),
      workScheduleRotationJson: Value(workScheduleRotationJson),
      workScheduleAnchorDate: Value(workScheduleAnchorDate),
      workReminderEnabled: Value(workReminderEnabled),
      workReminderOffsetMinutes: Value(workReminderOffsetMinutes),
      workPomodoroEnabled: Value(workPomodoroEnabled),
      workActivityCreditEnabled: Value(workActivityCreditEnabled),
      quietStartMinutes: Value(quietStartMinutes),
      quietEndMinutes: Value(quietEndMinutes),
      sleepReminderEnabled: Value(sleepReminderEnabled),
      sleepReminderOffsetMinutes: Value(sleepReminderOffsetMinutes),
      phoneUsageAnalysisEnabled: Value(phoneUsageAnalysisEnabled),
      coachingSensitivity: Value(coachingSensitivity),
      coachingTone: Value(coachingTone),
      healthSummarySyncEnabled: Value(healthSummarySyncEnabled),
      healthReportPrivacy: Value(healthReportPrivacy),
      notificationPreferencesJson: Value(notificationPreferencesJson),
      countryCode: Value(countryCode),
      dateFormat: Value(dateFormat),
      firstDayOfWeek: Value(firstDayOfWeek),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastCommandId: lastCommandId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommandId),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalAppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAppSetting(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      localeCode: serializer.fromJson<String>(json['localeCode']),
      themeKey: serializer.fromJson<String>(json['themeKey']),
      accentColor: serializer.fromJson<int>(json['accentColor']),
      timeZone: serializer.fromJson<String>(json['timeZone']),
      useDeviceTimeZone: serializer.fromJson<bool>(json['useDeviceTimeZone']),
      clockFormat: serializer.fromJson<String>(json['clockFormat']),
      notificationSoundKey: serializer.fromJson<String>(
        json['notificationSoundKey'],
      ),
      healthConnectEnabled: serializer.fromJson<bool>(
        json['healthConnectEnabled'],
      ),
      cycleTrackingEnabled: serializer.fromJson<bool>(
        json['cycleTrackingEnabled'],
      ),
      cycleStorageMode: serializer.fromJson<String>(json['cycleStorageMode']),
      calendarShowCompleted: serializer.fromJson<bool>(
        json['calendarShowCompleted'],
      ),
      applicationTrackingEnabled: serializer.fromJson<bool>(
        json['applicationTrackingEnabled'],
      ),
      windowTitleTrackingEnabled: serializer.fromJson<bool>(
        json['windowTitleTrackingEnabled'],
      ),
      idleDetectionEnabled: serializer.fromJson<bool>(
        json['idleDetectionEnabled'],
      ),
      idleThresholdSeconds: serializer.fromJson<int>(
        json['idleThresholdSeconds'],
      ),
      detectBreakActivity: serializer.fromJson<bool>(
        json['detectBreakActivity'],
      ),
      detectCrossTaskActivity: serializer.fromJson<bool>(
        json['detectCrossTaskActivity'],
      ),
      retainUnclassifiedActivity: serializer.fromJson<bool>(
        json['retainUnclassifiedActivity'],
      ),
      retainTechnicalIdle: serializer.fromJson<bool>(
        json['retainTechnicalIdle'],
      ),
      automaticTrustedRules: serializer.fromJson<bool>(
        json['automaticTrustedRules'],
      ),
      activitySyncEnabled: serializer.fromJson<bool>(
        json['activitySyncEnabled'],
      ),
      activityRuleSyncEnabled: serializer.fromJson<bool>(
        json['activityRuleSyncEnabled'],
      ),
      detailedActivitySyncEnabled: serializer.fromJson<bool>(
        json['detailedActivitySyncEnabled'],
      ),
      localActivityRetentionDays: serializer.fromJson<int>(
        json['localActivityRetentionDays'],
      ),
      hideConfirmedSystemActivity: serializer.fromJson<bool>(
        json['hideConfirmedSystemActivity'],
      ),
      showPossibleSystemActivity: serializer.fromJson<bool>(
        json['showPossibleSystemActivity'],
      ),
      automaticConfidenceThreshold: serializer.fromJson<double>(
        json['automaticConfidenceThreshold'],
      ),
      minimumSuggestionDurationMs: serializer.fromJson<int>(
        json['minimumSuggestionDurationMs'],
      ),
      wakeTimeMinutes: serializer.fromJson<int>(json['wakeTimeMinutes']),
      sleepTimeMinutes: serializer.fromJson<int>(json['sleepTimeMinutes']),
      workingDaysJson: serializer.fromJson<String>(json['workingDaysJson']),
      workStartMinutes: serializer.fromJson<int>(json['workStartMinutes']),
      workEndMinutes: serializer.fromJson<int>(json['workEndMinutes']),
      workScheduleEnabled: serializer.fromJson<bool>(
        json['workScheduleEnabled'],
      ),
      workScheduleRotationJson: serializer.fromJson<String>(
        json['workScheduleRotationJson'],
      ),
      workScheduleAnchorDate: serializer.fromJson<String>(
        json['workScheduleAnchorDate'],
      ),
      workReminderEnabled: serializer.fromJson<bool>(
        json['workReminderEnabled'],
      ),
      workReminderOffsetMinutes: serializer.fromJson<int>(
        json['workReminderOffsetMinutes'],
      ),
      workPomodoroEnabled: serializer.fromJson<bool>(
        json['workPomodoroEnabled'],
      ),
      workActivityCreditEnabled: serializer.fromJson<bool>(
        json['workActivityCreditEnabled'],
      ),
      quietStartMinutes: serializer.fromJson<int>(json['quietStartMinutes']),
      quietEndMinutes: serializer.fromJson<int>(json['quietEndMinutes']),
      sleepReminderEnabled: serializer.fromJson<bool>(
        json['sleepReminderEnabled'],
      ),
      sleepReminderOffsetMinutes: serializer.fromJson<int>(
        json['sleepReminderOffsetMinutes'],
      ),
      phoneUsageAnalysisEnabled: serializer.fromJson<bool>(
        json['phoneUsageAnalysisEnabled'],
      ),
      coachingSensitivity: serializer.fromJson<String>(
        json['coachingSensitivity'],
      ),
      coachingTone: serializer.fromJson<String>(json['coachingTone']),
      healthSummarySyncEnabled: serializer.fromJson<bool>(
        json['healthSummarySyncEnabled'],
      ),
      healthReportPrivacy: serializer.fromJson<String>(
        json['healthReportPrivacy'],
      ),
      notificationPreferencesJson: serializer.fromJson<String>(
        json['notificationPreferencesJson'],
      ),
      countryCode: serializer.fromJson<String>(json['countryCode']),
      dateFormat: serializer.fromJson<String>(json['dateFormat']),
      firstDayOfWeek: serializer.fromJson<int>(json['firstDayOfWeek']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastCommandId: serializer.fromJson<String?>(json['lastCommandId']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'localeCode': serializer.toJson<String>(localeCode),
      'themeKey': serializer.toJson<String>(themeKey),
      'accentColor': serializer.toJson<int>(accentColor),
      'timeZone': serializer.toJson<String>(timeZone),
      'useDeviceTimeZone': serializer.toJson<bool>(useDeviceTimeZone),
      'clockFormat': serializer.toJson<String>(clockFormat),
      'notificationSoundKey': serializer.toJson<String>(notificationSoundKey),
      'healthConnectEnabled': serializer.toJson<bool>(healthConnectEnabled),
      'cycleTrackingEnabled': serializer.toJson<bool>(cycleTrackingEnabled),
      'cycleStorageMode': serializer.toJson<String>(cycleStorageMode),
      'calendarShowCompleted': serializer.toJson<bool>(calendarShowCompleted),
      'applicationTrackingEnabled': serializer.toJson<bool>(
        applicationTrackingEnabled,
      ),
      'windowTitleTrackingEnabled': serializer.toJson<bool>(
        windowTitleTrackingEnabled,
      ),
      'idleDetectionEnabled': serializer.toJson<bool>(idleDetectionEnabled),
      'idleThresholdSeconds': serializer.toJson<int>(idleThresholdSeconds),
      'detectBreakActivity': serializer.toJson<bool>(detectBreakActivity),
      'detectCrossTaskActivity': serializer.toJson<bool>(
        detectCrossTaskActivity,
      ),
      'retainUnclassifiedActivity': serializer.toJson<bool>(
        retainUnclassifiedActivity,
      ),
      'retainTechnicalIdle': serializer.toJson<bool>(retainTechnicalIdle),
      'automaticTrustedRules': serializer.toJson<bool>(automaticTrustedRules),
      'activitySyncEnabled': serializer.toJson<bool>(activitySyncEnabled),
      'activityRuleSyncEnabled': serializer.toJson<bool>(
        activityRuleSyncEnabled,
      ),
      'detailedActivitySyncEnabled': serializer.toJson<bool>(
        detailedActivitySyncEnabled,
      ),
      'localActivityRetentionDays': serializer.toJson<int>(
        localActivityRetentionDays,
      ),
      'hideConfirmedSystemActivity': serializer.toJson<bool>(
        hideConfirmedSystemActivity,
      ),
      'showPossibleSystemActivity': serializer.toJson<bool>(
        showPossibleSystemActivity,
      ),
      'automaticConfidenceThreshold': serializer.toJson<double>(
        automaticConfidenceThreshold,
      ),
      'minimumSuggestionDurationMs': serializer.toJson<int>(
        minimumSuggestionDurationMs,
      ),
      'wakeTimeMinutes': serializer.toJson<int>(wakeTimeMinutes),
      'sleepTimeMinutes': serializer.toJson<int>(sleepTimeMinutes),
      'workingDaysJson': serializer.toJson<String>(workingDaysJson),
      'workStartMinutes': serializer.toJson<int>(workStartMinutes),
      'workEndMinutes': serializer.toJson<int>(workEndMinutes),
      'workScheduleEnabled': serializer.toJson<bool>(workScheduleEnabled),
      'workScheduleRotationJson': serializer.toJson<String>(
        workScheduleRotationJson,
      ),
      'workScheduleAnchorDate': serializer.toJson<String>(
        workScheduleAnchorDate,
      ),
      'workReminderEnabled': serializer.toJson<bool>(workReminderEnabled),
      'workReminderOffsetMinutes': serializer.toJson<int>(
        workReminderOffsetMinutes,
      ),
      'workPomodoroEnabled': serializer.toJson<bool>(workPomodoroEnabled),
      'workActivityCreditEnabled': serializer.toJson<bool>(
        workActivityCreditEnabled,
      ),
      'quietStartMinutes': serializer.toJson<int>(quietStartMinutes),
      'quietEndMinutes': serializer.toJson<int>(quietEndMinutes),
      'sleepReminderEnabled': serializer.toJson<bool>(sleepReminderEnabled),
      'sleepReminderOffsetMinutes': serializer.toJson<int>(
        sleepReminderOffsetMinutes,
      ),
      'phoneUsageAnalysisEnabled': serializer.toJson<bool>(
        phoneUsageAnalysisEnabled,
      ),
      'coachingSensitivity': serializer.toJson<String>(coachingSensitivity),
      'coachingTone': serializer.toJson<String>(coachingTone),
      'healthSummarySyncEnabled': serializer.toJson<bool>(
        healthSummarySyncEnabled,
      ),
      'healthReportPrivacy': serializer.toJson<String>(healthReportPrivacy),
      'notificationPreferencesJson': serializer.toJson<String>(
        notificationPreferencesJson,
      ),
      'countryCode': serializer.toJson<String>(countryCode),
      'dateFormat': serializer.toJson<String>(dateFormat),
      'firstDayOfWeek': serializer.toJson<int>(firstDayOfWeek),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastCommandId': serializer.toJson<String?>(lastCommandId),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalAppSetting copyWith({
    String? id,
    String? userId,
    String? localeCode,
    String? themeKey,
    int? accentColor,
    String? timeZone,
    bool? useDeviceTimeZone,
    String? clockFormat,
    String? notificationSoundKey,
    bool? healthConnectEnabled,
    bool? cycleTrackingEnabled,
    String? cycleStorageMode,
    bool? calendarShowCompleted,
    bool? applicationTrackingEnabled,
    bool? windowTitleTrackingEnabled,
    bool? idleDetectionEnabled,
    int? idleThresholdSeconds,
    bool? detectBreakActivity,
    bool? detectCrossTaskActivity,
    bool? retainUnclassifiedActivity,
    bool? retainTechnicalIdle,
    bool? automaticTrustedRules,
    bool? activitySyncEnabled,
    bool? activityRuleSyncEnabled,
    bool? detailedActivitySyncEnabled,
    int? localActivityRetentionDays,
    bool? hideConfirmedSystemActivity,
    bool? showPossibleSystemActivity,
    double? automaticConfidenceThreshold,
    int? minimumSuggestionDurationMs,
    int? wakeTimeMinutes,
    int? sleepTimeMinutes,
    String? workingDaysJson,
    int? workStartMinutes,
    int? workEndMinutes,
    bool? workScheduleEnabled,
    String? workScheduleRotationJson,
    String? workScheduleAnchorDate,
    bool? workReminderEnabled,
    int? workReminderOffsetMinutes,
    bool? workPomodoroEnabled,
    bool? workActivityCreditEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
    bool? sleepReminderEnabled,
    int? sleepReminderOffsetMinutes,
    bool? phoneUsageAnalysisEnabled,
    String? coachingSensitivity,
    String? coachingTone,
    bool? healthSummarySyncEnabled,
    String? healthReportPrivacy,
    String? notificationPreferencesJson,
    String? countryCode,
    String? dateFormat,
    int? firstDayOfWeek,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> lastCommandId = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalAppSetting(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    localeCode: localeCode ?? this.localeCode,
    themeKey: themeKey ?? this.themeKey,
    accentColor: accentColor ?? this.accentColor,
    timeZone: timeZone ?? this.timeZone,
    useDeviceTimeZone: useDeviceTimeZone ?? this.useDeviceTimeZone,
    clockFormat: clockFormat ?? this.clockFormat,
    notificationSoundKey: notificationSoundKey ?? this.notificationSoundKey,
    healthConnectEnabled: healthConnectEnabled ?? this.healthConnectEnabled,
    cycleTrackingEnabled: cycleTrackingEnabled ?? this.cycleTrackingEnabled,
    cycleStorageMode: cycleStorageMode ?? this.cycleStorageMode,
    calendarShowCompleted: calendarShowCompleted ?? this.calendarShowCompleted,
    applicationTrackingEnabled:
        applicationTrackingEnabled ?? this.applicationTrackingEnabled,
    windowTitleTrackingEnabled:
        windowTitleTrackingEnabled ?? this.windowTitleTrackingEnabled,
    idleDetectionEnabled: idleDetectionEnabled ?? this.idleDetectionEnabled,
    idleThresholdSeconds: idleThresholdSeconds ?? this.idleThresholdSeconds,
    detectBreakActivity: detectBreakActivity ?? this.detectBreakActivity,
    detectCrossTaskActivity:
        detectCrossTaskActivity ?? this.detectCrossTaskActivity,
    retainUnclassifiedActivity:
        retainUnclassifiedActivity ?? this.retainUnclassifiedActivity,
    retainTechnicalIdle: retainTechnicalIdle ?? this.retainTechnicalIdle,
    automaticTrustedRules: automaticTrustedRules ?? this.automaticTrustedRules,
    activitySyncEnabled: activitySyncEnabled ?? this.activitySyncEnabled,
    activityRuleSyncEnabled:
        activityRuleSyncEnabled ?? this.activityRuleSyncEnabled,
    detailedActivitySyncEnabled:
        detailedActivitySyncEnabled ?? this.detailedActivitySyncEnabled,
    localActivityRetentionDays:
        localActivityRetentionDays ?? this.localActivityRetentionDays,
    hideConfirmedSystemActivity:
        hideConfirmedSystemActivity ?? this.hideConfirmedSystemActivity,
    showPossibleSystemActivity:
        showPossibleSystemActivity ?? this.showPossibleSystemActivity,
    automaticConfidenceThreshold:
        automaticConfidenceThreshold ?? this.automaticConfidenceThreshold,
    minimumSuggestionDurationMs:
        minimumSuggestionDurationMs ?? this.minimumSuggestionDurationMs,
    wakeTimeMinutes: wakeTimeMinutes ?? this.wakeTimeMinutes,
    sleepTimeMinutes: sleepTimeMinutes ?? this.sleepTimeMinutes,
    workingDaysJson: workingDaysJson ?? this.workingDaysJson,
    workStartMinutes: workStartMinutes ?? this.workStartMinutes,
    workEndMinutes: workEndMinutes ?? this.workEndMinutes,
    workScheduleEnabled: workScheduleEnabled ?? this.workScheduleEnabled,
    workScheduleRotationJson:
        workScheduleRotationJson ?? this.workScheduleRotationJson,
    workScheduleAnchorDate:
        workScheduleAnchorDate ?? this.workScheduleAnchorDate,
    workReminderEnabled: workReminderEnabled ?? this.workReminderEnabled,
    workReminderOffsetMinutes:
        workReminderOffsetMinutes ?? this.workReminderOffsetMinutes,
    workPomodoroEnabled: workPomodoroEnabled ?? this.workPomodoroEnabled,
    workActivityCreditEnabled:
        workActivityCreditEnabled ?? this.workActivityCreditEnabled,
    quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
    quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    sleepReminderEnabled: sleepReminderEnabled ?? this.sleepReminderEnabled,
    sleepReminderOffsetMinutes:
        sleepReminderOffsetMinutes ?? this.sleepReminderOffsetMinutes,
    phoneUsageAnalysisEnabled:
        phoneUsageAnalysisEnabled ?? this.phoneUsageAnalysisEnabled,
    coachingSensitivity: coachingSensitivity ?? this.coachingSensitivity,
    coachingTone: coachingTone ?? this.coachingTone,
    healthSummarySyncEnabled:
        healthSummarySyncEnabled ?? this.healthSummarySyncEnabled,
    healthReportPrivacy: healthReportPrivacy ?? this.healthReportPrivacy,
    notificationPreferencesJson:
        notificationPreferencesJson ?? this.notificationPreferencesJson,
    countryCode: countryCode ?? this.countryCode,
    dateFormat: dateFormat ?? this.dateFormat,
    firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastCommandId: lastCommandId.present
        ? lastCommandId.value
        : this.lastCommandId,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalAppSetting copyWithCompanion(LocalAppSettingsCompanion data) {
    return LocalAppSetting(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      localeCode: data.localeCode.present
          ? data.localeCode.value
          : this.localeCode,
      themeKey: data.themeKey.present ? data.themeKey.value : this.themeKey,
      accentColor: data.accentColor.present
          ? data.accentColor.value
          : this.accentColor,
      timeZone: data.timeZone.present ? data.timeZone.value : this.timeZone,
      useDeviceTimeZone: data.useDeviceTimeZone.present
          ? data.useDeviceTimeZone.value
          : this.useDeviceTimeZone,
      clockFormat: data.clockFormat.present
          ? data.clockFormat.value
          : this.clockFormat,
      notificationSoundKey: data.notificationSoundKey.present
          ? data.notificationSoundKey.value
          : this.notificationSoundKey,
      healthConnectEnabled: data.healthConnectEnabled.present
          ? data.healthConnectEnabled.value
          : this.healthConnectEnabled,
      cycleTrackingEnabled: data.cycleTrackingEnabled.present
          ? data.cycleTrackingEnabled.value
          : this.cycleTrackingEnabled,
      cycleStorageMode: data.cycleStorageMode.present
          ? data.cycleStorageMode.value
          : this.cycleStorageMode,
      calendarShowCompleted: data.calendarShowCompleted.present
          ? data.calendarShowCompleted.value
          : this.calendarShowCompleted,
      applicationTrackingEnabled: data.applicationTrackingEnabled.present
          ? data.applicationTrackingEnabled.value
          : this.applicationTrackingEnabled,
      windowTitleTrackingEnabled: data.windowTitleTrackingEnabled.present
          ? data.windowTitleTrackingEnabled.value
          : this.windowTitleTrackingEnabled,
      idleDetectionEnabled: data.idleDetectionEnabled.present
          ? data.idleDetectionEnabled.value
          : this.idleDetectionEnabled,
      idleThresholdSeconds: data.idleThresholdSeconds.present
          ? data.idleThresholdSeconds.value
          : this.idleThresholdSeconds,
      detectBreakActivity: data.detectBreakActivity.present
          ? data.detectBreakActivity.value
          : this.detectBreakActivity,
      detectCrossTaskActivity: data.detectCrossTaskActivity.present
          ? data.detectCrossTaskActivity.value
          : this.detectCrossTaskActivity,
      retainUnclassifiedActivity: data.retainUnclassifiedActivity.present
          ? data.retainUnclassifiedActivity.value
          : this.retainUnclassifiedActivity,
      retainTechnicalIdle: data.retainTechnicalIdle.present
          ? data.retainTechnicalIdle.value
          : this.retainTechnicalIdle,
      automaticTrustedRules: data.automaticTrustedRules.present
          ? data.automaticTrustedRules.value
          : this.automaticTrustedRules,
      activitySyncEnabled: data.activitySyncEnabled.present
          ? data.activitySyncEnabled.value
          : this.activitySyncEnabled,
      activityRuleSyncEnabled: data.activityRuleSyncEnabled.present
          ? data.activityRuleSyncEnabled.value
          : this.activityRuleSyncEnabled,
      detailedActivitySyncEnabled: data.detailedActivitySyncEnabled.present
          ? data.detailedActivitySyncEnabled.value
          : this.detailedActivitySyncEnabled,
      localActivityRetentionDays: data.localActivityRetentionDays.present
          ? data.localActivityRetentionDays.value
          : this.localActivityRetentionDays,
      hideConfirmedSystemActivity: data.hideConfirmedSystemActivity.present
          ? data.hideConfirmedSystemActivity.value
          : this.hideConfirmedSystemActivity,
      showPossibleSystemActivity: data.showPossibleSystemActivity.present
          ? data.showPossibleSystemActivity.value
          : this.showPossibleSystemActivity,
      automaticConfidenceThreshold: data.automaticConfidenceThreshold.present
          ? data.automaticConfidenceThreshold.value
          : this.automaticConfidenceThreshold,
      minimumSuggestionDurationMs: data.minimumSuggestionDurationMs.present
          ? data.minimumSuggestionDurationMs.value
          : this.minimumSuggestionDurationMs,
      wakeTimeMinutes: data.wakeTimeMinutes.present
          ? data.wakeTimeMinutes.value
          : this.wakeTimeMinutes,
      sleepTimeMinutes: data.sleepTimeMinutes.present
          ? data.sleepTimeMinutes.value
          : this.sleepTimeMinutes,
      workingDaysJson: data.workingDaysJson.present
          ? data.workingDaysJson.value
          : this.workingDaysJson,
      workStartMinutes: data.workStartMinutes.present
          ? data.workStartMinutes.value
          : this.workStartMinutes,
      workEndMinutes: data.workEndMinutes.present
          ? data.workEndMinutes.value
          : this.workEndMinutes,
      workScheduleEnabled: data.workScheduleEnabled.present
          ? data.workScheduleEnabled.value
          : this.workScheduleEnabled,
      workScheduleRotationJson: data.workScheduleRotationJson.present
          ? data.workScheduleRotationJson.value
          : this.workScheduleRotationJson,
      workScheduleAnchorDate: data.workScheduleAnchorDate.present
          ? data.workScheduleAnchorDate.value
          : this.workScheduleAnchorDate,
      workReminderEnabled: data.workReminderEnabled.present
          ? data.workReminderEnabled.value
          : this.workReminderEnabled,
      workReminderOffsetMinutes: data.workReminderOffsetMinutes.present
          ? data.workReminderOffsetMinutes.value
          : this.workReminderOffsetMinutes,
      workPomodoroEnabled: data.workPomodoroEnabled.present
          ? data.workPomodoroEnabled.value
          : this.workPomodoroEnabled,
      workActivityCreditEnabled: data.workActivityCreditEnabled.present
          ? data.workActivityCreditEnabled.value
          : this.workActivityCreditEnabled,
      quietStartMinutes: data.quietStartMinutes.present
          ? data.quietStartMinutes.value
          : this.quietStartMinutes,
      quietEndMinutes: data.quietEndMinutes.present
          ? data.quietEndMinutes.value
          : this.quietEndMinutes,
      sleepReminderEnabled: data.sleepReminderEnabled.present
          ? data.sleepReminderEnabled.value
          : this.sleepReminderEnabled,
      sleepReminderOffsetMinutes: data.sleepReminderOffsetMinutes.present
          ? data.sleepReminderOffsetMinutes.value
          : this.sleepReminderOffsetMinutes,
      phoneUsageAnalysisEnabled: data.phoneUsageAnalysisEnabled.present
          ? data.phoneUsageAnalysisEnabled.value
          : this.phoneUsageAnalysisEnabled,
      coachingSensitivity: data.coachingSensitivity.present
          ? data.coachingSensitivity.value
          : this.coachingSensitivity,
      coachingTone: data.coachingTone.present
          ? data.coachingTone.value
          : this.coachingTone,
      healthSummarySyncEnabled: data.healthSummarySyncEnabled.present
          ? data.healthSummarySyncEnabled.value
          : this.healthSummarySyncEnabled,
      healthReportPrivacy: data.healthReportPrivacy.present
          ? data.healthReportPrivacy.value
          : this.healthReportPrivacy,
      notificationPreferencesJson: data.notificationPreferencesJson.present
          ? data.notificationPreferencesJson.value
          : this.notificationPreferencesJson,
      countryCode: data.countryCode.present
          ? data.countryCode.value
          : this.countryCode,
      dateFormat: data.dateFormat.present
          ? data.dateFormat.value
          : this.dateFormat,
      firstDayOfWeek: data.firstDayOfWeek.present
          ? data.firstDayOfWeek.value
          : this.firstDayOfWeek,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastCommandId: data.lastCommandId.present
          ? data.lastCommandId.value
          : this.lastCommandId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAppSetting(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('localeCode: $localeCode, ')
          ..write('themeKey: $themeKey, ')
          ..write('accentColor: $accentColor, ')
          ..write('timeZone: $timeZone, ')
          ..write('useDeviceTimeZone: $useDeviceTimeZone, ')
          ..write('clockFormat: $clockFormat, ')
          ..write('notificationSoundKey: $notificationSoundKey, ')
          ..write('healthConnectEnabled: $healthConnectEnabled, ')
          ..write('cycleTrackingEnabled: $cycleTrackingEnabled, ')
          ..write('cycleStorageMode: $cycleStorageMode, ')
          ..write('calendarShowCompleted: $calendarShowCompleted, ')
          ..write('applicationTrackingEnabled: $applicationTrackingEnabled, ')
          ..write('windowTitleTrackingEnabled: $windowTitleTrackingEnabled, ')
          ..write('idleDetectionEnabled: $idleDetectionEnabled, ')
          ..write('idleThresholdSeconds: $idleThresholdSeconds, ')
          ..write('detectBreakActivity: $detectBreakActivity, ')
          ..write('detectCrossTaskActivity: $detectCrossTaskActivity, ')
          ..write('retainUnclassifiedActivity: $retainUnclassifiedActivity, ')
          ..write('retainTechnicalIdle: $retainTechnicalIdle, ')
          ..write('automaticTrustedRules: $automaticTrustedRules, ')
          ..write('activitySyncEnabled: $activitySyncEnabled, ')
          ..write('activityRuleSyncEnabled: $activityRuleSyncEnabled, ')
          ..write('detailedActivitySyncEnabled: $detailedActivitySyncEnabled, ')
          ..write('localActivityRetentionDays: $localActivityRetentionDays, ')
          ..write('hideConfirmedSystemActivity: $hideConfirmedSystemActivity, ')
          ..write('showPossibleSystemActivity: $showPossibleSystemActivity, ')
          ..write(
            'automaticConfidenceThreshold: $automaticConfidenceThreshold, ',
          )
          ..write('minimumSuggestionDurationMs: $minimumSuggestionDurationMs, ')
          ..write('wakeTimeMinutes: $wakeTimeMinutes, ')
          ..write('sleepTimeMinutes: $sleepTimeMinutes, ')
          ..write('workingDaysJson: $workingDaysJson, ')
          ..write('workStartMinutes: $workStartMinutes, ')
          ..write('workEndMinutes: $workEndMinutes, ')
          ..write('workScheduleEnabled: $workScheduleEnabled, ')
          ..write('workScheduleRotationJson: $workScheduleRotationJson, ')
          ..write('workScheduleAnchorDate: $workScheduleAnchorDate, ')
          ..write('workReminderEnabled: $workReminderEnabled, ')
          ..write('workReminderOffsetMinutes: $workReminderOffsetMinutes, ')
          ..write('workPomodoroEnabled: $workPomodoroEnabled, ')
          ..write('workActivityCreditEnabled: $workActivityCreditEnabled, ')
          ..write('quietStartMinutes: $quietStartMinutes, ')
          ..write('quietEndMinutes: $quietEndMinutes, ')
          ..write('sleepReminderEnabled: $sleepReminderEnabled, ')
          ..write('sleepReminderOffsetMinutes: $sleepReminderOffsetMinutes, ')
          ..write('phoneUsageAnalysisEnabled: $phoneUsageAnalysisEnabled, ')
          ..write('coachingSensitivity: $coachingSensitivity, ')
          ..write('coachingTone: $coachingTone, ')
          ..write('healthSummarySyncEnabled: $healthSummarySyncEnabled, ')
          ..write('healthReportPrivacy: $healthReportPrivacy, ')
          ..write('notificationPreferencesJson: $notificationPreferencesJson, ')
          ..write('countryCode: $countryCode, ')
          ..write('dateFormat: $dateFormat, ')
          ..write('firstDayOfWeek: $firstDayOfWeek, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    userId,
    localeCode,
    themeKey,
    accentColor,
    timeZone,
    useDeviceTimeZone,
    clockFormat,
    notificationSoundKey,
    healthConnectEnabled,
    cycleTrackingEnabled,
    cycleStorageMode,
    calendarShowCompleted,
    applicationTrackingEnabled,
    windowTitleTrackingEnabled,
    idleDetectionEnabled,
    idleThresholdSeconds,
    detectBreakActivity,
    detectCrossTaskActivity,
    retainUnclassifiedActivity,
    retainTechnicalIdle,
    automaticTrustedRules,
    activitySyncEnabled,
    activityRuleSyncEnabled,
    detailedActivitySyncEnabled,
    localActivityRetentionDays,
    hideConfirmedSystemActivity,
    showPossibleSystemActivity,
    automaticConfidenceThreshold,
    minimumSuggestionDurationMs,
    wakeTimeMinutes,
    sleepTimeMinutes,
    workingDaysJson,
    workStartMinutes,
    workEndMinutes,
    workScheduleEnabled,
    workScheduleRotationJson,
    workScheduleAnchorDate,
    workReminderEnabled,
    workReminderOffsetMinutes,
    workPomodoroEnabled,
    workActivityCreditEnabled,
    quietStartMinutes,
    quietEndMinutes,
    sleepReminderEnabled,
    sleepReminderOffsetMinutes,
    phoneUsageAnalysisEnabled,
    coachingSensitivity,
    coachingTone,
    healthSummarySyncEnabled,
    healthReportPrivacy,
    notificationPreferencesJson,
    countryCode,
    dateFormat,
    firstDayOfWeek,
    revision,
    createdAt,
    updatedAt,
    lastCommandId,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAppSetting &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.localeCode == this.localeCode &&
          other.themeKey == this.themeKey &&
          other.accentColor == this.accentColor &&
          other.timeZone == this.timeZone &&
          other.useDeviceTimeZone == this.useDeviceTimeZone &&
          other.clockFormat == this.clockFormat &&
          other.notificationSoundKey == this.notificationSoundKey &&
          other.healthConnectEnabled == this.healthConnectEnabled &&
          other.cycleTrackingEnabled == this.cycleTrackingEnabled &&
          other.cycleStorageMode == this.cycleStorageMode &&
          other.calendarShowCompleted == this.calendarShowCompleted &&
          other.applicationTrackingEnabled == this.applicationTrackingEnabled &&
          other.windowTitleTrackingEnabled == this.windowTitleTrackingEnabled &&
          other.idleDetectionEnabled == this.idleDetectionEnabled &&
          other.idleThresholdSeconds == this.idleThresholdSeconds &&
          other.detectBreakActivity == this.detectBreakActivity &&
          other.detectCrossTaskActivity == this.detectCrossTaskActivity &&
          other.retainUnclassifiedActivity == this.retainUnclassifiedActivity &&
          other.retainTechnicalIdle == this.retainTechnicalIdle &&
          other.automaticTrustedRules == this.automaticTrustedRules &&
          other.activitySyncEnabled == this.activitySyncEnabled &&
          other.activityRuleSyncEnabled == this.activityRuleSyncEnabled &&
          other.detailedActivitySyncEnabled ==
              this.detailedActivitySyncEnabled &&
          other.localActivityRetentionDays == this.localActivityRetentionDays &&
          other.hideConfirmedSystemActivity ==
              this.hideConfirmedSystemActivity &&
          other.showPossibleSystemActivity == this.showPossibleSystemActivity &&
          other.automaticConfidenceThreshold ==
              this.automaticConfidenceThreshold &&
          other.minimumSuggestionDurationMs ==
              this.minimumSuggestionDurationMs &&
          other.wakeTimeMinutes == this.wakeTimeMinutes &&
          other.sleepTimeMinutes == this.sleepTimeMinutes &&
          other.workingDaysJson == this.workingDaysJson &&
          other.workStartMinutes == this.workStartMinutes &&
          other.workEndMinutes == this.workEndMinutes &&
          other.workScheduleEnabled == this.workScheduleEnabled &&
          other.workScheduleRotationJson == this.workScheduleRotationJson &&
          other.workScheduleAnchorDate == this.workScheduleAnchorDate &&
          other.workReminderEnabled == this.workReminderEnabled &&
          other.workReminderOffsetMinutes == this.workReminderOffsetMinutes &&
          other.workPomodoroEnabled == this.workPomodoroEnabled &&
          other.workActivityCreditEnabled == this.workActivityCreditEnabled &&
          other.quietStartMinutes == this.quietStartMinutes &&
          other.quietEndMinutes == this.quietEndMinutes &&
          other.sleepReminderEnabled == this.sleepReminderEnabled &&
          other.sleepReminderOffsetMinutes == this.sleepReminderOffsetMinutes &&
          other.phoneUsageAnalysisEnabled == this.phoneUsageAnalysisEnabled &&
          other.coachingSensitivity == this.coachingSensitivity &&
          other.coachingTone == this.coachingTone &&
          other.healthSummarySyncEnabled == this.healthSummarySyncEnabled &&
          other.healthReportPrivacy == this.healthReportPrivacy &&
          other.notificationPreferencesJson ==
              this.notificationPreferencesJson &&
          other.countryCode == this.countryCode &&
          other.dateFormat == this.dateFormat &&
          other.firstDayOfWeek == this.firstDayOfWeek &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastCommandId == this.lastCommandId &&
          other.deletedAt == this.deletedAt);
}

class LocalAppSettingsCompanion extends UpdateCompanion<LocalAppSetting> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> localeCode;
  final Value<String> themeKey;
  final Value<int> accentColor;
  final Value<String> timeZone;
  final Value<bool> useDeviceTimeZone;
  final Value<String> clockFormat;
  final Value<String> notificationSoundKey;
  final Value<bool> healthConnectEnabled;
  final Value<bool> cycleTrackingEnabled;
  final Value<String> cycleStorageMode;
  final Value<bool> calendarShowCompleted;
  final Value<bool> applicationTrackingEnabled;
  final Value<bool> windowTitleTrackingEnabled;
  final Value<bool> idleDetectionEnabled;
  final Value<int> idleThresholdSeconds;
  final Value<bool> detectBreakActivity;
  final Value<bool> detectCrossTaskActivity;
  final Value<bool> retainUnclassifiedActivity;
  final Value<bool> retainTechnicalIdle;
  final Value<bool> automaticTrustedRules;
  final Value<bool> activitySyncEnabled;
  final Value<bool> activityRuleSyncEnabled;
  final Value<bool> detailedActivitySyncEnabled;
  final Value<int> localActivityRetentionDays;
  final Value<bool> hideConfirmedSystemActivity;
  final Value<bool> showPossibleSystemActivity;
  final Value<double> automaticConfidenceThreshold;
  final Value<int> minimumSuggestionDurationMs;
  final Value<int> wakeTimeMinutes;
  final Value<int> sleepTimeMinutes;
  final Value<String> workingDaysJson;
  final Value<int> workStartMinutes;
  final Value<int> workEndMinutes;
  final Value<bool> workScheduleEnabled;
  final Value<String> workScheduleRotationJson;
  final Value<String> workScheduleAnchorDate;
  final Value<bool> workReminderEnabled;
  final Value<int> workReminderOffsetMinutes;
  final Value<bool> workPomodoroEnabled;
  final Value<bool> workActivityCreditEnabled;
  final Value<int> quietStartMinutes;
  final Value<int> quietEndMinutes;
  final Value<bool> sleepReminderEnabled;
  final Value<int> sleepReminderOffsetMinutes;
  final Value<bool> phoneUsageAnalysisEnabled;
  final Value<String> coachingSensitivity;
  final Value<String> coachingTone;
  final Value<bool> healthSummarySyncEnabled;
  final Value<String> healthReportPrivacy;
  final Value<String> notificationPreferencesJson;
  final Value<String> countryCode;
  final Value<String> dateFormat;
  final Value<int> firstDayOfWeek;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> lastCommandId;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalAppSettingsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.localeCode = const Value.absent(),
    this.themeKey = const Value.absent(),
    this.accentColor = const Value.absent(),
    this.timeZone = const Value.absent(),
    this.useDeviceTimeZone = const Value.absent(),
    this.clockFormat = const Value.absent(),
    this.notificationSoundKey = const Value.absent(),
    this.healthConnectEnabled = const Value.absent(),
    this.cycleTrackingEnabled = const Value.absent(),
    this.cycleStorageMode = const Value.absent(),
    this.calendarShowCompleted = const Value.absent(),
    this.applicationTrackingEnabled = const Value.absent(),
    this.windowTitleTrackingEnabled = const Value.absent(),
    this.idleDetectionEnabled = const Value.absent(),
    this.idleThresholdSeconds = const Value.absent(),
    this.detectBreakActivity = const Value.absent(),
    this.detectCrossTaskActivity = const Value.absent(),
    this.retainUnclassifiedActivity = const Value.absent(),
    this.retainTechnicalIdle = const Value.absent(),
    this.automaticTrustedRules = const Value.absent(),
    this.activitySyncEnabled = const Value.absent(),
    this.activityRuleSyncEnabled = const Value.absent(),
    this.detailedActivitySyncEnabled = const Value.absent(),
    this.localActivityRetentionDays = const Value.absent(),
    this.hideConfirmedSystemActivity = const Value.absent(),
    this.showPossibleSystemActivity = const Value.absent(),
    this.automaticConfidenceThreshold = const Value.absent(),
    this.minimumSuggestionDurationMs = const Value.absent(),
    this.wakeTimeMinutes = const Value.absent(),
    this.sleepTimeMinutes = const Value.absent(),
    this.workingDaysJson = const Value.absent(),
    this.workStartMinutes = const Value.absent(),
    this.workEndMinutes = const Value.absent(),
    this.workScheduleEnabled = const Value.absent(),
    this.workScheduleRotationJson = const Value.absent(),
    this.workScheduleAnchorDate = const Value.absent(),
    this.workReminderEnabled = const Value.absent(),
    this.workReminderOffsetMinutes = const Value.absent(),
    this.workPomodoroEnabled = const Value.absent(),
    this.workActivityCreditEnabled = const Value.absent(),
    this.quietStartMinutes = const Value.absent(),
    this.quietEndMinutes = const Value.absent(),
    this.sleepReminderEnabled = const Value.absent(),
    this.sleepReminderOffsetMinutes = const Value.absent(),
    this.phoneUsageAnalysisEnabled = const Value.absent(),
    this.coachingSensitivity = const Value.absent(),
    this.coachingTone = const Value.absent(),
    this.healthSummarySyncEnabled = const Value.absent(),
    this.healthReportPrivacy = const Value.absent(),
    this.notificationPreferencesJson = const Value.absent(),
    this.countryCode = const Value.absent(),
    this.dateFormat = const Value.absent(),
    this.firstDayOfWeek = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAppSettingsCompanion.insert({
    required String id,
    this.userId = const Value.absent(),
    this.localeCode = const Value.absent(),
    this.themeKey = const Value.absent(),
    this.accentColor = const Value.absent(),
    this.timeZone = const Value.absent(),
    this.useDeviceTimeZone = const Value.absent(),
    this.clockFormat = const Value.absent(),
    this.notificationSoundKey = const Value.absent(),
    this.healthConnectEnabled = const Value.absent(),
    this.cycleTrackingEnabled = const Value.absent(),
    this.cycleStorageMode = const Value.absent(),
    this.calendarShowCompleted = const Value.absent(),
    this.applicationTrackingEnabled = const Value.absent(),
    this.windowTitleTrackingEnabled = const Value.absent(),
    this.idleDetectionEnabled = const Value.absent(),
    this.idleThresholdSeconds = const Value.absent(),
    this.detectBreakActivity = const Value.absent(),
    this.detectCrossTaskActivity = const Value.absent(),
    this.retainUnclassifiedActivity = const Value.absent(),
    this.retainTechnicalIdle = const Value.absent(),
    this.automaticTrustedRules = const Value.absent(),
    this.activitySyncEnabled = const Value.absent(),
    this.activityRuleSyncEnabled = const Value.absent(),
    this.detailedActivitySyncEnabled = const Value.absent(),
    this.localActivityRetentionDays = const Value.absent(),
    this.hideConfirmedSystemActivity = const Value.absent(),
    this.showPossibleSystemActivity = const Value.absent(),
    this.automaticConfidenceThreshold = const Value.absent(),
    this.minimumSuggestionDurationMs = const Value.absent(),
    this.wakeTimeMinutes = const Value.absent(),
    this.sleepTimeMinutes = const Value.absent(),
    this.workingDaysJson = const Value.absent(),
    this.workStartMinutes = const Value.absent(),
    this.workEndMinutes = const Value.absent(),
    this.workScheduleEnabled = const Value.absent(),
    this.workScheduleRotationJson = const Value.absent(),
    this.workScheduleAnchorDate = const Value.absent(),
    this.workReminderEnabled = const Value.absent(),
    this.workReminderOffsetMinutes = const Value.absent(),
    this.workPomodoroEnabled = const Value.absent(),
    this.workActivityCreditEnabled = const Value.absent(),
    this.quietStartMinutes = const Value.absent(),
    this.quietEndMinutes = const Value.absent(),
    this.sleepReminderEnabled = const Value.absent(),
    this.sleepReminderOffsetMinutes = const Value.absent(),
    this.phoneUsageAnalysisEnabled = const Value.absent(),
    this.coachingSensitivity = const Value.absent(),
    this.coachingTone = const Value.absent(),
    this.healthSummarySyncEnabled = const Value.absent(),
    this.healthReportPrivacy = const Value.absent(),
    this.notificationPreferencesJson = const Value.absent(),
    this.countryCode = const Value.absent(),
    this.dateFormat = const Value.absent(),
    this.firstDayOfWeek = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalAppSetting> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? localeCode,
    Expression<String>? themeKey,
    Expression<int>? accentColor,
    Expression<String>? timeZone,
    Expression<bool>? useDeviceTimeZone,
    Expression<String>? clockFormat,
    Expression<String>? notificationSoundKey,
    Expression<bool>? healthConnectEnabled,
    Expression<bool>? cycleTrackingEnabled,
    Expression<String>? cycleStorageMode,
    Expression<bool>? calendarShowCompleted,
    Expression<bool>? applicationTrackingEnabled,
    Expression<bool>? windowTitleTrackingEnabled,
    Expression<bool>? idleDetectionEnabled,
    Expression<int>? idleThresholdSeconds,
    Expression<bool>? detectBreakActivity,
    Expression<bool>? detectCrossTaskActivity,
    Expression<bool>? retainUnclassifiedActivity,
    Expression<bool>? retainTechnicalIdle,
    Expression<bool>? automaticTrustedRules,
    Expression<bool>? activitySyncEnabled,
    Expression<bool>? activityRuleSyncEnabled,
    Expression<bool>? detailedActivitySyncEnabled,
    Expression<int>? localActivityRetentionDays,
    Expression<bool>? hideConfirmedSystemActivity,
    Expression<bool>? showPossibleSystemActivity,
    Expression<double>? automaticConfidenceThreshold,
    Expression<int>? minimumSuggestionDurationMs,
    Expression<int>? wakeTimeMinutes,
    Expression<int>? sleepTimeMinutes,
    Expression<String>? workingDaysJson,
    Expression<int>? workStartMinutes,
    Expression<int>? workEndMinutes,
    Expression<bool>? workScheduleEnabled,
    Expression<String>? workScheduleRotationJson,
    Expression<String>? workScheduleAnchorDate,
    Expression<bool>? workReminderEnabled,
    Expression<int>? workReminderOffsetMinutes,
    Expression<bool>? workPomodoroEnabled,
    Expression<bool>? workActivityCreditEnabled,
    Expression<int>? quietStartMinutes,
    Expression<int>? quietEndMinutes,
    Expression<bool>? sleepReminderEnabled,
    Expression<int>? sleepReminderOffsetMinutes,
    Expression<bool>? phoneUsageAnalysisEnabled,
    Expression<String>? coachingSensitivity,
    Expression<String>? coachingTone,
    Expression<bool>? healthSummarySyncEnabled,
    Expression<String>? healthReportPrivacy,
    Expression<String>? notificationPreferencesJson,
    Expression<String>? countryCode,
    Expression<String>? dateFormat,
    Expression<int>? firstDayOfWeek,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? lastCommandId,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (localeCode != null) 'locale_code': localeCode,
      if (themeKey != null) 'theme_key': themeKey,
      if (accentColor != null) 'accent_color': accentColor,
      if (timeZone != null) 'time_zone': timeZone,
      if (useDeviceTimeZone != null) 'use_device_time_zone': useDeviceTimeZone,
      if (clockFormat != null) 'clock_format': clockFormat,
      if (notificationSoundKey != null)
        'notification_sound_key': notificationSoundKey,
      if (healthConnectEnabled != null)
        'health_connect_enabled': healthConnectEnabled,
      if (cycleTrackingEnabled != null)
        'cycle_tracking_enabled': cycleTrackingEnabled,
      if (cycleStorageMode != null) 'cycle_storage_mode': cycleStorageMode,
      if (calendarShowCompleted != null)
        'calendar_show_completed': calendarShowCompleted,
      if (applicationTrackingEnabled != null)
        'application_tracking_enabled': applicationTrackingEnabled,
      if (windowTitleTrackingEnabled != null)
        'window_title_tracking_enabled': windowTitleTrackingEnabled,
      if (idleDetectionEnabled != null)
        'idle_detection_enabled': idleDetectionEnabled,
      if (idleThresholdSeconds != null)
        'idle_threshold_seconds': idleThresholdSeconds,
      if (detectBreakActivity != null)
        'detect_break_activity': detectBreakActivity,
      if (detectCrossTaskActivity != null)
        'detect_cross_task_activity': detectCrossTaskActivity,
      if (retainUnclassifiedActivity != null)
        'retain_unclassified_activity': retainUnclassifiedActivity,
      if (retainTechnicalIdle != null)
        'retain_technical_idle': retainTechnicalIdle,
      if (automaticTrustedRules != null)
        'automatic_trusted_rules': automaticTrustedRules,
      if (activitySyncEnabled != null)
        'activity_sync_enabled': activitySyncEnabled,
      if (activityRuleSyncEnabled != null)
        'activity_rule_sync_enabled': activityRuleSyncEnabled,
      if (detailedActivitySyncEnabled != null)
        'detailed_activity_sync_enabled': detailedActivitySyncEnabled,
      if (localActivityRetentionDays != null)
        'local_activity_retention_days': localActivityRetentionDays,
      if (hideConfirmedSystemActivity != null)
        'hide_confirmed_system_activity': hideConfirmedSystemActivity,
      if (showPossibleSystemActivity != null)
        'show_possible_system_activity': showPossibleSystemActivity,
      if (automaticConfidenceThreshold != null)
        'automatic_confidence_threshold': automaticConfidenceThreshold,
      if (minimumSuggestionDurationMs != null)
        'minimum_suggestion_duration_ms': minimumSuggestionDurationMs,
      if (wakeTimeMinutes != null) 'wake_time_minutes': wakeTimeMinutes,
      if (sleepTimeMinutes != null) 'sleep_time_minutes': sleepTimeMinutes,
      if (workingDaysJson != null) 'working_days_json': workingDaysJson,
      if (workStartMinutes != null) 'work_start_minutes': workStartMinutes,
      if (workEndMinutes != null) 'work_end_minutes': workEndMinutes,
      if (workScheduleEnabled != null)
        'work_schedule_enabled': workScheduleEnabled,
      if (workScheduleRotationJson != null)
        'work_schedule_rotation_json': workScheduleRotationJson,
      if (workScheduleAnchorDate != null)
        'work_schedule_anchor_date': workScheduleAnchorDate,
      if (workReminderEnabled != null)
        'work_reminder_enabled': workReminderEnabled,
      if (workReminderOffsetMinutes != null)
        'work_reminder_offset_minutes': workReminderOffsetMinutes,
      if (workPomodoroEnabled != null)
        'work_pomodoro_enabled': workPomodoroEnabled,
      if (workActivityCreditEnabled != null)
        'work_activity_credit_enabled': workActivityCreditEnabled,
      if (quietStartMinutes != null) 'quiet_start_minutes': quietStartMinutes,
      if (quietEndMinutes != null) 'quiet_end_minutes': quietEndMinutes,
      if (sleepReminderEnabled != null)
        'sleep_reminder_enabled': sleepReminderEnabled,
      if (sleepReminderOffsetMinutes != null)
        'sleep_reminder_offset_minutes': sleepReminderOffsetMinutes,
      if (phoneUsageAnalysisEnabled != null)
        'phone_usage_analysis_enabled': phoneUsageAnalysisEnabled,
      if (coachingSensitivity != null)
        'coaching_sensitivity': coachingSensitivity,
      if (coachingTone != null) 'coaching_tone': coachingTone,
      if (healthSummarySyncEnabled != null)
        'health_summary_sync_enabled': healthSummarySyncEnabled,
      if (healthReportPrivacy != null)
        'health_report_privacy': healthReportPrivacy,
      if (notificationPreferencesJson != null)
        'notification_preferences_json': notificationPreferencesJson,
      if (countryCode != null) 'country_code': countryCode,
      if (dateFormat != null) 'date_format': dateFormat,
      if (firstDayOfWeek != null) 'first_day_of_week': firstDayOfWeek,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastCommandId != null) 'last_command_id': lastCommandId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAppSettingsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? localeCode,
    Value<String>? themeKey,
    Value<int>? accentColor,
    Value<String>? timeZone,
    Value<bool>? useDeviceTimeZone,
    Value<String>? clockFormat,
    Value<String>? notificationSoundKey,
    Value<bool>? healthConnectEnabled,
    Value<bool>? cycleTrackingEnabled,
    Value<String>? cycleStorageMode,
    Value<bool>? calendarShowCompleted,
    Value<bool>? applicationTrackingEnabled,
    Value<bool>? windowTitleTrackingEnabled,
    Value<bool>? idleDetectionEnabled,
    Value<int>? idleThresholdSeconds,
    Value<bool>? detectBreakActivity,
    Value<bool>? detectCrossTaskActivity,
    Value<bool>? retainUnclassifiedActivity,
    Value<bool>? retainTechnicalIdle,
    Value<bool>? automaticTrustedRules,
    Value<bool>? activitySyncEnabled,
    Value<bool>? activityRuleSyncEnabled,
    Value<bool>? detailedActivitySyncEnabled,
    Value<int>? localActivityRetentionDays,
    Value<bool>? hideConfirmedSystemActivity,
    Value<bool>? showPossibleSystemActivity,
    Value<double>? automaticConfidenceThreshold,
    Value<int>? minimumSuggestionDurationMs,
    Value<int>? wakeTimeMinutes,
    Value<int>? sleepTimeMinutes,
    Value<String>? workingDaysJson,
    Value<int>? workStartMinutes,
    Value<int>? workEndMinutes,
    Value<bool>? workScheduleEnabled,
    Value<String>? workScheduleRotationJson,
    Value<String>? workScheduleAnchorDate,
    Value<bool>? workReminderEnabled,
    Value<int>? workReminderOffsetMinutes,
    Value<bool>? workPomodoroEnabled,
    Value<bool>? workActivityCreditEnabled,
    Value<int>? quietStartMinutes,
    Value<int>? quietEndMinutes,
    Value<bool>? sleepReminderEnabled,
    Value<int>? sleepReminderOffsetMinutes,
    Value<bool>? phoneUsageAnalysisEnabled,
    Value<String>? coachingSensitivity,
    Value<String>? coachingTone,
    Value<bool>? healthSummarySyncEnabled,
    Value<String>? healthReportPrivacy,
    Value<String>? notificationPreferencesJson,
    Value<String>? countryCode,
    Value<String>? dateFormat,
    Value<int>? firstDayOfWeek,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? lastCommandId,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalAppSettingsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      localeCode: localeCode ?? this.localeCode,
      themeKey: themeKey ?? this.themeKey,
      accentColor: accentColor ?? this.accentColor,
      timeZone: timeZone ?? this.timeZone,
      useDeviceTimeZone: useDeviceTimeZone ?? this.useDeviceTimeZone,
      clockFormat: clockFormat ?? this.clockFormat,
      notificationSoundKey: notificationSoundKey ?? this.notificationSoundKey,
      healthConnectEnabled: healthConnectEnabled ?? this.healthConnectEnabled,
      cycleTrackingEnabled: cycleTrackingEnabled ?? this.cycleTrackingEnabled,
      cycleStorageMode: cycleStorageMode ?? this.cycleStorageMode,
      calendarShowCompleted:
          calendarShowCompleted ?? this.calendarShowCompleted,
      applicationTrackingEnabled:
          applicationTrackingEnabled ?? this.applicationTrackingEnabled,
      windowTitleTrackingEnabled:
          windowTitleTrackingEnabled ?? this.windowTitleTrackingEnabled,
      idleDetectionEnabled: idleDetectionEnabled ?? this.idleDetectionEnabled,
      idleThresholdSeconds: idleThresholdSeconds ?? this.idleThresholdSeconds,
      detectBreakActivity: detectBreakActivity ?? this.detectBreakActivity,
      detectCrossTaskActivity:
          detectCrossTaskActivity ?? this.detectCrossTaskActivity,
      retainUnclassifiedActivity:
          retainUnclassifiedActivity ?? this.retainUnclassifiedActivity,
      retainTechnicalIdle: retainTechnicalIdle ?? this.retainTechnicalIdle,
      automaticTrustedRules:
          automaticTrustedRules ?? this.automaticTrustedRules,
      activitySyncEnabled: activitySyncEnabled ?? this.activitySyncEnabled,
      activityRuleSyncEnabled:
          activityRuleSyncEnabled ?? this.activityRuleSyncEnabled,
      detailedActivitySyncEnabled:
          detailedActivitySyncEnabled ?? this.detailedActivitySyncEnabled,
      localActivityRetentionDays:
          localActivityRetentionDays ?? this.localActivityRetentionDays,
      hideConfirmedSystemActivity:
          hideConfirmedSystemActivity ?? this.hideConfirmedSystemActivity,
      showPossibleSystemActivity:
          showPossibleSystemActivity ?? this.showPossibleSystemActivity,
      automaticConfidenceThreshold:
          automaticConfidenceThreshold ?? this.automaticConfidenceThreshold,
      minimumSuggestionDurationMs:
          minimumSuggestionDurationMs ?? this.minimumSuggestionDurationMs,
      wakeTimeMinutes: wakeTimeMinutes ?? this.wakeTimeMinutes,
      sleepTimeMinutes: sleepTimeMinutes ?? this.sleepTimeMinutes,
      workingDaysJson: workingDaysJson ?? this.workingDaysJson,
      workStartMinutes: workStartMinutes ?? this.workStartMinutes,
      workEndMinutes: workEndMinutes ?? this.workEndMinutes,
      workScheduleEnabled: workScheduleEnabled ?? this.workScheduleEnabled,
      workScheduleRotationJson:
          workScheduleRotationJson ?? this.workScheduleRotationJson,
      workScheduleAnchorDate:
          workScheduleAnchorDate ?? this.workScheduleAnchorDate,
      workReminderEnabled: workReminderEnabled ?? this.workReminderEnabled,
      workReminderOffsetMinutes:
          workReminderOffsetMinutes ?? this.workReminderOffsetMinutes,
      workPomodoroEnabled: workPomodoroEnabled ?? this.workPomodoroEnabled,
      workActivityCreditEnabled:
          workActivityCreditEnabled ?? this.workActivityCreditEnabled,
      quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
      quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
      sleepReminderEnabled: sleepReminderEnabled ?? this.sleepReminderEnabled,
      sleepReminderOffsetMinutes:
          sleepReminderOffsetMinutes ?? this.sleepReminderOffsetMinutes,
      phoneUsageAnalysisEnabled:
          phoneUsageAnalysisEnabled ?? this.phoneUsageAnalysisEnabled,
      coachingSensitivity: coachingSensitivity ?? this.coachingSensitivity,
      coachingTone: coachingTone ?? this.coachingTone,
      healthSummarySyncEnabled:
          healthSummarySyncEnabled ?? this.healthSummarySyncEnabled,
      healthReportPrivacy: healthReportPrivacy ?? this.healthReportPrivacy,
      notificationPreferencesJson:
          notificationPreferencesJson ?? this.notificationPreferencesJson,
      countryCode: countryCode ?? this.countryCode,
      dateFormat: dateFormat ?? this.dateFormat,
      firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastCommandId: lastCommandId ?? this.lastCommandId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (localeCode.present) {
      map['locale_code'] = Variable<String>(localeCode.value);
    }
    if (themeKey.present) {
      map['theme_key'] = Variable<String>(themeKey.value);
    }
    if (accentColor.present) {
      map['accent_color'] = Variable<int>(accentColor.value);
    }
    if (timeZone.present) {
      map['time_zone'] = Variable<String>(timeZone.value);
    }
    if (useDeviceTimeZone.present) {
      map['use_device_time_zone'] = Variable<bool>(useDeviceTimeZone.value);
    }
    if (clockFormat.present) {
      map['clock_format'] = Variable<String>(clockFormat.value);
    }
    if (notificationSoundKey.present) {
      map['notification_sound_key'] = Variable<String>(
        notificationSoundKey.value,
      );
    }
    if (healthConnectEnabled.present) {
      map['health_connect_enabled'] = Variable<bool>(
        healthConnectEnabled.value,
      );
    }
    if (cycleTrackingEnabled.present) {
      map['cycle_tracking_enabled'] = Variable<bool>(
        cycleTrackingEnabled.value,
      );
    }
    if (cycleStorageMode.present) {
      map['cycle_storage_mode'] = Variable<String>(cycleStorageMode.value);
    }
    if (calendarShowCompleted.present) {
      map['calendar_show_completed'] = Variable<bool>(
        calendarShowCompleted.value,
      );
    }
    if (applicationTrackingEnabled.present) {
      map['application_tracking_enabled'] = Variable<bool>(
        applicationTrackingEnabled.value,
      );
    }
    if (windowTitleTrackingEnabled.present) {
      map['window_title_tracking_enabled'] = Variable<bool>(
        windowTitleTrackingEnabled.value,
      );
    }
    if (idleDetectionEnabled.present) {
      map['idle_detection_enabled'] = Variable<bool>(
        idleDetectionEnabled.value,
      );
    }
    if (idleThresholdSeconds.present) {
      map['idle_threshold_seconds'] = Variable<int>(idleThresholdSeconds.value);
    }
    if (detectBreakActivity.present) {
      map['detect_break_activity'] = Variable<bool>(detectBreakActivity.value);
    }
    if (detectCrossTaskActivity.present) {
      map['detect_cross_task_activity'] = Variable<bool>(
        detectCrossTaskActivity.value,
      );
    }
    if (retainUnclassifiedActivity.present) {
      map['retain_unclassified_activity'] = Variable<bool>(
        retainUnclassifiedActivity.value,
      );
    }
    if (retainTechnicalIdle.present) {
      map['retain_technical_idle'] = Variable<bool>(retainTechnicalIdle.value);
    }
    if (automaticTrustedRules.present) {
      map['automatic_trusted_rules'] = Variable<bool>(
        automaticTrustedRules.value,
      );
    }
    if (activitySyncEnabled.present) {
      map['activity_sync_enabled'] = Variable<bool>(activitySyncEnabled.value);
    }
    if (activityRuleSyncEnabled.present) {
      map['activity_rule_sync_enabled'] = Variable<bool>(
        activityRuleSyncEnabled.value,
      );
    }
    if (detailedActivitySyncEnabled.present) {
      map['detailed_activity_sync_enabled'] = Variable<bool>(
        detailedActivitySyncEnabled.value,
      );
    }
    if (localActivityRetentionDays.present) {
      map['local_activity_retention_days'] = Variable<int>(
        localActivityRetentionDays.value,
      );
    }
    if (hideConfirmedSystemActivity.present) {
      map['hide_confirmed_system_activity'] = Variable<bool>(
        hideConfirmedSystemActivity.value,
      );
    }
    if (showPossibleSystemActivity.present) {
      map['show_possible_system_activity'] = Variable<bool>(
        showPossibleSystemActivity.value,
      );
    }
    if (automaticConfidenceThreshold.present) {
      map['automatic_confidence_threshold'] = Variable<double>(
        automaticConfidenceThreshold.value,
      );
    }
    if (minimumSuggestionDurationMs.present) {
      map['minimum_suggestion_duration_ms'] = Variable<int>(
        minimumSuggestionDurationMs.value,
      );
    }
    if (wakeTimeMinutes.present) {
      map['wake_time_minutes'] = Variable<int>(wakeTimeMinutes.value);
    }
    if (sleepTimeMinutes.present) {
      map['sleep_time_minutes'] = Variable<int>(sleepTimeMinutes.value);
    }
    if (workingDaysJson.present) {
      map['working_days_json'] = Variable<String>(workingDaysJson.value);
    }
    if (workStartMinutes.present) {
      map['work_start_minutes'] = Variable<int>(workStartMinutes.value);
    }
    if (workEndMinutes.present) {
      map['work_end_minutes'] = Variable<int>(workEndMinutes.value);
    }
    if (workScheduleEnabled.present) {
      map['work_schedule_enabled'] = Variable<bool>(workScheduleEnabled.value);
    }
    if (workScheduleRotationJson.present) {
      map['work_schedule_rotation_json'] = Variable<String>(
        workScheduleRotationJson.value,
      );
    }
    if (workScheduleAnchorDate.present) {
      map['work_schedule_anchor_date'] = Variable<String>(
        workScheduleAnchorDate.value,
      );
    }
    if (workReminderEnabled.present) {
      map['work_reminder_enabled'] = Variable<bool>(workReminderEnabled.value);
    }
    if (workReminderOffsetMinutes.present) {
      map['work_reminder_offset_minutes'] = Variable<int>(
        workReminderOffsetMinutes.value,
      );
    }
    if (workPomodoroEnabled.present) {
      map['work_pomodoro_enabled'] = Variable<bool>(workPomodoroEnabled.value);
    }
    if (workActivityCreditEnabled.present) {
      map['work_activity_credit_enabled'] = Variable<bool>(
        workActivityCreditEnabled.value,
      );
    }
    if (quietStartMinutes.present) {
      map['quiet_start_minutes'] = Variable<int>(quietStartMinutes.value);
    }
    if (quietEndMinutes.present) {
      map['quiet_end_minutes'] = Variable<int>(quietEndMinutes.value);
    }
    if (sleepReminderEnabled.present) {
      map['sleep_reminder_enabled'] = Variable<bool>(
        sleepReminderEnabled.value,
      );
    }
    if (sleepReminderOffsetMinutes.present) {
      map['sleep_reminder_offset_minutes'] = Variable<int>(
        sleepReminderOffsetMinutes.value,
      );
    }
    if (phoneUsageAnalysisEnabled.present) {
      map['phone_usage_analysis_enabled'] = Variable<bool>(
        phoneUsageAnalysisEnabled.value,
      );
    }
    if (coachingSensitivity.present) {
      map['coaching_sensitivity'] = Variable<String>(coachingSensitivity.value);
    }
    if (coachingTone.present) {
      map['coaching_tone'] = Variable<String>(coachingTone.value);
    }
    if (healthSummarySyncEnabled.present) {
      map['health_summary_sync_enabled'] = Variable<bool>(
        healthSummarySyncEnabled.value,
      );
    }
    if (healthReportPrivacy.present) {
      map['health_report_privacy'] = Variable<String>(
        healthReportPrivacy.value,
      );
    }
    if (notificationPreferencesJson.present) {
      map['notification_preferences_json'] = Variable<String>(
        notificationPreferencesJson.value,
      );
    }
    if (countryCode.present) {
      map['country_code'] = Variable<String>(countryCode.value);
    }
    if (dateFormat.present) {
      map['date_format'] = Variable<String>(dateFormat.value);
    }
    if (firstDayOfWeek.present) {
      map['first_day_of_week'] = Variable<int>(firstDayOfWeek.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastCommandId.present) {
      map['last_command_id'] = Variable<String>(lastCommandId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('localeCode: $localeCode, ')
          ..write('themeKey: $themeKey, ')
          ..write('accentColor: $accentColor, ')
          ..write('timeZone: $timeZone, ')
          ..write('useDeviceTimeZone: $useDeviceTimeZone, ')
          ..write('clockFormat: $clockFormat, ')
          ..write('notificationSoundKey: $notificationSoundKey, ')
          ..write('healthConnectEnabled: $healthConnectEnabled, ')
          ..write('cycleTrackingEnabled: $cycleTrackingEnabled, ')
          ..write('cycleStorageMode: $cycleStorageMode, ')
          ..write('calendarShowCompleted: $calendarShowCompleted, ')
          ..write('applicationTrackingEnabled: $applicationTrackingEnabled, ')
          ..write('windowTitleTrackingEnabled: $windowTitleTrackingEnabled, ')
          ..write('idleDetectionEnabled: $idleDetectionEnabled, ')
          ..write('idleThresholdSeconds: $idleThresholdSeconds, ')
          ..write('detectBreakActivity: $detectBreakActivity, ')
          ..write('detectCrossTaskActivity: $detectCrossTaskActivity, ')
          ..write('retainUnclassifiedActivity: $retainUnclassifiedActivity, ')
          ..write('retainTechnicalIdle: $retainTechnicalIdle, ')
          ..write('automaticTrustedRules: $automaticTrustedRules, ')
          ..write('activitySyncEnabled: $activitySyncEnabled, ')
          ..write('activityRuleSyncEnabled: $activityRuleSyncEnabled, ')
          ..write('detailedActivitySyncEnabled: $detailedActivitySyncEnabled, ')
          ..write('localActivityRetentionDays: $localActivityRetentionDays, ')
          ..write('hideConfirmedSystemActivity: $hideConfirmedSystemActivity, ')
          ..write('showPossibleSystemActivity: $showPossibleSystemActivity, ')
          ..write(
            'automaticConfidenceThreshold: $automaticConfidenceThreshold, ',
          )
          ..write('minimumSuggestionDurationMs: $minimumSuggestionDurationMs, ')
          ..write('wakeTimeMinutes: $wakeTimeMinutes, ')
          ..write('sleepTimeMinutes: $sleepTimeMinutes, ')
          ..write('workingDaysJson: $workingDaysJson, ')
          ..write('workStartMinutes: $workStartMinutes, ')
          ..write('workEndMinutes: $workEndMinutes, ')
          ..write('workScheduleEnabled: $workScheduleEnabled, ')
          ..write('workScheduleRotationJson: $workScheduleRotationJson, ')
          ..write('workScheduleAnchorDate: $workScheduleAnchorDate, ')
          ..write('workReminderEnabled: $workReminderEnabled, ')
          ..write('workReminderOffsetMinutes: $workReminderOffsetMinutes, ')
          ..write('workPomodoroEnabled: $workPomodoroEnabled, ')
          ..write('workActivityCreditEnabled: $workActivityCreditEnabled, ')
          ..write('quietStartMinutes: $quietStartMinutes, ')
          ..write('quietEndMinutes: $quietEndMinutes, ')
          ..write('sleepReminderEnabled: $sleepReminderEnabled, ')
          ..write('sleepReminderOffsetMinutes: $sleepReminderOffsetMinutes, ')
          ..write('phoneUsageAnalysisEnabled: $phoneUsageAnalysisEnabled, ')
          ..write('coachingSensitivity: $coachingSensitivity, ')
          ..write('coachingTone: $coachingTone, ')
          ..write('healthSummarySyncEnabled: $healthSummarySyncEnabled, ')
          ..write('healthReportPrivacy: $healthReportPrivacy, ')
          ..write('notificationPreferencesJson: $notificationPreferencesJson, ')
          ..write('countryCode: $countryCode, ')
          ..write('dateFormat: $dateFormat, ')
          ..write('firstDayOfWeek: $firstDayOfWeek, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalDomainsTable extends LocalDomains
    with TableInfo<$LocalDomainsTable, LocalDomain> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalDomainsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _iconNameMeta = const VerificationMeta(
    'iconName',
  );
  @override
  late final GeneratedColumn<String> iconName = GeneratedColumn<String>(
    'icon_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('folder'),
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
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<double> position = GeneratedColumn<double>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdByDeviceIdMeta = const VerificationMeta(
    'createdByDeviceId',
  );
  @override
  late final GeneratedColumn<String> createdByDeviceId =
      GeneratedColumn<String>(
        'created_by_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedByDeviceIdMeta = const VerificationMeta(
    'updatedByDeviceId',
  );
  @override
  late final GeneratedColumn<String> updatedByDeviceId =
      GeneratedColumn<String>(
        'updated_by_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCommandIdMeta = const VerificationMeta(
    'lastCommandId',
  );
  @override
  late final GeneratedColumn<String> lastCommandId = GeneratedColumn<String>(
    'last_command_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    iconName,
    colorValue,
    position,
    archivedAt,
    revision,
    createdAt,
    updatedAt,
    createdByDeviceId,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_domains';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalDomain> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon_name')) {
      context.handle(
        _iconNameMeta,
        iconName.isAcceptableOrUnknown(data['icon_name']!, _iconNameMeta),
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
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('created_by_device_id')) {
      context.handle(
        _createdByDeviceIdMeta,
        createdByDeviceId.isAcceptableOrUnknown(
          data['created_by_device_id']!,
          _createdByDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('updated_by_device_id')) {
      context.handle(
        _updatedByDeviceIdMeta,
        updatedByDeviceId.isAcceptableOrUnknown(
          data['updated_by_device_id']!,
          _updatedByDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('last_command_id')) {
      context.handle(
        _lastCommandIdMeta,
        lastCommandId.isAcceptableOrUnknown(
          data['last_command_id']!,
          _lastCommandIdMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalDomain map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalDomain(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      iconName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}position'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      createdByDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_device_id'],
      ),
      updatedByDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device_id'],
      ),
      lastCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_command_id'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalDomainsTable createAlias(String alias) {
    return $LocalDomainsTable(attachedDatabase, alias);
  }
}

class LocalDomain extends DataClass implements Insertable<LocalDomain> {
  final String id;
  final String userId;
  final String name;
  final String iconName;
  final int colorValue;
  final double position;
  final DateTime? archivedAt;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByDeviceId;
  final String? updatedByDeviceId;
  final String? lastCommandId;
  final DateTime? deletedAt;
  const LocalDomain({
    required this.id,
    required this.userId,
    required this.name,
    required this.iconName,
    required this.colorValue,
    required this.position,
    this.archivedAt,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.createdByDeviceId,
    this.updatedByDeviceId,
    this.lastCommandId,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['icon_name'] = Variable<String>(iconName);
    map['color_value'] = Variable<int>(colorValue);
    map['position'] = Variable<double>(position);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || createdByDeviceId != null) {
      map['created_by_device_id'] = Variable<String>(createdByDeviceId);
    }
    if (!nullToAbsent || updatedByDeviceId != null) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId);
    }
    if (!nullToAbsent || lastCommandId != null) {
      map['last_command_id'] = Variable<String>(lastCommandId);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalDomainsCompanion toCompanion(bool nullToAbsent) {
    return LocalDomainsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      iconName: Value(iconName),
      colorValue: Value(colorValue),
      position: Value(position),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      createdByDeviceId: createdByDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(createdByDeviceId),
      updatedByDeviceId: updatedByDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedByDeviceId),
      lastCommandId: lastCommandId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommandId),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalDomain.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalDomain(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      iconName: serializer.fromJson<String>(json['iconName']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      position: serializer.fromJson<double>(json['position']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      createdByDeviceId: serializer.fromJson<String?>(
        json['createdByDeviceId'],
      ),
      updatedByDeviceId: serializer.fromJson<String?>(
        json['updatedByDeviceId'],
      ),
      lastCommandId: serializer.fromJson<String?>(json['lastCommandId']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'iconName': serializer.toJson<String>(iconName),
      'colorValue': serializer.toJson<int>(colorValue),
      'position': serializer.toJson<double>(position),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'createdByDeviceId': serializer.toJson<String?>(createdByDeviceId),
      'updatedByDeviceId': serializer.toJson<String?>(updatedByDeviceId),
      'lastCommandId': serializer.toJson<String?>(lastCommandId),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalDomain copyWith({
    String? id,
    String? userId,
    String? name,
    String? iconName,
    int? colorValue,
    double? position,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> createdByDeviceId = const Value.absent(),
    Value<String?> updatedByDeviceId = const Value.absent(),
    Value<String?> lastCommandId = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalDomain(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    iconName: iconName ?? this.iconName,
    colorValue: colorValue ?? this.colorValue,
    position: position ?? this.position,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdByDeviceId: createdByDeviceId.present
        ? createdByDeviceId.value
        : this.createdByDeviceId,
    updatedByDeviceId: updatedByDeviceId.present
        ? updatedByDeviceId.value
        : this.updatedByDeviceId,
    lastCommandId: lastCommandId.present
        ? lastCommandId.value
        : this.lastCommandId,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalDomain copyWithCompanion(LocalDomainsCompanion data) {
    return LocalDomain(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      iconName: data.iconName.present ? data.iconName.value : this.iconName,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      position: data.position.present ? data.position.value : this.position,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdByDeviceId: data.createdByDeviceId.present
          ? data.createdByDeviceId.value
          : this.createdByDeviceId,
      updatedByDeviceId: data.updatedByDeviceId.present
          ? data.updatedByDeviceId.value
          : this.updatedByDeviceId,
      lastCommandId: data.lastCommandId.present
          ? data.lastCommandId.value
          : this.lastCommandId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalDomain(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('iconName: $iconName, ')
          ..write('colorValue: $colorValue, ')
          ..write('position: $position, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdByDeviceId: $createdByDeviceId, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    iconName,
    colorValue,
    position,
    archivedAt,
    revision,
    createdAt,
    updatedAt,
    createdByDeviceId,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDomain &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.iconName == this.iconName &&
          other.colorValue == this.colorValue &&
          other.position == this.position &&
          other.archivedAt == this.archivedAt &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.createdByDeviceId == this.createdByDeviceId &&
          other.updatedByDeviceId == this.updatedByDeviceId &&
          other.lastCommandId == this.lastCommandId &&
          other.deletedAt == this.deletedAt);
}

class LocalDomainsCompanion extends UpdateCompanion<LocalDomain> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> iconName;
  final Value<int> colorValue;
  final Value<double> position;
  final Value<DateTime?> archivedAt;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> createdByDeviceId;
  final Value<String?> updatedByDeviceId;
  final Value<String?> lastCommandId;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalDomainsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.iconName = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.position = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdByDeviceId = const Value.absent(),
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalDomainsCompanion.insert({
    required String id,
    required String userId,
    required String name,
    this.iconName = const Value.absent(),
    required int colorValue,
    this.position = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.createdByDeviceId = const Value.absent(),
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       colorValue = Value(colorValue),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalDomain> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? iconName,
    Expression<int>? colorValue,
    Expression<double>? position,
    Expression<DateTime>? archivedAt,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? createdByDeviceId,
    Expression<String>? updatedByDeviceId,
    Expression<String>? lastCommandId,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (iconName != null) 'icon_name': iconName,
      if (colorValue != null) 'color_value': colorValue,
      if (position != null) 'position': position,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdByDeviceId != null) 'created_by_device_id': createdByDeviceId,
      if (updatedByDeviceId != null) 'updated_by_device_id': updatedByDeviceId,
      if (lastCommandId != null) 'last_command_id': lastCommandId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalDomainsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<String>? iconName,
    Value<int>? colorValue,
    Value<double>? position,
    Value<DateTime?>? archivedAt,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? createdByDeviceId,
    Value<String?>? updatedByDeviceId,
    Value<String?>? lastCommandId,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalDomainsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      colorValue: colorValue ?? this.colorValue,
      position: position ?? this.position,
      archivedAt: archivedAt ?? this.archivedAt,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByDeviceId: createdByDeviceId ?? this.createdByDeviceId,
      updatedByDeviceId: updatedByDeviceId ?? this.updatedByDeviceId,
      lastCommandId: lastCommandId ?? this.lastCommandId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (iconName.present) {
      map['icon_name'] = Variable<String>(iconName.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (position.present) {
      map['position'] = Variable<double>(position.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (createdByDeviceId.present) {
      map['created_by_device_id'] = Variable<String>(createdByDeviceId.value);
    }
    if (updatedByDeviceId.present) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId.value);
    }
    if (lastCommandId.present) {
      map['last_command_id'] = Variable<String>(lastCommandId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalDomainsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('iconName: $iconName, ')
          ..write('colorValue: $colorValue, ')
          ..write('position: $position, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdByDeviceId: $createdByDeviceId, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTasksTable extends LocalTasks
    with TableInfo<$LocalTasksTable, LocalTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _domainIdMeta = const VerificationMeta(
    'domainId',
  );
  @override
  late final GeneratedColumn<String> domainId = GeneratedColumn<String>(
    'domain_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ready'),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _executionModeMeta = const VerificationMeta(
    'executionMode',
  );
  @override
  late final GeneratedColumn<String> executionMode = GeneratedColumn<String>(
    'execution_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _scheduledDateMeta = const VerificationMeta(
    'scheduledDate',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledDate =
      GeneratedColumn<DateTime>(
        'scheduled_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _plannedStartMeta = const VerificationMeta(
    'plannedStart',
  );
  @override
  late final GeneratedColumn<DateTime> plannedStart = GeneratedColumn<DateTime>(
    'planned_start',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedEndMeta = const VerificationMeta(
    'plannedEnd',
  );
  @override
  late final GeneratedColumn<DateTime> plannedEnd = GeneratedColumn<DateTime>(
    'planned_end',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<DateTime> dueAt = GeneratedColumn<DateTime>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedDurationMsMeta =
      const VerificationMeta('estimatedDurationMs');
  @override
  late final GeneratedColumn<int> estimatedDurationMs = GeneratedColumn<int>(
    'estimated_duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _actualStartMeta = const VerificationMeta(
    'actualStart',
  );
  @override
  late final GeneratedColumn<DateTime> actualStart = GeneratedColumn<DateTime>(
    'actual_start',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualFinishMeta = const VerificationMeta(
    'actualFinish',
  );
  @override
  late final GeneratedColumn<DateTime> actualFinish = GeneratedColumn<DateTime>(
    'actual_finish',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeDurationMsMeta = const VerificationMeta(
    'activeDurationMs',
  );
  @override
  late final GeneratedColumn<int> activeDurationMs = GeneratedColumn<int>(
    'active_duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pausedDurationMsMeta = const VerificationMeta(
    'pausedDurationMs',
  );
  @override
  late final GeneratedColumn<int> pausedDurationMs = GeneratedColumn<int>(
    'paused_duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _idleDurationMsMeta = const VerificationMeta(
    'idleDurationMs',
  );
  @override
  late final GeneratedColumn<int> idleDurationMs = GeneratedColumn<int>(
    'idle_duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _roadmapIdMeta = const VerificationMeta(
    'roadmapId',
  );
  @override
  late final GeneratedColumn<String> roadmapId = GeneratedColumn<String>(
    'roadmap_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roadmapPhaseIdMeta = const VerificationMeta(
    'roadmapPhaseId',
  );
  @override
  late final GeneratedColumn<String> roadmapPhaseId = GeneratedColumn<String>(
    'roadmap_phase_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurrenceKeyMeta = const VerificationMeta(
    'occurrenceKey',
  );
  @override
  late final GeneratedColumn<String> occurrenceKey = GeneratedColumn<String>(
    'occurrence_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdByDeviceIdMeta = const VerificationMeta(
    'createdByDeviceId',
  );
  @override
  late final GeneratedColumn<String> createdByDeviceId =
      GeneratedColumn<String>(
        'created_by_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedByDeviceIdMeta = const VerificationMeta(
    'updatedByDeviceId',
  );
  @override
  late final GeneratedColumn<String> updatedByDeviceId =
      GeneratedColumn<String>(
        'updated_by_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCommandIdMeta = const VerificationMeta(
    'lastCommandId',
  );
  @override
  late final GeneratedColumn<String> lastCommandId = GeneratedColumn<String>(
    'last_command_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    templateId,
    title,
    description,
    domainId,
    status,
    priority,
    executionMode,
    scheduledDate,
    plannedStart,
    plannedEnd,
    dueAt,
    estimatedDurationMs,
    actualStart,
    actualFinish,
    activeDurationMs,
    pausedDurationMs,
    idleDurationMs,
    progress,
    roadmapId,
    roadmapPhaseId,
    occurrenceKey,
    dataJson,
    revision,
    createdAt,
    updatedAt,
    createdByDeviceId,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('domain_id')) {
      context.handle(
        _domainIdMeta,
        domainId.isAcceptableOrUnknown(data['domain_id']!, _domainIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('execution_mode')) {
      context.handle(
        _executionModeMeta,
        executionMode.isAcceptableOrUnknown(
          data['execution_mode']!,
          _executionModeMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_date')) {
      context.handle(
        _scheduledDateMeta,
        scheduledDate.isAcceptableOrUnknown(
          data['scheduled_date']!,
          _scheduledDateMeta,
        ),
      );
    }
    if (data.containsKey('planned_start')) {
      context.handle(
        _plannedStartMeta,
        plannedStart.isAcceptableOrUnknown(
          data['planned_start']!,
          _plannedStartMeta,
        ),
      );
    }
    if (data.containsKey('planned_end')) {
      context.handle(
        _plannedEndMeta,
        plannedEnd.isAcceptableOrUnknown(data['planned_end']!, _plannedEndMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('estimated_duration_ms')) {
      context.handle(
        _estimatedDurationMsMeta,
        estimatedDurationMs.isAcceptableOrUnknown(
          data['estimated_duration_ms']!,
          _estimatedDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('actual_start')) {
      context.handle(
        _actualStartMeta,
        actualStart.isAcceptableOrUnknown(
          data['actual_start']!,
          _actualStartMeta,
        ),
      );
    }
    if (data.containsKey('actual_finish')) {
      context.handle(
        _actualFinishMeta,
        actualFinish.isAcceptableOrUnknown(
          data['actual_finish']!,
          _actualFinishMeta,
        ),
      );
    }
    if (data.containsKey('active_duration_ms')) {
      context.handle(
        _activeDurationMsMeta,
        activeDurationMs.isAcceptableOrUnknown(
          data['active_duration_ms']!,
          _activeDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('paused_duration_ms')) {
      context.handle(
        _pausedDurationMsMeta,
        pausedDurationMs.isAcceptableOrUnknown(
          data['paused_duration_ms']!,
          _pausedDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('idle_duration_ms')) {
      context.handle(
        _idleDurationMsMeta,
        idleDurationMs.isAcceptableOrUnknown(
          data['idle_duration_ms']!,
          _idleDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('roadmap_id')) {
      context.handle(
        _roadmapIdMeta,
        roadmapId.isAcceptableOrUnknown(data['roadmap_id']!, _roadmapIdMeta),
      );
    }
    if (data.containsKey('roadmap_phase_id')) {
      context.handle(
        _roadmapPhaseIdMeta,
        roadmapPhaseId.isAcceptableOrUnknown(
          data['roadmap_phase_id']!,
          _roadmapPhaseIdMeta,
        ),
      );
    }
    if (data.containsKey('occurrence_key')) {
      context.handle(
        _occurrenceKeyMeta,
        occurrenceKey.isAcceptableOrUnknown(
          data['occurrence_key']!,
          _occurrenceKeyMeta,
        ),
      );
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('created_by_device_id')) {
      context.handle(
        _createdByDeviceIdMeta,
        createdByDeviceId.isAcceptableOrUnknown(
          data['created_by_device_id']!,
          _createdByDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('updated_by_device_id')) {
      context.handle(
        _updatedByDeviceIdMeta,
        updatedByDeviceId.isAcceptableOrUnknown(
          data['updated_by_device_id']!,
          _updatedByDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('last_command_id')) {
      context.handle(
        _lastCommandIdMeta,
        lastCommandId.isAcceptableOrUnknown(
          data['last_command_id']!,
          _lastCommandIdMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTask(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      domainId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domain_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      executionMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}execution_mode'],
      )!,
      scheduledDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_date'],
      ),
      plannedStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}planned_start'],
      ),
      plannedEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}planned_end'],
      ),
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_at'],
      ),
      estimatedDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_duration_ms'],
      )!,
      actualStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actual_start'],
      ),
      actualFinish: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actual_finish'],
      ),
      activeDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}active_duration_ms'],
      )!,
      pausedDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paused_duration_ms'],
      )!,
      idleDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}idle_duration_ms'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      roadmapId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}roadmap_id'],
      ),
      roadmapPhaseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}roadmap_phase_id'],
      ),
      occurrenceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrence_key'],
      ),
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      createdByDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_device_id'],
      ),
      updatedByDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device_id'],
      ),
      lastCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_command_id'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalTasksTable createAlias(String alias) {
    return $LocalTasksTable(attachedDatabase, alias);
  }
}

class LocalTask extends DataClass implements Insertable<LocalTask> {
  final String id;
  final String userId;
  final String? templateId;
  final String title;
  final String description;
  final String? domainId;
  final String status;
  final int priority;
  final String executionMode;
  final DateTime? scheduledDate;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DateTime? dueAt;
  final int estimatedDurationMs;
  final DateTime? actualStart;
  final DateTime? actualFinish;
  final int activeDurationMs;
  final int pausedDurationMs;
  final int idleDurationMs;
  final double progress;
  final String? roadmapId;
  final String? roadmapPhaseId;
  final String? occurrenceKey;
  final String dataJson;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByDeviceId;
  final String? updatedByDeviceId;
  final String? lastCommandId;
  final DateTime? deletedAt;
  const LocalTask({
    required this.id,
    required this.userId,
    this.templateId,
    required this.title,
    required this.description,
    this.domainId,
    required this.status,
    required this.priority,
    required this.executionMode,
    this.scheduledDate,
    this.plannedStart,
    this.plannedEnd,
    this.dueAt,
    required this.estimatedDurationMs,
    this.actualStart,
    this.actualFinish,
    required this.activeDurationMs,
    required this.pausedDurationMs,
    required this.idleDurationMs,
    required this.progress,
    this.roadmapId,
    this.roadmapPhaseId,
    this.occurrenceKey,
    required this.dataJson,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.createdByDeviceId,
    this.updatedByDeviceId,
    this.lastCommandId,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || templateId != null) {
      map['template_id'] = Variable<String>(templateId);
    }
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || domainId != null) {
      map['domain_id'] = Variable<String>(domainId);
    }
    map['status'] = Variable<String>(status);
    map['priority'] = Variable<int>(priority);
    map['execution_mode'] = Variable<String>(executionMode);
    if (!nullToAbsent || scheduledDate != null) {
      map['scheduled_date'] = Variable<DateTime>(scheduledDate);
    }
    if (!nullToAbsent || plannedStart != null) {
      map['planned_start'] = Variable<DateTime>(plannedStart);
    }
    if (!nullToAbsent || plannedEnd != null) {
      map['planned_end'] = Variable<DateTime>(plannedEnd);
    }
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<DateTime>(dueAt);
    }
    map['estimated_duration_ms'] = Variable<int>(estimatedDurationMs);
    if (!nullToAbsent || actualStart != null) {
      map['actual_start'] = Variable<DateTime>(actualStart);
    }
    if (!nullToAbsent || actualFinish != null) {
      map['actual_finish'] = Variable<DateTime>(actualFinish);
    }
    map['active_duration_ms'] = Variable<int>(activeDurationMs);
    map['paused_duration_ms'] = Variable<int>(pausedDurationMs);
    map['idle_duration_ms'] = Variable<int>(idleDurationMs);
    map['progress'] = Variable<double>(progress);
    if (!nullToAbsent || roadmapId != null) {
      map['roadmap_id'] = Variable<String>(roadmapId);
    }
    if (!nullToAbsent || roadmapPhaseId != null) {
      map['roadmap_phase_id'] = Variable<String>(roadmapPhaseId);
    }
    if (!nullToAbsent || occurrenceKey != null) {
      map['occurrence_key'] = Variable<String>(occurrenceKey);
    }
    map['data_json'] = Variable<String>(dataJson);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || createdByDeviceId != null) {
      map['created_by_device_id'] = Variable<String>(createdByDeviceId);
    }
    if (!nullToAbsent || updatedByDeviceId != null) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId);
    }
    if (!nullToAbsent || lastCommandId != null) {
      map['last_command_id'] = Variable<String>(lastCommandId);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalTasksCompanion toCompanion(bool nullToAbsent) {
    return LocalTasksCompanion(
      id: Value(id),
      userId: Value(userId),
      templateId: templateId == null && nullToAbsent
          ? const Value.absent()
          : Value(templateId),
      title: Value(title),
      description: Value(description),
      domainId: domainId == null && nullToAbsent
          ? const Value.absent()
          : Value(domainId),
      status: Value(status),
      priority: Value(priority),
      executionMode: Value(executionMode),
      scheduledDate: scheduledDate == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledDate),
      plannedStart: plannedStart == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedStart),
      plannedEnd: plannedEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedEnd),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      estimatedDurationMs: Value(estimatedDurationMs),
      actualStart: actualStart == null && nullToAbsent
          ? const Value.absent()
          : Value(actualStart),
      actualFinish: actualFinish == null && nullToAbsent
          ? const Value.absent()
          : Value(actualFinish),
      activeDurationMs: Value(activeDurationMs),
      pausedDurationMs: Value(pausedDurationMs),
      idleDurationMs: Value(idleDurationMs),
      progress: Value(progress),
      roadmapId: roadmapId == null && nullToAbsent
          ? const Value.absent()
          : Value(roadmapId),
      roadmapPhaseId: roadmapPhaseId == null && nullToAbsent
          ? const Value.absent()
          : Value(roadmapPhaseId),
      occurrenceKey: occurrenceKey == null && nullToAbsent
          ? const Value.absent()
          : Value(occurrenceKey),
      dataJson: Value(dataJson),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      createdByDeviceId: createdByDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(createdByDeviceId),
      updatedByDeviceId: updatedByDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedByDeviceId),
      lastCommandId: lastCommandId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommandId),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTask(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      templateId: serializer.fromJson<String?>(json['templateId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      domainId: serializer.fromJson<String?>(json['domainId']),
      status: serializer.fromJson<String>(json['status']),
      priority: serializer.fromJson<int>(json['priority']),
      executionMode: serializer.fromJson<String>(json['executionMode']),
      scheduledDate: serializer.fromJson<DateTime?>(json['scheduledDate']),
      plannedStart: serializer.fromJson<DateTime?>(json['plannedStart']),
      plannedEnd: serializer.fromJson<DateTime?>(json['plannedEnd']),
      dueAt: serializer.fromJson<DateTime?>(json['dueAt']),
      estimatedDurationMs: serializer.fromJson<int>(
        json['estimatedDurationMs'],
      ),
      actualStart: serializer.fromJson<DateTime?>(json['actualStart']),
      actualFinish: serializer.fromJson<DateTime?>(json['actualFinish']),
      activeDurationMs: serializer.fromJson<int>(json['activeDurationMs']),
      pausedDurationMs: serializer.fromJson<int>(json['pausedDurationMs']),
      idleDurationMs: serializer.fromJson<int>(json['idleDurationMs']),
      progress: serializer.fromJson<double>(json['progress']),
      roadmapId: serializer.fromJson<String?>(json['roadmapId']),
      roadmapPhaseId: serializer.fromJson<String?>(json['roadmapPhaseId']),
      occurrenceKey: serializer.fromJson<String?>(json['occurrenceKey']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      createdByDeviceId: serializer.fromJson<String?>(
        json['createdByDeviceId'],
      ),
      updatedByDeviceId: serializer.fromJson<String?>(
        json['updatedByDeviceId'],
      ),
      lastCommandId: serializer.fromJson<String?>(json['lastCommandId']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'templateId': serializer.toJson<String?>(templateId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'domainId': serializer.toJson<String?>(domainId),
      'status': serializer.toJson<String>(status),
      'priority': serializer.toJson<int>(priority),
      'executionMode': serializer.toJson<String>(executionMode),
      'scheduledDate': serializer.toJson<DateTime?>(scheduledDate),
      'plannedStart': serializer.toJson<DateTime?>(plannedStart),
      'plannedEnd': serializer.toJson<DateTime?>(plannedEnd),
      'dueAt': serializer.toJson<DateTime?>(dueAt),
      'estimatedDurationMs': serializer.toJson<int>(estimatedDurationMs),
      'actualStart': serializer.toJson<DateTime?>(actualStart),
      'actualFinish': serializer.toJson<DateTime?>(actualFinish),
      'activeDurationMs': serializer.toJson<int>(activeDurationMs),
      'pausedDurationMs': serializer.toJson<int>(pausedDurationMs),
      'idleDurationMs': serializer.toJson<int>(idleDurationMs),
      'progress': serializer.toJson<double>(progress),
      'roadmapId': serializer.toJson<String?>(roadmapId),
      'roadmapPhaseId': serializer.toJson<String?>(roadmapPhaseId),
      'occurrenceKey': serializer.toJson<String?>(occurrenceKey),
      'dataJson': serializer.toJson<String>(dataJson),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'createdByDeviceId': serializer.toJson<String?>(createdByDeviceId),
      'updatedByDeviceId': serializer.toJson<String?>(updatedByDeviceId),
      'lastCommandId': serializer.toJson<String?>(lastCommandId),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalTask copyWith({
    String? id,
    String? userId,
    Value<String?> templateId = const Value.absent(),
    String? title,
    String? description,
    Value<String?> domainId = const Value.absent(),
    String? status,
    int? priority,
    String? executionMode,
    Value<DateTime?> scheduledDate = const Value.absent(),
    Value<DateTime?> plannedStart = const Value.absent(),
    Value<DateTime?> plannedEnd = const Value.absent(),
    Value<DateTime?> dueAt = const Value.absent(),
    int? estimatedDurationMs,
    Value<DateTime?> actualStart = const Value.absent(),
    Value<DateTime?> actualFinish = const Value.absent(),
    int? activeDurationMs,
    int? pausedDurationMs,
    int? idleDurationMs,
    double? progress,
    Value<String?> roadmapId = const Value.absent(),
    Value<String?> roadmapPhaseId = const Value.absent(),
    Value<String?> occurrenceKey = const Value.absent(),
    String? dataJson,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> createdByDeviceId = const Value.absent(),
    Value<String?> updatedByDeviceId = const Value.absent(),
    Value<String?> lastCommandId = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalTask(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    templateId: templateId.present ? templateId.value : this.templateId,
    title: title ?? this.title,
    description: description ?? this.description,
    domainId: domainId.present ? domainId.value : this.domainId,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    executionMode: executionMode ?? this.executionMode,
    scheduledDate: scheduledDate.present
        ? scheduledDate.value
        : this.scheduledDate,
    plannedStart: plannedStart.present ? plannedStart.value : this.plannedStart,
    plannedEnd: plannedEnd.present ? plannedEnd.value : this.plannedEnd,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    estimatedDurationMs: estimatedDurationMs ?? this.estimatedDurationMs,
    actualStart: actualStart.present ? actualStart.value : this.actualStart,
    actualFinish: actualFinish.present ? actualFinish.value : this.actualFinish,
    activeDurationMs: activeDurationMs ?? this.activeDurationMs,
    pausedDurationMs: pausedDurationMs ?? this.pausedDurationMs,
    idleDurationMs: idleDurationMs ?? this.idleDurationMs,
    progress: progress ?? this.progress,
    roadmapId: roadmapId.present ? roadmapId.value : this.roadmapId,
    roadmapPhaseId: roadmapPhaseId.present
        ? roadmapPhaseId.value
        : this.roadmapPhaseId,
    occurrenceKey: occurrenceKey.present
        ? occurrenceKey.value
        : this.occurrenceKey,
    dataJson: dataJson ?? this.dataJson,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdByDeviceId: createdByDeviceId.present
        ? createdByDeviceId.value
        : this.createdByDeviceId,
    updatedByDeviceId: updatedByDeviceId.present
        ? updatedByDeviceId.value
        : this.updatedByDeviceId,
    lastCommandId: lastCommandId.present
        ? lastCommandId.value
        : this.lastCommandId,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalTask copyWithCompanion(LocalTasksCompanion data) {
    return LocalTask(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      domainId: data.domainId.present ? data.domainId.value : this.domainId,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      executionMode: data.executionMode.present
          ? data.executionMode.value
          : this.executionMode,
      scheduledDate: data.scheduledDate.present
          ? data.scheduledDate.value
          : this.scheduledDate,
      plannedStart: data.plannedStart.present
          ? data.plannedStart.value
          : this.plannedStart,
      plannedEnd: data.plannedEnd.present
          ? data.plannedEnd.value
          : this.plannedEnd,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      estimatedDurationMs: data.estimatedDurationMs.present
          ? data.estimatedDurationMs.value
          : this.estimatedDurationMs,
      actualStart: data.actualStart.present
          ? data.actualStart.value
          : this.actualStart,
      actualFinish: data.actualFinish.present
          ? data.actualFinish.value
          : this.actualFinish,
      activeDurationMs: data.activeDurationMs.present
          ? data.activeDurationMs.value
          : this.activeDurationMs,
      pausedDurationMs: data.pausedDurationMs.present
          ? data.pausedDurationMs.value
          : this.pausedDurationMs,
      idleDurationMs: data.idleDurationMs.present
          ? data.idleDurationMs.value
          : this.idleDurationMs,
      progress: data.progress.present ? data.progress.value : this.progress,
      roadmapId: data.roadmapId.present ? data.roadmapId.value : this.roadmapId,
      roadmapPhaseId: data.roadmapPhaseId.present
          ? data.roadmapPhaseId.value
          : this.roadmapPhaseId,
      occurrenceKey: data.occurrenceKey.present
          ? data.occurrenceKey.value
          : this.occurrenceKey,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdByDeviceId: data.createdByDeviceId.present
          ? data.createdByDeviceId.value
          : this.createdByDeviceId,
      updatedByDeviceId: data.updatedByDeviceId.present
          ? data.updatedByDeviceId.value
          : this.updatedByDeviceId,
      lastCommandId: data.lastCommandId.present
          ? data.lastCommandId.value
          : this.lastCommandId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTask(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('templateId: $templateId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('domainId: $domainId, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('executionMode: $executionMode, ')
          ..write('scheduledDate: $scheduledDate, ')
          ..write('plannedStart: $plannedStart, ')
          ..write('plannedEnd: $plannedEnd, ')
          ..write('dueAt: $dueAt, ')
          ..write('estimatedDurationMs: $estimatedDurationMs, ')
          ..write('actualStart: $actualStart, ')
          ..write('actualFinish: $actualFinish, ')
          ..write('activeDurationMs: $activeDurationMs, ')
          ..write('pausedDurationMs: $pausedDurationMs, ')
          ..write('idleDurationMs: $idleDurationMs, ')
          ..write('progress: $progress, ')
          ..write('roadmapId: $roadmapId, ')
          ..write('roadmapPhaseId: $roadmapPhaseId, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('dataJson: $dataJson, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdByDeviceId: $createdByDeviceId, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    userId,
    templateId,
    title,
    description,
    domainId,
    status,
    priority,
    executionMode,
    scheduledDate,
    plannedStart,
    plannedEnd,
    dueAt,
    estimatedDurationMs,
    actualStart,
    actualFinish,
    activeDurationMs,
    pausedDurationMs,
    idleDurationMs,
    progress,
    roadmapId,
    roadmapPhaseId,
    occurrenceKey,
    dataJson,
    revision,
    createdAt,
    updatedAt,
    createdByDeviceId,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTask &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.templateId == this.templateId &&
          other.title == this.title &&
          other.description == this.description &&
          other.domainId == this.domainId &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.executionMode == this.executionMode &&
          other.scheduledDate == this.scheduledDate &&
          other.plannedStart == this.plannedStart &&
          other.plannedEnd == this.plannedEnd &&
          other.dueAt == this.dueAt &&
          other.estimatedDurationMs == this.estimatedDurationMs &&
          other.actualStart == this.actualStart &&
          other.actualFinish == this.actualFinish &&
          other.activeDurationMs == this.activeDurationMs &&
          other.pausedDurationMs == this.pausedDurationMs &&
          other.idleDurationMs == this.idleDurationMs &&
          other.progress == this.progress &&
          other.roadmapId == this.roadmapId &&
          other.roadmapPhaseId == this.roadmapPhaseId &&
          other.occurrenceKey == this.occurrenceKey &&
          other.dataJson == this.dataJson &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.createdByDeviceId == this.createdByDeviceId &&
          other.updatedByDeviceId == this.updatedByDeviceId &&
          other.lastCommandId == this.lastCommandId &&
          other.deletedAt == this.deletedAt);
}

class LocalTasksCompanion extends UpdateCompanion<LocalTask> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String?> templateId;
  final Value<String> title;
  final Value<String> description;
  final Value<String?> domainId;
  final Value<String> status;
  final Value<int> priority;
  final Value<String> executionMode;
  final Value<DateTime?> scheduledDate;
  final Value<DateTime?> plannedStart;
  final Value<DateTime?> plannedEnd;
  final Value<DateTime?> dueAt;
  final Value<int> estimatedDurationMs;
  final Value<DateTime?> actualStart;
  final Value<DateTime?> actualFinish;
  final Value<int> activeDurationMs;
  final Value<int> pausedDurationMs;
  final Value<int> idleDurationMs;
  final Value<double> progress;
  final Value<String?> roadmapId;
  final Value<String?> roadmapPhaseId;
  final Value<String?> occurrenceKey;
  final Value<String> dataJson;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> createdByDeviceId;
  final Value<String?> updatedByDeviceId;
  final Value<String?> lastCommandId;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalTasksCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.templateId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.domainId = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.executionMode = const Value.absent(),
    this.scheduledDate = const Value.absent(),
    this.plannedStart = const Value.absent(),
    this.plannedEnd = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.estimatedDurationMs = const Value.absent(),
    this.actualStart = const Value.absent(),
    this.actualFinish = const Value.absent(),
    this.activeDurationMs = const Value.absent(),
    this.pausedDurationMs = const Value.absent(),
    this.idleDurationMs = const Value.absent(),
    this.progress = const Value.absent(),
    this.roadmapId = const Value.absent(),
    this.roadmapPhaseId = const Value.absent(),
    this.occurrenceKey = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdByDeviceId = const Value.absent(),
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTasksCompanion.insert({
    required String id,
    required String userId,
    this.templateId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.domainId = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.executionMode = const Value.absent(),
    this.scheduledDate = const Value.absent(),
    this.plannedStart = const Value.absent(),
    this.plannedEnd = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.estimatedDurationMs = const Value.absent(),
    this.actualStart = const Value.absent(),
    this.actualFinish = const Value.absent(),
    this.activeDurationMs = const Value.absent(),
    this.pausedDurationMs = const Value.absent(),
    this.idleDurationMs = const Value.absent(),
    this.progress = const Value.absent(),
    this.roadmapId = const Value.absent(),
    this.roadmapPhaseId = const Value.absent(),
    this.occurrenceKey = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.createdByDeviceId = const Value.absent(),
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalTask> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? templateId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? domainId,
    Expression<String>? status,
    Expression<int>? priority,
    Expression<String>? executionMode,
    Expression<DateTime>? scheduledDate,
    Expression<DateTime>? plannedStart,
    Expression<DateTime>? plannedEnd,
    Expression<DateTime>? dueAt,
    Expression<int>? estimatedDurationMs,
    Expression<DateTime>? actualStart,
    Expression<DateTime>? actualFinish,
    Expression<int>? activeDurationMs,
    Expression<int>? pausedDurationMs,
    Expression<int>? idleDurationMs,
    Expression<double>? progress,
    Expression<String>? roadmapId,
    Expression<String>? roadmapPhaseId,
    Expression<String>? occurrenceKey,
    Expression<String>? dataJson,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? createdByDeviceId,
    Expression<String>? updatedByDeviceId,
    Expression<String>? lastCommandId,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (templateId != null) 'template_id': templateId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (domainId != null) 'domain_id': domainId,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (executionMode != null) 'execution_mode': executionMode,
      if (scheduledDate != null) 'scheduled_date': scheduledDate,
      if (plannedStart != null) 'planned_start': plannedStart,
      if (plannedEnd != null) 'planned_end': plannedEnd,
      if (dueAt != null) 'due_at': dueAt,
      if (estimatedDurationMs != null)
        'estimated_duration_ms': estimatedDurationMs,
      if (actualStart != null) 'actual_start': actualStart,
      if (actualFinish != null) 'actual_finish': actualFinish,
      if (activeDurationMs != null) 'active_duration_ms': activeDurationMs,
      if (pausedDurationMs != null) 'paused_duration_ms': pausedDurationMs,
      if (idleDurationMs != null) 'idle_duration_ms': idleDurationMs,
      if (progress != null) 'progress': progress,
      if (roadmapId != null) 'roadmap_id': roadmapId,
      if (roadmapPhaseId != null) 'roadmap_phase_id': roadmapPhaseId,
      if (occurrenceKey != null) 'occurrence_key': occurrenceKey,
      if (dataJson != null) 'data_json': dataJson,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdByDeviceId != null) 'created_by_device_id': createdByDeviceId,
      if (updatedByDeviceId != null) 'updated_by_device_id': updatedByDeviceId,
      if (lastCommandId != null) 'last_command_id': lastCommandId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String?>? templateId,
    Value<String>? title,
    Value<String>? description,
    Value<String?>? domainId,
    Value<String>? status,
    Value<int>? priority,
    Value<String>? executionMode,
    Value<DateTime?>? scheduledDate,
    Value<DateTime?>? plannedStart,
    Value<DateTime?>? plannedEnd,
    Value<DateTime?>? dueAt,
    Value<int>? estimatedDurationMs,
    Value<DateTime?>? actualStart,
    Value<DateTime?>? actualFinish,
    Value<int>? activeDurationMs,
    Value<int>? pausedDurationMs,
    Value<int>? idleDurationMs,
    Value<double>? progress,
    Value<String?>? roadmapId,
    Value<String?>? roadmapPhaseId,
    Value<String?>? occurrenceKey,
    Value<String>? dataJson,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? createdByDeviceId,
    Value<String?>? updatedByDeviceId,
    Value<String?>? lastCommandId,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalTasksCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      templateId: templateId ?? this.templateId,
      title: title ?? this.title,
      description: description ?? this.description,
      domainId: domainId ?? this.domainId,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      executionMode: executionMode ?? this.executionMode,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      plannedStart: plannedStart ?? this.plannedStart,
      plannedEnd: plannedEnd ?? this.plannedEnd,
      dueAt: dueAt ?? this.dueAt,
      estimatedDurationMs: estimatedDurationMs ?? this.estimatedDurationMs,
      actualStart: actualStart ?? this.actualStart,
      actualFinish: actualFinish ?? this.actualFinish,
      activeDurationMs: activeDurationMs ?? this.activeDurationMs,
      pausedDurationMs: pausedDurationMs ?? this.pausedDurationMs,
      idleDurationMs: idleDurationMs ?? this.idleDurationMs,
      progress: progress ?? this.progress,
      roadmapId: roadmapId ?? this.roadmapId,
      roadmapPhaseId: roadmapPhaseId ?? this.roadmapPhaseId,
      occurrenceKey: occurrenceKey ?? this.occurrenceKey,
      dataJson: dataJson ?? this.dataJson,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByDeviceId: createdByDeviceId ?? this.createdByDeviceId,
      updatedByDeviceId: updatedByDeviceId ?? this.updatedByDeviceId,
      lastCommandId: lastCommandId ?? this.lastCommandId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (domainId.present) {
      map['domain_id'] = Variable<String>(domainId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (executionMode.present) {
      map['execution_mode'] = Variable<String>(executionMode.value);
    }
    if (scheduledDate.present) {
      map['scheduled_date'] = Variable<DateTime>(scheduledDate.value);
    }
    if (plannedStart.present) {
      map['planned_start'] = Variable<DateTime>(plannedStart.value);
    }
    if (plannedEnd.present) {
      map['planned_end'] = Variable<DateTime>(plannedEnd.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<DateTime>(dueAt.value);
    }
    if (estimatedDurationMs.present) {
      map['estimated_duration_ms'] = Variable<int>(estimatedDurationMs.value);
    }
    if (actualStart.present) {
      map['actual_start'] = Variable<DateTime>(actualStart.value);
    }
    if (actualFinish.present) {
      map['actual_finish'] = Variable<DateTime>(actualFinish.value);
    }
    if (activeDurationMs.present) {
      map['active_duration_ms'] = Variable<int>(activeDurationMs.value);
    }
    if (pausedDurationMs.present) {
      map['paused_duration_ms'] = Variable<int>(pausedDurationMs.value);
    }
    if (idleDurationMs.present) {
      map['idle_duration_ms'] = Variable<int>(idleDurationMs.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (roadmapId.present) {
      map['roadmap_id'] = Variable<String>(roadmapId.value);
    }
    if (roadmapPhaseId.present) {
      map['roadmap_phase_id'] = Variable<String>(roadmapPhaseId.value);
    }
    if (occurrenceKey.present) {
      map['occurrence_key'] = Variable<String>(occurrenceKey.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (createdByDeviceId.present) {
      map['created_by_device_id'] = Variable<String>(createdByDeviceId.value);
    }
    if (updatedByDeviceId.present) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId.value);
    }
    if (lastCommandId.present) {
      map['last_command_id'] = Variable<String>(lastCommandId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTasksCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('templateId: $templateId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('domainId: $domainId, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('executionMode: $executionMode, ')
          ..write('scheduledDate: $scheduledDate, ')
          ..write('plannedStart: $plannedStart, ')
          ..write('plannedEnd: $plannedEnd, ')
          ..write('dueAt: $dueAt, ')
          ..write('estimatedDurationMs: $estimatedDurationMs, ')
          ..write('actualStart: $actualStart, ')
          ..write('actualFinish: $actualFinish, ')
          ..write('activeDurationMs: $activeDurationMs, ')
          ..write('pausedDurationMs: $pausedDurationMs, ')
          ..write('idleDurationMs: $idleDurationMs, ')
          ..write('progress: $progress, ')
          ..write('roadmapId: $roadmapId, ')
          ..write('roadmapPhaseId: $roadmapPhaseId, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('dataJson: $dataJson, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdByDeviceId: $createdByDeviceId, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalRuntimeStatesTable extends LocalRuntimeStates
    with TableInfo<$LocalRuntimeStatesTable, LocalRuntime> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRuntimeStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeTaskIdMeta = const VerificationMeta(
    'activeTaskId',
  );
  @override
  late final GeneratedColumn<String> activeTaskId = GeneratedColumn<String>(
    'active_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('idle'),
  );
  static const VerificationMeta _segmentStartedAtMeta = const VerificationMeta(
    'segmentStartedAt',
  );
  @override
  late final GeneratedColumn<DateTime> segmentStartedAt =
      GeneratedColumn<DateTime>(
        'segment_started_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _accumulatedActiveMsMeta =
      const VerificationMeta('accumulatedActiveMs');
  @override
  late final GeneratedColumn<int> accumulatedActiveMs = GeneratedColumn<int>(
    'accumulated_active_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _accumulatedPausedMsMeta =
      const VerificationMeta('accumulatedPausedMs');
  @override
  late final GeneratedColumn<int> accumulatedPausedMs = GeneratedColumn<int>(
    'accumulated_paused_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastCommandIdMeta = const VerificationMeta(
    'lastCommandId',
  );
  @override
  late final GeneratedColumn<String> lastCommandId = GeneratedColumn<String>(
    'last_command_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    activeTaskId,
    sessionId,
    state,
    segmentStartedAt,
    accumulatedActiveMs,
    accumulatedPausedMs,
    dataJson,
    revision,
    updatedAt,
    lastCommandId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_runtime_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalRuntime> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('active_task_id')) {
      context.handle(
        _activeTaskIdMeta,
        activeTaskId.isAcceptableOrUnknown(
          data['active_task_id']!,
          _activeTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('segment_started_at')) {
      context.handle(
        _segmentStartedAtMeta,
        segmentStartedAt.isAcceptableOrUnknown(
          data['segment_started_at']!,
          _segmentStartedAtMeta,
        ),
      );
    }
    if (data.containsKey('accumulated_active_ms')) {
      context.handle(
        _accumulatedActiveMsMeta,
        accumulatedActiveMs.isAcceptableOrUnknown(
          data['accumulated_active_ms']!,
          _accumulatedActiveMsMeta,
        ),
      );
    }
    if (data.containsKey('accumulated_paused_ms')) {
      context.handle(
        _accumulatedPausedMsMeta,
        accumulatedPausedMs.isAcceptableOrUnknown(
          data['accumulated_paused_ms']!,
          _accumulatedPausedMsMeta,
        ),
      );
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('last_command_id')) {
      context.handle(
        _lastCommandIdMeta,
        lastCommandId.isAcceptableOrUnknown(
          data['last_command_id']!,
          _lastCommandIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalRuntime map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRuntime(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      activeTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_task_id'],
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      segmentStartedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}segment_started_at'],
      ),
      accumulatedActiveMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accumulated_active_ms'],
      )!,
      accumulatedPausedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accumulated_paused_ms'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_command_id'],
      ),
    );
  }

  @override
  $LocalRuntimeStatesTable createAlias(String alias) {
    return $LocalRuntimeStatesTable(attachedDatabase, alias);
  }
}

class LocalRuntime extends DataClass implements Insertable<LocalRuntime> {
  final String id;
  final String userId;
  final String? activeTaskId;
  final String? sessionId;
  final String state;
  final DateTime? segmentStartedAt;
  final int accumulatedActiveMs;
  final int accumulatedPausedMs;

  /// Canonical interval metadata which is not part of the lifetime task total.
  /// Pomodoro uses this to keep each focus interval independent while the
  /// accumulated active duration continues to grow for reports.
  final String dataJson;
  final int revision;
  final DateTime updatedAt;
  final String? lastCommandId;
  const LocalRuntime({
    required this.id,
    required this.userId,
    this.activeTaskId,
    this.sessionId,
    required this.state,
    this.segmentStartedAt,
    required this.accumulatedActiveMs,
    required this.accumulatedPausedMs,
    required this.dataJson,
    required this.revision,
    required this.updatedAt,
    this.lastCommandId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || activeTaskId != null) {
      map['active_task_id'] = Variable<String>(activeTaskId);
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || segmentStartedAt != null) {
      map['segment_started_at'] = Variable<DateTime>(segmentStartedAt);
    }
    map['accumulated_active_ms'] = Variable<int>(accumulatedActiveMs);
    map['accumulated_paused_ms'] = Variable<int>(accumulatedPausedMs);
    map['data_json'] = Variable<String>(dataJson);
    map['revision'] = Variable<int>(revision);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || lastCommandId != null) {
      map['last_command_id'] = Variable<String>(lastCommandId);
    }
    return map;
  }

  LocalRuntimeStatesCompanion toCompanion(bool nullToAbsent) {
    return LocalRuntimeStatesCompanion(
      id: Value(id),
      userId: Value(userId),
      activeTaskId: activeTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(activeTaskId),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      state: Value(state),
      segmentStartedAt: segmentStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(segmentStartedAt),
      accumulatedActiveMs: Value(accumulatedActiveMs),
      accumulatedPausedMs: Value(accumulatedPausedMs),
      dataJson: Value(dataJson),
      revision: Value(revision),
      updatedAt: Value(updatedAt),
      lastCommandId: lastCommandId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommandId),
    );
  }

  factory LocalRuntime.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRuntime(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      activeTaskId: serializer.fromJson<String?>(json['activeTaskId']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      state: serializer.fromJson<String>(json['state']),
      segmentStartedAt: serializer.fromJson<DateTime?>(
        json['segmentStartedAt'],
      ),
      accumulatedActiveMs: serializer.fromJson<int>(
        json['accumulatedActiveMs'],
      ),
      accumulatedPausedMs: serializer.fromJson<int>(
        json['accumulatedPausedMs'],
      ),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      revision: serializer.fromJson<int>(json['revision']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastCommandId: serializer.fromJson<String?>(json['lastCommandId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'activeTaskId': serializer.toJson<String?>(activeTaskId),
      'sessionId': serializer.toJson<String?>(sessionId),
      'state': serializer.toJson<String>(state),
      'segmentStartedAt': serializer.toJson<DateTime?>(segmentStartedAt),
      'accumulatedActiveMs': serializer.toJson<int>(accumulatedActiveMs),
      'accumulatedPausedMs': serializer.toJson<int>(accumulatedPausedMs),
      'dataJson': serializer.toJson<String>(dataJson),
      'revision': serializer.toJson<int>(revision),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastCommandId': serializer.toJson<String?>(lastCommandId),
    };
  }

  LocalRuntime copyWith({
    String? id,
    String? userId,
    Value<String?> activeTaskId = const Value.absent(),
    Value<String?> sessionId = const Value.absent(),
    String? state,
    Value<DateTime?> segmentStartedAt = const Value.absent(),
    int? accumulatedActiveMs,
    int? accumulatedPausedMs,
    String? dataJson,
    int? revision,
    DateTime? updatedAt,
    Value<String?> lastCommandId = const Value.absent(),
  }) => LocalRuntime(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    activeTaskId: activeTaskId.present ? activeTaskId.value : this.activeTaskId,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    state: state ?? this.state,
    segmentStartedAt: segmentStartedAt.present
        ? segmentStartedAt.value
        : this.segmentStartedAt,
    accumulatedActiveMs: accumulatedActiveMs ?? this.accumulatedActiveMs,
    accumulatedPausedMs: accumulatedPausedMs ?? this.accumulatedPausedMs,
    dataJson: dataJson ?? this.dataJson,
    revision: revision ?? this.revision,
    updatedAt: updatedAt ?? this.updatedAt,
    lastCommandId: lastCommandId.present
        ? lastCommandId.value
        : this.lastCommandId,
  );
  LocalRuntime copyWithCompanion(LocalRuntimeStatesCompanion data) {
    return LocalRuntime(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      activeTaskId: data.activeTaskId.present
          ? data.activeTaskId.value
          : this.activeTaskId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      state: data.state.present ? data.state.value : this.state,
      segmentStartedAt: data.segmentStartedAt.present
          ? data.segmentStartedAt.value
          : this.segmentStartedAt,
      accumulatedActiveMs: data.accumulatedActiveMs.present
          ? data.accumulatedActiveMs.value
          : this.accumulatedActiveMs,
      accumulatedPausedMs: data.accumulatedPausedMs.present
          ? data.accumulatedPausedMs.value
          : this.accumulatedPausedMs,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      revision: data.revision.present ? data.revision.value : this.revision,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastCommandId: data.lastCommandId.present
          ? data.lastCommandId.value
          : this.lastCommandId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRuntime(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('activeTaskId: $activeTaskId, ')
          ..write('sessionId: $sessionId, ')
          ..write('state: $state, ')
          ..write('segmentStartedAt: $segmentStartedAt, ')
          ..write('accumulatedActiveMs: $accumulatedActiveMs, ')
          ..write('accumulatedPausedMs: $accumulatedPausedMs, ')
          ..write('dataJson: $dataJson, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastCommandId: $lastCommandId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    activeTaskId,
    sessionId,
    state,
    segmentStartedAt,
    accumulatedActiveMs,
    accumulatedPausedMs,
    dataJson,
    revision,
    updatedAt,
    lastCommandId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRuntime &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.activeTaskId == this.activeTaskId &&
          other.sessionId == this.sessionId &&
          other.state == this.state &&
          other.segmentStartedAt == this.segmentStartedAt &&
          other.accumulatedActiveMs == this.accumulatedActiveMs &&
          other.accumulatedPausedMs == this.accumulatedPausedMs &&
          other.dataJson == this.dataJson &&
          other.revision == this.revision &&
          other.updatedAt == this.updatedAt &&
          other.lastCommandId == this.lastCommandId);
}

class LocalRuntimeStatesCompanion extends UpdateCompanion<LocalRuntime> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String?> activeTaskId;
  final Value<String?> sessionId;
  final Value<String> state;
  final Value<DateTime?> segmentStartedAt;
  final Value<int> accumulatedActiveMs;
  final Value<int> accumulatedPausedMs;
  final Value<String> dataJson;
  final Value<int> revision;
  final Value<DateTime> updatedAt;
  final Value<String?> lastCommandId;
  final Value<int> rowid;
  const LocalRuntimeStatesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.activeTaskId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.state = const Value.absent(),
    this.segmentStartedAt = const Value.absent(),
    this.accumulatedActiveMs = const Value.absent(),
    this.accumulatedPausedMs = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.revision = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRuntimeStatesCompanion.insert({
    required String id,
    required String userId,
    this.activeTaskId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.state = const Value.absent(),
    this.segmentStartedAt = const Value.absent(),
    this.accumulatedActiveMs = const Value.absent(),
    this.accumulatedPausedMs = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime updatedAt,
    this.lastCommandId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       updatedAt = Value(updatedAt);
  static Insertable<LocalRuntime> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? activeTaskId,
    Expression<String>? sessionId,
    Expression<String>? state,
    Expression<DateTime>? segmentStartedAt,
    Expression<int>? accumulatedActiveMs,
    Expression<int>? accumulatedPausedMs,
    Expression<String>? dataJson,
    Expression<int>? revision,
    Expression<DateTime>? updatedAt,
    Expression<String>? lastCommandId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (activeTaskId != null) 'active_task_id': activeTaskId,
      if (sessionId != null) 'session_id': sessionId,
      if (state != null) 'state': state,
      if (segmentStartedAt != null) 'segment_started_at': segmentStartedAt,
      if (accumulatedActiveMs != null)
        'accumulated_active_ms': accumulatedActiveMs,
      if (accumulatedPausedMs != null)
        'accumulated_paused_ms': accumulatedPausedMs,
      if (dataJson != null) 'data_json': dataJson,
      if (revision != null) 'revision': revision,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastCommandId != null) 'last_command_id': lastCommandId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRuntimeStatesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String?>? activeTaskId,
    Value<String?>? sessionId,
    Value<String>? state,
    Value<DateTime?>? segmentStartedAt,
    Value<int>? accumulatedActiveMs,
    Value<int>? accumulatedPausedMs,
    Value<String>? dataJson,
    Value<int>? revision,
    Value<DateTime>? updatedAt,
    Value<String?>? lastCommandId,
    Value<int>? rowid,
  }) {
    return LocalRuntimeStatesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      activeTaskId: activeTaskId ?? this.activeTaskId,
      sessionId: sessionId ?? this.sessionId,
      state: state ?? this.state,
      segmentStartedAt: segmentStartedAt ?? this.segmentStartedAt,
      accumulatedActiveMs: accumulatedActiveMs ?? this.accumulatedActiveMs,
      accumulatedPausedMs: accumulatedPausedMs ?? this.accumulatedPausedMs,
      dataJson: dataJson ?? this.dataJson,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      lastCommandId: lastCommandId ?? this.lastCommandId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (activeTaskId.present) {
      map['active_task_id'] = Variable<String>(activeTaskId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (segmentStartedAt.present) {
      map['segment_started_at'] = Variable<DateTime>(segmentStartedAt.value);
    }
    if (accumulatedActiveMs.present) {
      map['accumulated_active_ms'] = Variable<int>(accumulatedActiveMs.value);
    }
    if (accumulatedPausedMs.present) {
      map['accumulated_paused_ms'] = Variable<int>(accumulatedPausedMs.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastCommandId.present) {
      map['last_command_id'] = Variable<String>(lastCommandId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRuntimeStatesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('activeTaskId: $activeTaskId, ')
          ..write('sessionId: $sessionId, ')
          ..write('state: $state, ')
          ..write('segmentStartedAt: $segmentStartedAt, ')
          ..write('accumulatedActiveMs: $accumulatedActiveMs, ')
          ..write('accumulatedPausedMs: $accumulatedPausedMs, ')
          ..write('dataJson: $dataJson, ')
          ..write('revision: $revision, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalRoadmapsTable extends LocalRoadmaps
    with TableInfo<$LocalRoadmapsTable, LocalRoadmap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRoadmapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _plannedStartMeta = const VerificationMeta(
    'plannedStart',
  );
  @override
  late final GeneratedColumn<DateTime> plannedStart = GeneratedColumn<DateTime>(
    'planned_start',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originalTargetDateMeta =
      const VerificationMeta('originalTargetDate');
  @override
  late final GeneratedColumn<DateTime> originalTargetDate =
      GeneratedColumn<DateTime>(
        'original_target_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _forecastTargetDateMeta =
      const VerificationMeta('forecastTargetDate');
  @override
  late final GeneratedColumn<DateTime> forecastTargetDate =
      GeneratedColumn<DateTime>(
        'forecast_target_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _finalOutcomeMeta = const VerificationMeta(
    'finalOutcome',
  );
  @override
  late final GeneratedColumn<String> finalOutcome = GeneratedColumn<String>(
    'final_outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _requiredEffortMsMeta = const VerificationMeta(
    'requiredEffortMs',
  );
  @override
  late final GeneratedColumn<int> requiredEffortMs = GeneratedColumn<int>(
    'required_effort_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedEffortMsMeta = const VerificationMeta(
    'completedEffortMs',
  );
  @override
  late final GeneratedColumn<int> completedEffortMs = GeneratedColumn<int>(
    'completed_effort_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _riskLevelMeta = const VerificationMeta(
    'riskLevel',
  );
  @override
  late final GeneratedColumn<String> riskLevel = GeneratedColumn<String>(
    'risk_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('low'),
  );
  static const VerificationMeta _forecastConfidenceMeta =
      const VerificationMeta('forecastConfidence');
  @override
  late final GeneratedColumn<String> forecastConfidence =
      GeneratedColumn<String>(
        'forecast_confidence',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('low'),
      );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedByDeviceIdMeta = const VerificationMeta(
    'updatedByDeviceId',
  );
  @override
  late final GeneratedColumn<String> updatedByDeviceId =
      GeneratedColumn<String>(
        'updated_by_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCommandIdMeta = const VerificationMeta(
    'lastCommandId',
  );
  @override
  late final GeneratedColumn<String> lastCommandId = GeneratedColumn<String>(
    'last_command_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    title,
    description,
    status,
    plannedStart,
    originalTargetDate,
    forecastTargetDate,
    finalOutcome,
    progress,
    requiredEffortMs,
    completedEffortMs,
    riskLevel,
    forecastConfidence,
    revision,
    createdAt,
    updatedAt,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_roadmaps';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalRoadmap> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('planned_start')) {
      context.handle(
        _plannedStartMeta,
        plannedStart.isAcceptableOrUnknown(
          data['planned_start']!,
          _plannedStartMeta,
        ),
      );
    }
    if (data.containsKey('original_target_date')) {
      context.handle(
        _originalTargetDateMeta,
        originalTargetDate.isAcceptableOrUnknown(
          data['original_target_date']!,
          _originalTargetDateMeta,
        ),
      );
    }
    if (data.containsKey('forecast_target_date')) {
      context.handle(
        _forecastTargetDateMeta,
        forecastTargetDate.isAcceptableOrUnknown(
          data['forecast_target_date']!,
          _forecastTargetDateMeta,
        ),
      );
    }
    if (data.containsKey('final_outcome')) {
      context.handle(
        _finalOutcomeMeta,
        finalOutcome.isAcceptableOrUnknown(
          data['final_outcome']!,
          _finalOutcomeMeta,
        ),
      );
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('required_effort_ms')) {
      context.handle(
        _requiredEffortMsMeta,
        requiredEffortMs.isAcceptableOrUnknown(
          data['required_effort_ms']!,
          _requiredEffortMsMeta,
        ),
      );
    }
    if (data.containsKey('completed_effort_ms')) {
      context.handle(
        _completedEffortMsMeta,
        completedEffortMs.isAcceptableOrUnknown(
          data['completed_effort_ms']!,
          _completedEffortMsMeta,
        ),
      );
    }
    if (data.containsKey('risk_level')) {
      context.handle(
        _riskLevelMeta,
        riskLevel.isAcceptableOrUnknown(data['risk_level']!, _riskLevelMeta),
      );
    }
    if (data.containsKey('forecast_confidence')) {
      context.handle(
        _forecastConfidenceMeta,
        forecastConfidence.isAcceptableOrUnknown(
          data['forecast_confidence']!,
          _forecastConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('updated_by_device_id')) {
      context.handle(
        _updatedByDeviceIdMeta,
        updatedByDeviceId.isAcceptableOrUnknown(
          data['updated_by_device_id']!,
          _updatedByDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('last_command_id')) {
      context.handle(
        _lastCommandIdMeta,
        lastCommandId.isAcceptableOrUnknown(
          data['last_command_id']!,
          _lastCommandIdMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalRoadmap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRoadmap(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      plannedStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}planned_start'],
      ),
      originalTargetDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}original_target_date'],
      ),
      forecastTargetDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}forecast_target_date'],
      ),
      finalOutcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}final_outcome'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      requiredEffortMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}required_effort_ms'],
      ),
      completedEffortMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_effort_ms'],
      )!,
      riskLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}risk_level'],
      )!,
      forecastConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}forecast_confidence'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      updatedByDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device_id'],
      ),
      lastCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_command_id'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalRoadmapsTable createAlias(String alias) {
    return $LocalRoadmapsTable(attachedDatabase, alias);
  }
}

class LocalRoadmap extends DataClass implements Insertable<LocalRoadmap> {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String status;
  final DateTime? plannedStart;
  final DateTime? originalTargetDate;
  final DateTime? forecastTargetDate;
  final String finalOutcome;
  final double progress;
  final int? requiredEffortMs;
  final int completedEffortMs;
  final String riskLevel;
  final String forecastConfidence;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? updatedByDeviceId;
  final String? lastCommandId;
  final DateTime? deletedAt;
  const LocalRoadmap({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.status,
    this.plannedStart,
    this.originalTargetDate,
    this.forecastTargetDate,
    required this.finalOutcome,
    required this.progress,
    this.requiredEffortMs,
    required this.completedEffortMs,
    required this.riskLevel,
    required this.forecastConfidence,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.updatedByDeviceId,
    this.lastCommandId,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || plannedStart != null) {
      map['planned_start'] = Variable<DateTime>(plannedStart);
    }
    if (!nullToAbsent || originalTargetDate != null) {
      map['original_target_date'] = Variable<DateTime>(originalTargetDate);
    }
    if (!nullToAbsent || forecastTargetDate != null) {
      map['forecast_target_date'] = Variable<DateTime>(forecastTargetDate);
    }
    map['final_outcome'] = Variable<String>(finalOutcome);
    map['progress'] = Variable<double>(progress);
    if (!nullToAbsent || requiredEffortMs != null) {
      map['required_effort_ms'] = Variable<int>(requiredEffortMs);
    }
    map['completed_effort_ms'] = Variable<int>(completedEffortMs);
    map['risk_level'] = Variable<String>(riskLevel);
    map['forecast_confidence'] = Variable<String>(forecastConfidence);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || updatedByDeviceId != null) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId);
    }
    if (!nullToAbsent || lastCommandId != null) {
      map['last_command_id'] = Variable<String>(lastCommandId);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalRoadmapsCompanion toCompanion(bool nullToAbsent) {
    return LocalRoadmapsCompanion(
      id: Value(id),
      userId: Value(userId),
      title: Value(title),
      description: Value(description),
      status: Value(status),
      plannedStart: plannedStart == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedStart),
      originalTargetDate: originalTargetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(originalTargetDate),
      forecastTargetDate: forecastTargetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(forecastTargetDate),
      finalOutcome: Value(finalOutcome),
      progress: Value(progress),
      requiredEffortMs: requiredEffortMs == null && nullToAbsent
          ? const Value.absent()
          : Value(requiredEffortMs),
      completedEffortMs: Value(completedEffortMs),
      riskLevel: Value(riskLevel),
      forecastConfidence: Value(forecastConfidence),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      updatedByDeviceId: updatedByDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedByDeviceId),
      lastCommandId: lastCommandId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommandId),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalRoadmap.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRoadmap(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      plannedStart: serializer.fromJson<DateTime?>(json['plannedStart']),
      originalTargetDate: serializer.fromJson<DateTime?>(
        json['originalTargetDate'],
      ),
      forecastTargetDate: serializer.fromJson<DateTime?>(
        json['forecastTargetDate'],
      ),
      finalOutcome: serializer.fromJson<String>(json['finalOutcome']),
      progress: serializer.fromJson<double>(json['progress']),
      requiredEffortMs: serializer.fromJson<int?>(json['requiredEffortMs']),
      completedEffortMs: serializer.fromJson<int>(json['completedEffortMs']),
      riskLevel: serializer.fromJson<String>(json['riskLevel']),
      forecastConfidence: serializer.fromJson<String>(
        json['forecastConfidence'],
      ),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      updatedByDeviceId: serializer.fromJson<String?>(
        json['updatedByDeviceId'],
      ),
      lastCommandId: serializer.fromJson<String?>(json['lastCommandId']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'status': serializer.toJson<String>(status),
      'plannedStart': serializer.toJson<DateTime?>(plannedStart),
      'originalTargetDate': serializer.toJson<DateTime?>(originalTargetDate),
      'forecastTargetDate': serializer.toJson<DateTime?>(forecastTargetDate),
      'finalOutcome': serializer.toJson<String>(finalOutcome),
      'progress': serializer.toJson<double>(progress),
      'requiredEffortMs': serializer.toJson<int?>(requiredEffortMs),
      'completedEffortMs': serializer.toJson<int>(completedEffortMs),
      'riskLevel': serializer.toJson<String>(riskLevel),
      'forecastConfidence': serializer.toJson<String>(forecastConfidence),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'updatedByDeviceId': serializer.toJson<String?>(updatedByDeviceId),
      'lastCommandId': serializer.toJson<String?>(lastCommandId),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalRoadmap copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? status,
    Value<DateTime?> plannedStart = const Value.absent(),
    Value<DateTime?> originalTargetDate = const Value.absent(),
    Value<DateTime?> forecastTargetDate = const Value.absent(),
    String? finalOutcome,
    double? progress,
    Value<int?> requiredEffortMs = const Value.absent(),
    int? completedEffortMs,
    String? riskLevel,
    String? forecastConfidence,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> updatedByDeviceId = const Value.absent(),
    Value<String?> lastCommandId = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalRoadmap(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    plannedStart: plannedStart.present ? plannedStart.value : this.plannedStart,
    originalTargetDate: originalTargetDate.present
        ? originalTargetDate.value
        : this.originalTargetDate,
    forecastTargetDate: forecastTargetDate.present
        ? forecastTargetDate.value
        : this.forecastTargetDate,
    finalOutcome: finalOutcome ?? this.finalOutcome,
    progress: progress ?? this.progress,
    requiredEffortMs: requiredEffortMs.present
        ? requiredEffortMs.value
        : this.requiredEffortMs,
    completedEffortMs: completedEffortMs ?? this.completedEffortMs,
    riskLevel: riskLevel ?? this.riskLevel,
    forecastConfidence: forecastConfidence ?? this.forecastConfidence,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedByDeviceId: updatedByDeviceId.present
        ? updatedByDeviceId.value
        : this.updatedByDeviceId,
    lastCommandId: lastCommandId.present
        ? lastCommandId.value
        : this.lastCommandId,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalRoadmap copyWithCompanion(LocalRoadmapsCompanion data) {
    return LocalRoadmap(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      status: data.status.present ? data.status.value : this.status,
      plannedStart: data.plannedStart.present
          ? data.plannedStart.value
          : this.plannedStart,
      originalTargetDate: data.originalTargetDate.present
          ? data.originalTargetDate.value
          : this.originalTargetDate,
      forecastTargetDate: data.forecastTargetDate.present
          ? data.forecastTargetDate.value
          : this.forecastTargetDate,
      finalOutcome: data.finalOutcome.present
          ? data.finalOutcome.value
          : this.finalOutcome,
      progress: data.progress.present ? data.progress.value : this.progress,
      requiredEffortMs: data.requiredEffortMs.present
          ? data.requiredEffortMs.value
          : this.requiredEffortMs,
      completedEffortMs: data.completedEffortMs.present
          ? data.completedEffortMs.value
          : this.completedEffortMs,
      riskLevel: data.riskLevel.present ? data.riskLevel.value : this.riskLevel,
      forecastConfidence: data.forecastConfidence.present
          ? data.forecastConfidence.value
          : this.forecastConfidence,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      updatedByDeviceId: data.updatedByDeviceId.present
          ? data.updatedByDeviceId.value
          : this.updatedByDeviceId,
      lastCommandId: data.lastCommandId.present
          ? data.lastCommandId.value
          : this.lastCommandId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRoadmap(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('plannedStart: $plannedStart, ')
          ..write('originalTargetDate: $originalTargetDate, ')
          ..write('forecastTargetDate: $forecastTargetDate, ')
          ..write('finalOutcome: $finalOutcome, ')
          ..write('progress: $progress, ')
          ..write('requiredEffortMs: $requiredEffortMs, ')
          ..write('completedEffortMs: $completedEffortMs, ')
          ..write('riskLevel: $riskLevel, ')
          ..write('forecastConfidence: $forecastConfidence, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    title,
    description,
    status,
    plannedStart,
    originalTargetDate,
    forecastTargetDate,
    finalOutcome,
    progress,
    requiredEffortMs,
    completedEffortMs,
    riskLevel,
    forecastConfidence,
    revision,
    createdAt,
    updatedAt,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRoadmap &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.plannedStart == this.plannedStart &&
          other.originalTargetDate == this.originalTargetDate &&
          other.forecastTargetDate == this.forecastTargetDate &&
          other.finalOutcome == this.finalOutcome &&
          other.progress == this.progress &&
          other.requiredEffortMs == this.requiredEffortMs &&
          other.completedEffortMs == this.completedEffortMs &&
          other.riskLevel == this.riskLevel &&
          other.forecastConfidence == this.forecastConfidence &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.updatedByDeviceId == this.updatedByDeviceId &&
          other.lastCommandId == this.lastCommandId &&
          other.deletedAt == this.deletedAt);
}

class LocalRoadmapsCompanion extends UpdateCompanion<LocalRoadmap> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> title;
  final Value<String> description;
  final Value<String> status;
  final Value<DateTime?> plannedStart;
  final Value<DateTime?> originalTargetDate;
  final Value<DateTime?> forecastTargetDate;
  final Value<String> finalOutcome;
  final Value<double> progress;
  final Value<int?> requiredEffortMs;
  final Value<int> completedEffortMs;
  final Value<String> riskLevel;
  final Value<String> forecastConfidence;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> updatedByDeviceId;
  final Value<String?> lastCommandId;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalRoadmapsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.plannedStart = const Value.absent(),
    this.originalTargetDate = const Value.absent(),
    this.forecastTargetDate = const Value.absent(),
    this.finalOutcome = const Value.absent(),
    this.progress = const Value.absent(),
    this.requiredEffortMs = const Value.absent(),
    this.completedEffortMs = const Value.absent(),
    this.riskLevel = const Value.absent(),
    this.forecastConfidence = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalRoadmapsCompanion.insert({
    required String id,
    required String userId,
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.plannedStart = const Value.absent(),
    this.originalTargetDate = const Value.absent(),
    this.forecastTargetDate = const Value.absent(),
    this.finalOutcome = const Value.absent(),
    this.progress = const Value.absent(),
    this.requiredEffortMs = const Value.absent(),
    this.completedEffortMs = const Value.absent(),
    this.riskLevel = const Value.absent(),
    this.forecastConfidence = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalRoadmap> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<DateTime>? plannedStart,
    Expression<DateTime>? originalTargetDate,
    Expression<DateTime>? forecastTargetDate,
    Expression<String>? finalOutcome,
    Expression<double>? progress,
    Expression<int>? requiredEffortMs,
    Expression<int>? completedEffortMs,
    Expression<String>? riskLevel,
    Expression<String>? forecastConfidence,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? updatedByDeviceId,
    Expression<String>? lastCommandId,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (plannedStart != null) 'planned_start': plannedStart,
      if (originalTargetDate != null)
        'original_target_date': originalTargetDate,
      if (forecastTargetDate != null)
        'forecast_target_date': forecastTargetDate,
      if (finalOutcome != null) 'final_outcome': finalOutcome,
      if (progress != null) 'progress': progress,
      if (requiredEffortMs != null) 'required_effort_ms': requiredEffortMs,
      if (completedEffortMs != null) 'completed_effort_ms': completedEffortMs,
      if (riskLevel != null) 'risk_level': riskLevel,
      if (forecastConfidence != null) 'forecast_confidence': forecastConfidence,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (updatedByDeviceId != null) 'updated_by_device_id': updatedByDeviceId,
      if (lastCommandId != null) 'last_command_id': lastCommandId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalRoadmapsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? title,
    Value<String>? description,
    Value<String>? status,
    Value<DateTime?>? plannedStart,
    Value<DateTime?>? originalTargetDate,
    Value<DateTime?>? forecastTargetDate,
    Value<String>? finalOutcome,
    Value<double>? progress,
    Value<int?>? requiredEffortMs,
    Value<int>? completedEffortMs,
    Value<String>? riskLevel,
    Value<String>? forecastConfidence,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? updatedByDeviceId,
    Value<String?>? lastCommandId,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalRoadmapsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      plannedStart: plannedStart ?? this.plannedStart,
      originalTargetDate: originalTargetDate ?? this.originalTargetDate,
      forecastTargetDate: forecastTargetDate ?? this.forecastTargetDate,
      finalOutcome: finalOutcome ?? this.finalOutcome,
      progress: progress ?? this.progress,
      requiredEffortMs: requiredEffortMs ?? this.requiredEffortMs,
      completedEffortMs: completedEffortMs ?? this.completedEffortMs,
      riskLevel: riskLevel ?? this.riskLevel,
      forecastConfidence: forecastConfidence ?? this.forecastConfidence,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDeviceId: updatedByDeviceId ?? this.updatedByDeviceId,
      lastCommandId: lastCommandId ?? this.lastCommandId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (plannedStart.present) {
      map['planned_start'] = Variable<DateTime>(plannedStart.value);
    }
    if (originalTargetDate.present) {
      map['original_target_date'] = Variable<DateTime>(
        originalTargetDate.value,
      );
    }
    if (forecastTargetDate.present) {
      map['forecast_target_date'] = Variable<DateTime>(
        forecastTargetDate.value,
      );
    }
    if (finalOutcome.present) {
      map['final_outcome'] = Variable<String>(finalOutcome.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (requiredEffortMs.present) {
      map['required_effort_ms'] = Variable<int>(requiredEffortMs.value);
    }
    if (completedEffortMs.present) {
      map['completed_effort_ms'] = Variable<int>(completedEffortMs.value);
    }
    if (riskLevel.present) {
      map['risk_level'] = Variable<String>(riskLevel.value);
    }
    if (forecastConfidence.present) {
      map['forecast_confidence'] = Variable<String>(forecastConfidence.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (updatedByDeviceId.present) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId.value);
    }
    if (lastCommandId.present) {
      map['last_command_id'] = Variable<String>(lastCommandId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRoadmapsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('plannedStart: $plannedStart, ')
          ..write('originalTargetDate: $originalTargetDate, ')
          ..write('forecastTargetDate: $forecastTargetDate, ')
          ..write('finalOutcome: $finalOutcome, ')
          ..write('progress: $progress, ')
          ..write('requiredEffortMs: $requiredEffortMs, ')
          ..write('completedEffortMs: $completedEffortMs, ')
          ..write('riskLevel: $riskLevel, ')
          ..write('forecastConfidence: $forecastConfidence, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalActivitySegmentsTable extends LocalActivitySegments
    with TableInfo<$LocalActivitySegmentsTable, LocalActivitySegment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalActivitySegmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceEventIdMeta = const VerificationMeta(
    'deviceEventId',
  );
  @override
  late final GeneratedColumn<String> deviceEventId = GeneratedColumn<String>(
    'device_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _processNameMeta = const VerificationMeta(
    'processName',
  );
  @override
  late final GeneratedColumn<String> processName = GeneratedColumn<String>(
    'process_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _windowTitleMeta = const VerificationMeta(
    'windowTitle',
  );
  @override
  late final GeneratedColumn<String> windowTitle = GeneratedColumn<String>(
    'window_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _domainMeta = const VerificationMeta('domain');
  @override
  late final GeneratedColumn<String> domain = GeneratedColumn<String>(
    'domain',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageTitleMeta = const VerificationMeta(
    'pageTitle',
  );
  @override
  late final GeneratedColumn<String> pageTitle = GeneratedColumn<String>(
    'page_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _idleStateMeta = const VerificationMeta(
    'idleState',
  );
  @override
  late final GeneratedColumn<String> idleState = GeneratedColumn<String>(
    'idle_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _captureConfidenceMeta = const VerificationMeta(
    'captureConfidence',
  );
  @override
  late final GeneratedColumn<double> captureConfidence =
      GeneratedColumn<double>(
        'capture_confidence',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _rawMetadataJsonMeta = const VerificationMeta(
    'rawMetadataJson',
  );
  @override
  late final GeneratedColumn<String> rawMetadataJson = GeneratedColumn<String>(
    'raw_metadata_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    deviceId,
    deviceEventId,
    startedAt,
    endedAt,
    sourceType,
    processName,
    windowTitle,
    domain,
    url,
    pageTitle,
    idleState,
    captureConfidence,
    rawMetadataJson,
    revision,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_activity_segments';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalActivitySegment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('device_event_id')) {
      context.handle(
        _deviceEventIdMeta,
        deviceEventId.isAcceptableOrUnknown(
          data['device_event_id']!,
          _deviceEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deviceEventIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endedAtMeta);
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('process_name')) {
      context.handle(
        _processNameMeta,
        processName.isAcceptableOrUnknown(
          data['process_name']!,
          _processNameMeta,
        ),
      );
    }
    if (data.containsKey('window_title')) {
      context.handle(
        _windowTitleMeta,
        windowTitle.isAcceptableOrUnknown(
          data['window_title']!,
          _windowTitleMeta,
        ),
      );
    }
    if (data.containsKey('domain')) {
      context.handle(
        _domainMeta,
        domain.isAcceptableOrUnknown(data['domain']!, _domainMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('page_title')) {
      context.handle(
        _pageTitleMeta,
        pageTitle.isAcceptableOrUnknown(data['page_title']!, _pageTitleMeta),
      );
    }
    if (data.containsKey('idle_state')) {
      context.handle(
        _idleStateMeta,
        idleState.isAcceptableOrUnknown(data['idle_state']!, _idleStateMeta),
      );
    }
    if (data.containsKey('capture_confidence')) {
      context.handle(
        _captureConfidenceMeta,
        captureConfidence.isAcceptableOrUnknown(
          data['capture_confidence']!,
          _captureConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('raw_metadata_json')) {
      context.handle(
        _rawMetadataJsonMeta,
        rawMetadataJson.isAcceptableOrUnknown(
          data['raw_metadata_json']!,
          _rawMetadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalActivitySegment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalActivitySegment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      deviceEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_event_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      )!,
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      )!,
      processName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}process_name'],
      ),
      windowTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}window_title'],
      ),
      domain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}domain'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      pageTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_title'],
      ),
      idleState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idle_state'],
      ),
      captureConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}capture_confidence'],
      ),
      rawMetadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_metadata_json'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalActivitySegmentsTable createAlias(String alias) {
    return $LocalActivitySegmentsTable(attachedDatabase, alias);
  }
}

class LocalActivitySegment extends DataClass
    implements Insertable<LocalActivitySegment> {
  final String id;
  final String userId;
  final String deviceId;
  final String deviceEventId;
  final DateTime startedAt;
  final DateTime endedAt;
  final String sourceType;
  final String? processName;
  final String? windowTitle;
  final String? domain;
  final String? url;
  final String? pageTitle;
  final String? idleState;
  final double? captureConfidence;
  final String rawMetadataJson;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const LocalActivitySegment({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.deviceEventId,
    required this.startedAt,
    required this.endedAt,
    required this.sourceType,
    this.processName,
    this.windowTitle,
    this.domain,
    this.url,
    this.pageTitle,
    this.idleState,
    this.captureConfidence,
    required this.rawMetadataJson,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['device_id'] = Variable<String>(deviceId);
    map['device_event_id'] = Variable<String>(deviceEventId);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['ended_at'] = Variable<DateTime>(endedAt);
    map['source_type'] = Variable<String>(sourceType);
    if (!nullToAbsent || processName != null) {
      map['process_name'] = Variable<String>(processName);
    }
    if (!nullToAbsent || windowTitle != null) {
      map['window_title'] = Variable<String>(windowTitle);
    }
    if (!nullToAbsent || domain != null) {
      map['domain'] = Variable<String>(domain);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || pageTitle != null) {
      map['page_title'] = Variable<String>(pageTitle);
    }
    if (!nullToAbsent || idleState != null) {
      map['idle_state'] = Variable<String>(idleState);
    }
    if (!nullToAbsent || captureConfidence != null) {
      map['capture_confidence'] = Variable<double>(captureConfidence);
    }
    map['raw_metadata_json'] = Variable<String>(rawMetadataJson);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalActivitySegmentsCompanion toCompanion(bool nullToAbsent) {
    return LocalActivitySegmentsCompanion(
      id: Value(id),
      userId: Value(userId),
      deviceId: Value(deviceId),
      deviceEventId: Value(deviceEventId),
      startedAt: Value(startedAt),
      endedAt: Value(endedAt),
      sourceType: Value(sourceType),
      processName: processName == null && nullToAbsent
          ? const Value.absent()
          : Value(processName),
      windowTitle: windowTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(windowTitle),
      domain: domain == null && nullToAbsent
          ? const Value.absent()
          : Value(domain),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      pageTitle: pageTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(pageTitle),
      idleState: idleState == null && nullToAbsent
          ? const Value.absent()
          : Value(idleState),
      captureConfidence: captureConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(captureConfidence),
      rawMetadataJson: Value(rawMetadataJson),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalActivitySegment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalActivitySegment(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deviceEventId: serializer.fromJson<String>(json['deviceEventId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime>(json['endedAt']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      processName: serializer.fromJson<String?>(json['processName']),
      windowTitle: serializer.fromJson<String?>(json['windowTitle']),
      domain: serializer.fromJson<String?>(json['domain']),
      url: serializer.fromJson<String?>(json['url']),
      pageTitle: serializer.fromJson<String?>(json['pageTitle']),
      idleState: serializer.fromJson<String?>(json['idleState']),
      captureConfidence: serializer.fromJson<double?>(
        json['captureConfidence'],
      ),
      rawMetadataJson: serializer.fromJson<String>(json['rawMetadataJson']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'deviceId': serializer.toJson<String>(deviceId),
      'deviceEventId': serializer.toJson<String>(deviceEventId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime>(endedAt),
      'sourceType': serializer.toJson<String>(sourceType),
      'processName': serializer.toJson<String?>(processName),
      'windowTitle': serializer.toJson<String?>(windowTitle),
      'domain': serializer.toJson<String?>(domain),
      'url': serializer.toJson<String?>(url),
      'pageTitle': serializer.toJson<String?>(pageTitle),
      'idleState': serializer.toJson<String?>(idleState),
      'captureConfidence': serializer.toJson<double?>(captureConfidence),
      'rawMetadataJson': serializer.toJson<String>(rawMetadataJson),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalActivitySegment copyWith({
    String? id,
    String? userId,
    String? deviceId,
    String? deviceEventId,
    DateTime? startedAt,
    DateTime? endedAt,
    String? sourceType,
    Value<String?> processName = const Value.absent(),
    Value<String?> windowTitle = const Value.absent(),
    Value<String?> domain = const Value.absent(),
    Value<String?> url = const Value.absent(),
    Value<String?> pageTitle = const Value.absent(),
    Value<String?> idleState = const Value.absent(),
    Value<double?> captureConfidence = const Value.absent(),
    String? rawMetadataJson,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalActivitySegment(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    deviceId: deviceId ?? this.deviceId,
    deviceEventId: deviceEventId ?? this.deviceEventId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    sourceType: sourceType ?? this.sourceType,
    processName: processName.present ? processName.value : this.processName,
    windowTitle: windowTitle.present ? windowTitle.value : this.windowTitle,
    domain: domain.present ? domain.value : this.domain,
    url: url.present ? url.value : this.url,
    pageTitle: pageTitle.present ? pageTitle.value : this.pageTitle,
    idleState: idleState.present ? idleState.value : this.idleState,
    captureConfidence: captureConfidence.present
        ? captureConfidence.value
        : this.captureConfidence,
    rawMetadataJson: rawMetadataJson ?? this.rawMetadataJson,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalActivitySegment copyWithCompanion(LocalActivitySegmentsCompanion data) {
    return LocalActivitySegment(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceEventId: data.deviceEventId.present
          ? data.deviceEventId.value
          : this.deviceEventId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      processName: data.processName.present
          ? data.processName.value
          : this.processName,
      windowTitle: data.windowTitle.present
          ? data.windowTitle.value
          : this.windowTitle,
      domain: data.domain.present ? data.domain.value : this.domain,
      url: data.url.present ? data.url.value : this.url,
      pageTitle: data.pageTitle.present ? data.pageTitle.value : this.pageTitle,
      idleState: data.idleState.present ? data.idleState.value : this.idleState,
      captureConfidence: data.captureConfidence.present
          ? data.captureConfidence.value
          : this.captureConfidence,
      rawMetadataJson: data.rawMetadataJson.present
          ? data.rawMetadataJson.value
          : this.rawMetadataJson,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalActivitySegment(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceEventId: $deviceEventId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('sourceType: $sourceType, ')
          ..write('processName: $processName, ')
          ..write('windowTitle: $windowTitle, ')
          ..write('domain: $domain, ')
          ..write('url: $url, ')
          ..write('pageTitle: $pageTitle, ')
          ..write('idleState: $idleState, ')
          ..write('captureConfidence: $captureConfidence, ')
          ..write('rawMetadataJson: $rawMetadataJson, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    deviceId,
    deviceEventId,
    startedAt,
    endedAt,
    sourceType,
    processName,
    windowTitle,
    domain,
    url,
    pageTitle,
    idleState,
    captureConfidence,
    rawMetadataJson,
    revision,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalActivitySegment &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.deviceId == this.deviceId &&
          other.deviceEventId == this.deviceEventId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.sourceType == this.sourceType &&
          other.processName == this.processName &&
          other.windowTitle == this.windowTitle &&
          other.domain == this.domain &&
          other.url == this.url &&
          other.pageTitle == this.pageTitle &&
          other.idleState == this.idleState &&
          other.captureConfidence == this.captureConfidence &&
          other.rawMetadataJson == this.rawMetadataJson &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class LocalActivitySegmentsCompanion
    extends UpdateCompanion<LocalActivitySegment> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> deviceId;
  final Value<String> deviceEventId;
  final Value<DateTime> startedAt;
  final Value<DateTime> endedAt;
  final Value<String> sourceType;
  final Value<String?> processName;
  final Value<String?> windowTitle;
  final Value<String?> domain;
  final Value<String?> url;
  final Value<String?> pageTitle;
  final Value<String?> idleState;
  final Value<double?> captureConfidence;
  final Value<String> rawMetadataJson;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalActivitySegmentsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceEventId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.processName = const Value.absent(),
    this.windowTitle = const Value.absent(),
    this.domain = const Value.absent(),
    this.url = const Value.absent(),
    this.pageTitle = const Value.absent(),
    this.idleState = const Value.absent(),
    this.captureConfidence = const Value.absent(),
    this.rawMetadataJson = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalActivitySegmentsCompanion.insert({
    required String id,
    required String userId,
    required String deviceId,
    required String deviceEventId,
    required DateTime startedAt,
    required DateTime endedAt,
    required String sourceType,
    this.processName = const Value.absent(),
    this.windowTitle = const Value.absent(),
    this.domain = const Value.absent(),
    this.url = const Value.absent(),
    this.pageTitle = const Value.absent(),
    this.idleState = const Value.absent(),
    this.captureConfidence = const Value.absent(),
    this.rawMetadataJson = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       deviceId = Value(deviceId),
       deviceEventId = Value(deviceEventId),
       startedAt = Value(startedAt),
       endedAt = Value(endedAt),
       sourceType = Value(sourceType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalActivitySegment> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? deviceId,
    Expression<String>? deviceEventId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<String>? sourceType,
    Expression<String>? processName,
    Expression<String>? windowTitle,
    Expression<String>? domain,
    Expression<String>? url,
    Expression<String>? pageTitle,
    Expression<String>? idleState,
    Expression<double>? captureConfidence,
    Expression<String>? rawMetadataJson,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceEventId != null) 'device_event_id': deviceEventId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (sourceType != null) 'source_type': sourceType,
      if (processName != null) 'process_name': processName,
      if (windowTitle != null) 'window_title': windowTitle,
      if (domain != null) 'domain': domain,
      if (url != null) 'url': url,
      if (pageTitle != null) 'page_title': pageTitle,
      if (idleState != null) 'idle_state': idleState,
      if (captureConfidence != null) 'capture_confidence': captureConfidence,
      if (rawMetadataJson != null) 'raw_metadata_json': rawMetadataJson,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalActivitySegmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? deviceId,
    Value<String>? deviceEventId,
    Value<DateTime>? startedAt,
    Value<DateTime>? endedAt,
    Value<String>? sourceType,
    Value<String?>? processName,
    Value<String?>? windowTitle,
    Value<String?>? domain,
    Value<String?>? url,
    Value<String?>? pageTitle,
    Value<String?>? idleState,
    Value<double?>? captureConfidence,
    Value<String>? rawMetadataJson,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalActivitySegmentsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      deviceEventId: deviceEventId ?? this.deviceEventId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      sourceType: sourceType ?? this.sourceType,
      processName: processName ?? this.processName,
      windowTitle: windowTitle ?? this.windowTitle,
      domain: domain ?? this.domain,
      url: url ?? this.url,
      pageTitle: pageTitle ?? this.pageTitle,
      idleState: idleState ?? this.idleState,
      captureConfidence: captureConfidence ?? this.captureConfidence,
      rawMetadataJson: rawMetadataJson ?? this.rawMetadataJson,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceEventId.present) {
      map['device_event_id'] = Variable<String>(deviceEventId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (processName.present) {
      map['process_name'] = Variable<String>(processName.value);
    }
    if (windowTitle.present) {
      map['window_title'] = Variable<String>(windowTitle.value);
    }
    if (domain.present) {
      map['domain'] = Variable<String>(domain.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (pageTitle.present) {
      map['page_title'] = Variable<String>(pageTitle.value);
    }
    if (idleState.present) {
      map['idle_state'] = Variable<String>(idleState.value);
    }
    if (captureConfidence.present) {
      map['capture_confidence'] = Variable<double>(captureConfidence.value);
    }
    if (rawMetadataJson.present) {
      map['raw_metadata_json'] = Variable<String>(rawMetadataJson.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalActivitySegmentsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceEventId: $deviceEventId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('sourceType: $sourceType, ')
          ..write('processName: $processName, ')
          ..write('windowTitle: $windowTitle, ')
          ..write('domain: $domain, ')
          ..write('url: $url, ')
          ..write('pageTitle: $pageTitle, ')
          ..write('idleState: $idleState, ')
          ..write('captureConfidence: $captureConfidence, ')
          ..write('rawMetadataJson: $rawMetadataJson, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalAttributionsTable extends LocalAttributions
    with TableInfo<$LocalAttributionsTable, LocalAttribution> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAttributionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activitySegmentIdMeta = const VerificationMeta(
    'activitySegmentId',
  );
  @override
  late final GeneratedColumn<String> activitySegmentId =
      GeneratedColumn<String>(
        'activity_segment_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _targetTypeMeta = const VerificationMeta(
    'targetType',
  );
  @override
  late final GeneratedColumn<String> targetType = GeneratedColumn<String>(
    'target_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classificationMeta = const VerificationMeta(
    'classification',
  );
  @override
  late final GeneratedColumn<String> classification = GeneratedColumn<String>(
    'classification',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attributionStatusMeta = const VerificationMeta(
    'attributionStatus',
  );
  @override
  late final GeneratedColumn<String> attributionStatus =
      GeneratedColumn<String>(
        'attribution_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('proposed'),
      );
  static const VerificationMeta _confirmedByUserMeta = const VerificationMeta(
    'confirmedByUser',
  );
  @override
  late final GeneratedColumn<bool> confirmedByUser = GeneratedColumn<bool>(
    'confirmed_by_user',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("confirmed_by_user" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    activitySegmentId,
    targetType,
    targetId,
    classification,
    confidence,
    attributionStatus,
    confirmedByUser,
    revision,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_attributions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAttribution> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('activity_segment_id')) {
      context.handle(
        _activitySegmentIdMeta,
        activitySegmentId.isAcceptableOrUnknown(
          data['activity_segment_id']!,
          _activitySegmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activitySegmentIdMeta);
    }
    if (data.containsKey('target_type')) {
      context.handle(
        _targetTypeMeta,
        targetType.isAcceptableOrUnknown(data['target_type']!, _targetTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_targetTypeMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    }
    if (data.containsKey('classification')) {
      context.handle(
        _classificationMeta,
        classification.isAcceptableOrUnknown(
          data['classification']!,
          _classificationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_classificationMeta);
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    if (data.containsKey('attribution_status')) {
      context.handle(
        _attributionStatusMeta,
        attributionStatus.isAcceptableOrUnknown(
          data['attribution_status']!,
          _attributionStatusMeta,
        ),
      );
    }
    if (data.containsKey('confirmed_by_user')) {
      context.handle(
        _confirmedByUserMeta,
        confirmedByUser.isAcceptableOrUnknown(
          data['confirmed_by_user']!,
          _confirmedByUserMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalAttribution map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAttribution(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      activitySegmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_segment_id'],
      )!,
      targetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_type'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      ),
      classification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classification'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      attributionStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attribution_status'],
      )!,
      confirmedByUser: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}confirmed_by_user'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalAttributionsTable createAlias(String alias) {
    return $LocalAttributionsTable(attachedDatabase, alias);
  }
}

class LocalAttribution extends DataClass
    implements Insertable<LocalAttribution> {
  final String id;
  final String userId;
  final String activitySegmentId;
  final String targetType;
  final String? targetId;
  final String classification;
  final double confidence;
  final String attributionStatus;
  final bool confirmedByUser;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const LocalAttribution({
    required this.id,
    required this.userId,
    required this.activitySegmentId,
    required this.targetType,
    this.targetId,
    required this.classification,
    required this.confidence,
    required this.attributionStatus,
    required this.confirmedByUser,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['activity_segment_id'] = Variable<String>(activitySegmentId);
    map['target_type'] = Variable<String>(targetType);
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<String>(targetId);
    }
    map['classification'] = Variable<String>(classification);
    map['confidence'] = Variable<double>(confidence);
    map['attribution_status'] = Variable<String>(attributionStatus);
    map['confirmed_by_user'] = Variable<bool>(confirmedByUser);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalAttributionsCompanion toCompanion(bool nullToAbsent) {
    return LocalAttributionsCompanion(
      id: Value(id),
      userId: Value(userId),
      activitySegmentId: Value(activitySegmentId),
      targetType: Value(targetType),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      classification: Value(classification),
      confidence: Value(confidence),
      attributionStatus: Value(attributionStatus),
      confirmedByUser: Value(confirmedByUser),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalAttribution.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAttribution(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      activitySegmentId: serializer.fromJson<String>(json['activitySegmentId']),
      targetType: serializer.fromJson<String>(json['targetType']),
      targetId: serializer.fromJson<String?>(json['targetId']),
      classification: serializer.fromJson<String>(json['classification']),
      confidence: serializer.fromJson<double>(json['confidence']),
      attributionStatus: serializer.fromJson<String>(json['attributionStatus']),
      confirmedByUser: serializer.fromJson<bool>(json['confirmedByUser']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'activitySegmentId': serializer.toJson<String>(activitySegmentId),
      'targetType': serializer.toJson<String>(targetType),
      'targetId': serializer.toJson<String?>(targetId),
      'classification': serializer.toJson<String>(classification),
      'confidence': serializer.toJson<double>(confidence),
      'attributionStatus': serializer.toJson<String>(attributionStatus),
      'confirmedByUser': serializer.toJson<bool>(confirmedByUser),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalAttribution copyWith({
    String? id,
    String? userId,
    String? activitySegmentId,
    String? targetType,
    Value<String?> targetId = const Value.absent(),
    String? classification,
    double? confidence,
    String? attributionStatus,
    bool? confirmedByUser,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalAttribution(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    activitySegmentId: activitySegmentId ?? this.activitySegmentId,
    targetType: targetType ?? this.targetType,
    targetId: targetId.present ? targetId.value : this.targetId,
    classification: classification ?? this.classification,
    confidence: confidence ?? this.confidence,
    attributionStatus: attributionStatus ?? this.attributionStatus,
    confirmedByUser: confirmedByUser ?? this.confirmedByUser,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalAttribution copyWithCompanion(LocalAttributionsCompanion data) {
    return LocalAttribution(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      activitySegmentId: data.activitySegmentId.present
          ? data.activitySegmentId.value
          : this.activitySegmentId,
      targetType: data.targetType.present
          ? data.targetType.value
          : this.targetType,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      classification: data.classification.present
          ? data.classification.value
          : this.classification,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      attributionStatus: data.attributionStatus.present
          ? data.attributionStatus.value
          : this.attributionStatus,
      confirmedByUser: data.confirmedByUser.present
          ? data.confirmedByUser.value
          : this.confirmedByUser,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAttribution(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('activitySegmentId: $activitySegmentId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('classification: $classification, ')
          ..write('confidence: $confidence, ')
          ..write('attributionStatus: $attributionStatus, ')
          ..write('confirmedByUser: $confirmedByUser, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    activitySegmentId,
    targetType,
    targetId,
    classification,
    confidence,
    attributionStatus,
    confirmedByUser,
    revision,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAttribution &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.activitySegmentId == this.activitySegmentId &&
          other.targetType == this.targetType &&
          other.targetId == this.targetId &&
          other.classification == this.classification &&
          other.confidence == this.confidence &&
          other.attributionStatus == this.attributionStatus &&
          other.confirmedByUser == this.confirmedByUser &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class LocalAttributionsCompanion extends UpdateCompanion<LocalAttribution> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> activitySegmentId;
  final Value<String> targetType;
  final Value<String?> targetId;
  final Value<String> classification;
  final Value<double> confidence;
  final Value<String> attributionStatus;
  final Value<bool> confirmedByUser;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalAttributionsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.activitySegmentId = const Value.absent(),
    this.targetType = const Value.absent(),
    this.targetId = const Value.absent(),
    this.classification = const Value.absent(),
    this.confidence = const Value.absent(),
    this.attributionStatus = const Value.absent(),
    this.confirmedByUser = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAttributionsCompanion.insert({
    required String id,
    required String userId,
    required String activitySegmentId,
    required String targetType,
    this.targetId = const Value.absent(),
    required String classification,
    required double confidence,
    this.attributionStatus = const Value.absent(),
    this.confirmedByUser = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       activitySegmentId = Value(activitySegmentId),
       targetType = Value(targetType),
       classification = Value(classification),
       confidence = Value(confidence),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalAttribution> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? activitySegmentId,
    Expression<String>? targetType,
    Expression<String>? targetId,
    Expression<String>? classification,
    Expression<double>? confidence,
    Expression<String>? attributionStatus,
    Expression<bool>? confirmedByUser,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (activitySegmentId != null) 'activity_segment_id': activitySegmentId,
      if (targetType != null) 'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      if (classification != null) 'classification': classification,
      if (confidence != null) 'confidence': confidence,
      if (attributionStatus != null) 'attribution_status': attributionStatus,
      if (confirmedByUser != null) 'confirmed_by_user': confirmedByUser,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAttributionsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? activitySegmentId,
    Value<String>? targetType,
    Value<String?>? targetId,
    Value<String>? classification,
    Value<double>? confidence,
    Value<String>? attributionStatus,
    Value<bool>? confirmedByUser,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalAttributionsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      activitySegmentId: activitySegmentId ?? this.activitySegmentId,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      classification: classification ?? this.classification,
      confidence: confidence ?? this.confidence,
      attributionStatus: attributionStatus ?? this.attributionStatus,
      confirmedByUser: confirmedByUser ?? this.confirmedByUser,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (activitySegmentId.present) {
      map['activity_segment_id'] = Variable<String>(activitySegmentId.value);
    }
    if (targetType.present) {
      map['target_type'] = Variable<String>(targetType.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (classification.present) {
      map['classification'] = Variable<String>(classification.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (attributionStatus.present) {
      map['attribution_status'] = Variable<String>(attributionStatus.value);
    }
    if (confirmedByUser.present) {
      map['confirmed_by_user'] = Variable<bool>(confirmedByUser.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAttributionsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('activitySegmentId: $activitySegmentId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('classification: $classification, ')
          ..write('confidence: $confidence, ')
          ..write('attributionStatus: $attributionStatus, ')
          ..write('confirmedByUser: $confirmedByUser, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalContributionsTable extends LocalContributions
    with TableInfo<$LocalContributionsTable, LocalContribution> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalContributionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activitySegmentIdMeta = const VerificationMeta(
    'activitySegmentId',
  );
  @override
  late final GeneratedColumn<String> activitySegmentId =
      GeneratedColumn<String>(
        'activity_segment_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _attributionIdMeta = const VerificationMeta(
    'attributionId',
  );
  @override
  late final GeneratedColumn<String> attributionId = GeneratedColumn<String>(
    'attribution_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTypeMeta = const VerificationMeta(
    'targetType',
  );
  @override
  late final GeneratedColumn<String> targetType = GeneratedColumn<String>(
    'target_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contributionTypeMeta = const VerificationMeta(
    'contributionType',
  );
  @override
  late final GeneratedColumn<String> contributionType = GeneratedColumn<String>(
    'contribution_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _physicalDurationMsMeta =
      const VerificationMeta('physicalDurationMs');
  @override
  late final GeneratedColumn<int> physicalDurationMs = GeneratedColumn<int>(
    'physical_duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _creditedDurationMsMeta =
      const VerificationMeta('creditedDurationMs');
  @override
  late final GeneratedColumn<int> creditedDurationMs = GeneratedColumn<int>(
    'credited_duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressValueMeta = const VerificationMeta(
    'progressValue',
  );
  @override
  late final GeneratedColumn<double> progressValue = GeneratedColumn<double>(
    'progress_value',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isUnscheduledMeta = const VerificationMeta(
    'isUnscheduled',
  );
  @override
  late final GeneratedColumn<bool> isUnscheduled = GeneratedColumn<bool>(
    'is_unscheduled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_unscheduled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isCrossTaskMeta = const VerificationMeta(
    'isCrossTask',
  );
  @override
  late final GeneratedColumn<bool> isCrossTask = GeneratedColumn<bool>(
    'is_cross_task',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_cross_task" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isIdleDerivedMeta = const VerificationMeta(
    'isIdleDerived',
  );
  @override
  late final GeneratedColumn<bool> isIdleDerived = GeneratedColumn<bool>(
    'is_idle_derived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_idle_derived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isAutomaticMeta = const VerificationMeta(
    'isAutomatic',
  );
  @override
  late final GeneratedColumn<bool> isAutomatic = GeneratedColumn<bool>(
    'is_automatic',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_automatic" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    activitySegmentId,
    attributionId,
    targetType,
    targetId,
    contributionType,
    physicalDurationMs,
    creditedDurationMs,
    progressValue,
    isUnscheduled,
    isCrossTask,
    isIdleDerived,
    isAutomatic,
    revision,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_contributions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalContribution> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('activity_segment_id')) {
      context.handle(
        _activitySegmentIdMeta,
        activitySegmentId.isAcceptableOrUnknown(
          data['activity_segment_id']!,
          _activitySegmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activitySegmentIdMeta);
    }
    if (data.containsKey('attribution_id')) {
      context.handle(
        _attributionIdMeta,
        attributionId.isAcceptableOrUnknown(
          data['attribution_id']!,
          _attributionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attributionIdMeta);
    }
    if (data.containsKey('target_type')) {
      context.handle(
        _targetTypeMeta,
        targetType.isAcceptableOrUnknown(data['target_type']!, _targetTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_targetTypeMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    }
    if (data.containsKey('contribution_type')) {
      context.handle(
        _contributionTypeMeta,
        contributionType.isAcceptableOrUnknown(
          data['contribution_type']!,
          _contributionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contributionTypeMeta);
    }
    if (data.containsKey('physical_duration_ms')) {
      context.handle(
        _physicalDurationMsMeta,
        physicalDurationMs.isAcceptableOrUnknown(
          data['physical_duration_ms']!,
          _physicalDurationMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_physicalDurationMsMeta);
    }
    if (data.containsKey('credited_duration_ms')) {
      context.handle(
        _creditedDurationMsMeta,
        creditedDurationMs.isAcceptableOrUnknown(
          data['credited_duration_ms']!,
          _creditedDurationMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_creditedDurationMsMeta);
    }
    if (data.containsKey('progress_value')) {
      context.handle(
        _progressValueMeta,
        progressValue.isAcceptableOrUnknown(
          data['progress_value']!,
          _progressValueMeta,
        ),
      );
    }
    if (data.containsKey('is_unscheduled')) {
      context.handle(
        _isUnscheduledMeta,
        isUnscheduled.isAcceptableOrUnknown(
          data['is_unscheduled']!,
          _isUnscheduledMeta,
        ),
      );
    }
    if (data.containsKey('is_cross_task')) {
      context.handle(
        _isCrossTaskMeta,
        isCrossTask.isAcceptableOrUnknown(
          data['is_cross_task']!,
          _isCrossTaskMeta,
        ),
      );
    }
    if (data.containsKey('is_idle_derived')) {
      context.handle(
        _isIdleDerivedMeta,
        isIdleDerived.isAcceptableOrUnknown(
          data['is_idle_derived']!,
          _isIdleDerivedMeta,
        ),
      );
    }
    if (data.containsKey('is_automatic')) {
      context.handle(
        _isAutomaticMeta,
        isAutomatic.isAcceptableOrUnknown(
          data['is_automatic']!,
          _isAutomaticMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalContribution map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalContribution(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      activitySegmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_segment_id'],
      )!,
      attributionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attribution_id'],
      )!,
      targetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_type'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      ),
      contributionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contribution_type'],
      )!,
      physicalDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}physical_duration_ms'],
      )!,
      creditedDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}credited_duration_ms'],
      )!,
      progressValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress_value'],
      ),
      isUnscheduled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_unscheduled'],
      )!,
      isCrossTask: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_cross_task'],
      )!,
      isIdleDerived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_idle_derived'],
      )!,
      isAutomatic: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_automatic'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalContributionsTable createAlias(String alias) {
    return $LocalContributionsTable(attachedDatabase, alias);
  }
}

class LocalContribution extends DataClass
    implements Insertable<LocalContribution> {
  final String id;
  final String userId;
  final String activitySegmentId;
  final String attributionId;
  final String targetType;
  final String? targetId;
  final String contributionType;
  final int physicalDurationMs;
  final int creditedDurationMs;
  final double? progressValue;
  final bool isUnscheduled;
  final bool isCrossTask;
  final bool isIdleDerived;
  final bool isAutomatic;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const LocalContribution({
    required this.id,
    required this.userId,
    required this.activitySegmentId,
    required this.attributionId,
    required this.targetType,
    this.targetId,
    required this.contributionType,
    required this.physicalDurationMs,
    required this.creditedDurationMs,
    this.progressValue,
    required this.isUnscheduled,
    required this.isCrossTask,
    required this.isIdleDerived,
    required this.isAutomatic,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['activity_segment_id'] = Variable<String>(activitySegmentId);
    map['attribution_id'] = Variable<String>(attributionId);
    map['target_type'] = Variable<String>(targetType);
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<String>(targetId);
    }
    map['contribution_type'] = Variable<String>(contributionType);
    map['physical_duration_ms'] = Variable<int>(physicalDurationMs);
    map['credited_duration_ms'] = Variable<int>(creditedDurationMs);
    if (!nullToAbsent || progressValue != null) {
      map['progress_value'] = Variable<double>(progressValue);
    }
    map['is_unscheduled'] = Variable<bool>(isUnscheduled);
    map['is_cross_task'] = Variable<bool>(isCrossTask);
    map['is_idle_derived'] = Variable<bool>(isIdleDerived);
    map['is_automatic'] = Variable<bool>(isAutomatic);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalContributionsCompanion toCompanion(bool nullToAbsent) {
    return LocalContributionsCompanion(
      id: Value(id),
      userId: Value(userId),
      activitySegmentId: Value(activitySegmentId),
      attributionId: Value(attributionId),
      targetType: Value(targetType),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      contributionType: Value(contributionType),
      physicalDurationMs: Value(physicalDurationMs),
      creditedDurationMs: Value(creditedDurationMs),
      progressValue: progressValue == null && nullToAbsent
          ? const Value.absent()
          : Value(progressValue),
      isUnscheduled: Value(isUnscheduled),
      isCrossTask: Value(isCrossTask),
      isIdleDerived: Value(isIdleDerived),
      isAutomatic: Value(isAutomatic),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalContribution.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalContribution(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      activitySegmentId: serializer.fromJson<String>(json['activitySegmentId']),
      attributionId: serializer.fromJson<String>(json['attributionId']),
      targetType: serializer.fromJson<String>(json['targetType']),
      targetId: serializer.fromJson<String?>(json['targetId']),
      contributionType: serializer.fromJson<String>(json['contributionType']),
      physicalDurationMs: serializer.fromJson<int>(json['physicalDurationMs']),
      creditedDurationMs: serializer.fromJson<int>(json['creditedDurationMs']),
      progressValue: serializer.fromJson<double?>(json['progressValue']),
      isUnscheduled: serializer.fromJson<bool>(json['isUnscheduled']),
      isCrossTask: serializer.fromJson<bool>(json['isCrossTask']),
      isIdleDerived: serializer.fromJson<bool>(json['isIdleDerived']),
      isAutomatic: serializer.fromJson<bool>(json['isAutomatic']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'activitySegmentId': serializer.toJson<String>(activitySegmentId),
      'attributionId': serializer.toJson<String>(attributionId),
      'targetType': serializer.toJson<String>(targetType),
      'targetId': serializer.toJson<String?>(targetId),
      'contributionType': serializer.toJson<String>(contributionType),
      'physicalDurationMs': serializer.toJson<int>(physicalDurationMs),
      'creditedDurationMs': serializer.toJson<int>(creditedDurationMs),
      'progressValue': serializer.toJson<double?>(progressValue),
      'isUnscheduled': serializer.toJson<bool>(isUnscheduled),
      'isCrossTask': serializer.toJson<bool>(isCrossTask),
      'isIdleDerived': serializer.toJson<bool>(isIdleDerived),
      'isAutomatic': serializer.toJson<bool>(isAutomatic),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalContribution copyWith({
    String? id,
    String? userId,
    String? activitySegmentId,
    String? attributionId,
    String? targetType,
    Value<String?> targetId = const Value.absent(),
    String? contributionType,
    int? physicalDurationMs,
    int? creditedDurationMs,
    Value<double?> progressValue = const Value.absent(),
    bool? isUnscheduled,
    bool? isCrossTask,
    bool? isIdleDerived,
    bool? isAutomatic,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalContribution(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    activitySegmentId: activitySegmentId ?? this.activitySegmentId,
    attributionId: attributionId ?? this.attributionId,
    targetType: targetType ?? this.targetType,
    targetId: targetId.present ? targetId.value : this.targetId,
    contributionType: contributionType ?? this.contributionType,
    physicalDurationMs: physicalDurationMs ?? this.physicalDurationMs,
    creditedDurationMs: creditedDurationMs ?? this.creditedDurationMs,
    progressValue: progressValue.present
        ? progressValue.value
        : this.progressValue,
    isUnscheduled: isUnscheduled ?? this.isUnscheduled,
    isCrossTask: isCrossTask ?? this.isCrossTask,
    isIdleDerived: isIdleDerived ?? this.isIdleDerived,
    isAutomatic: isAutomatic ?? this.isAutomatic,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalContribution copyWithCompanion(LocalContributionsCompanion data) {
    return LocalContribution(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      activitySegmentId: data.activitySegmentId.present
          ? data.activitySegmentId.value
          : this.activitySegmentId,
      attributionId: data.attributionId.present
          ? data.attributionId.value
          : this.attributionId,
      targetType: data.targetType.present
          ? data.targetType.value
          : this.targetType,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      contributionType: data.contributionType.present
          ? data.contributionType.value
          : this.contributionType,
      physicalDurationMs: data.physicalDurationMs.present
          ? data.physicalDurationMs.value
          : this.physicalDurationMs,
      creditedDurationMs: data.creditedDurationMs.present
          ? data.creditedDurationMs.value
          : this.creditedDurationMs,
      progressValue: data.progressValue.present
          ? data.progressValue.value
          : this.progressValue,
      isUnscheduled: data.isUnscheduled.present
          ? data.isUnscheduled.value
          : this.isUnscheduled,
      isCrossTask: data.isCrossTask.present
          ? data.isCrossTask.value
          : this.isCrossTask,
      isIdleDerived: data.isIdleDerived.present
          ? data.isIdleDerived.value
          : this.isIdleDerived,
      isAutomatic: data.isAutomatic.present
          ? data.isAutomatic.value
          : this.isAutomatic,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalContribution(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('activitySegmentId: $activitySegmentId, ')
          ..write('attributionId: $attributionId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('contributionType: $contributionType, ')
          ..write('physicalDurationMs: $physicalDurationMs, ')
          ..write('creditedDurationMs: $creditedDurationMs, ')
          ..write('progressValue: $progressValue, ')
          ..write('isUnscheduled: $isUnscheduled, ')
          ..write('isCrossTask: $isCrossTask, ')
          ..write('isIdleDerived: $isIdleDerived, ')
          ..write('isAutomatic: $isAutomatic, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    activitySegmentId,
    attributionId,
    targetType,
    targetId,
    contributionType,
    physicalDurationMs,
    creditedDurationMs,
    progressValue,
    isUnscheduled,
    isCrossTask,
    isIdleDerived,
    isAutomatic,
    revision,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalContribution &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.activitySegmentId == this.activitySegmentId &&
          other.attributionId == this.attributionId &&
          other.targetType == this.targetType &&
          other.targetId == this.targetId &&
          other.contributionType == this.contributionType &&
          other.physicalDurationMs == this.physicalDurationMs &&
          other.creditedDurationMs == this.creditedDurationMs &&
          other.progressValue == this.progressValue &&
          other.isUnscheduled == this.isUnscheduled &&
          other.isCrossTask == this.isCrossTask &&
          other.isIdleDerived == this.isIdleDerived &&
          other.isAutomatic == this.isAutomatic &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class LocalContributionsCompanion extends UpdateCompanion<LocalContribution> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> activitySegmentId;
  final Value<String> attributionId;
  final Value<String> targetType;
  final Value<String?> targetId;
  final Value<String> contributionType;
  final Value<int> physicalDurationMs;
  final Value<int> creditedDurationMs;
  final Value<double?> progressValue;
  final Value<bool> isUnscheduled;
  final Value<bool> isCrossTask;
  final Value<bool> isIdleDerived;
  final Value<bool> isAutomatic;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalContributionsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.activitySegmentId = const Value.absent(),
    this.attributionId = const Value.absent(),
    this.targetType = const Value.absent(),
    this.targetId = const Value.absent(),
    this.contributionType = const Value.absent(),
    this.physicalDurationMs = const Value.absent(),
    this.creditedDurationMs = const Value.absent(),
    this.progressValue = const Value.absent(),
    this.isUnscheduled = const Value.absent(),
    this.isCrossTask = const Value.absent(),
    this.isIdleDerived = const Value.absent(),
    this.isAutomatic = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalContributionsCompanion.insert({
    required String id,
    required String userId,
    required String activitySegmentId,
    required String attributionId,
    required String targetType,
    this.targetId = const Value.absent(),
    required String contributionType,
    required int physicalDurationMs,
    required int creditedDurationMs,
    this.progressValue = const Value.absent(),
    this.isUnscheduled = const Value.absent(),
    this.isCrossTask = const Value.absent(),
    this.isIdleDerived = const Value.absent(),
    this.isAutomatic = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       activitySegmentId = Value(activitySegmentId),
       attributionId = Value(attributionId),
       targetType = Value(targetType),
       contributionType = Value(contributionType),
       physicalDurationMs = Value(physicalDurationMs),
       creditedDurationMs = Value(creditedDurationMs),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalContribution> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? activitySegmentId,
    Expression<String>? attributionId,
    Expression<String>? targetType,
    Expression<String>? targetId,
    Expression<String>? contributionType,
    Expression<int>? physicalDurationMs,
    Expression<int>? creditedDurationMs,
    Expression<double>? progressValue,
    Expression<bool>? isUnscheduled,
    Expression<bool>? isCrossTask,
    Expression<bool>? isIdleDerived,
    Expression<bool>? isAutomatic,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (activitySegmentId != null) 'activity_segment_id': activitySegmentId,
      if (attributionId != null) 'attribution_id': attributionId,
      if (targetType != null) 'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      if (contributionType != null) 'contribution_type': contributionType,
      if (physicalDurationMs != null)
        'physical_duration_ms': physicalDurationMs,
      if (creditedDurationMs != null)
        'credited_duration_ms': creditedDurationMs,
      if (progressValue != null) 'progress_value': progressValue,
      if (isUnscheduled != null) 'is_unscheduled': isUnscheduled,
      if (isCrossTask != null) 'is_cross_task': isCrossTask,
      if (isIdleDerived != null) 'is_idle_derived': isIdleDerived,
      if (isAutomatic != null) 'is_automatic': isAutomatic,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalContributionsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? activitySegmentId,
    Value<String>? attributionId,
    Value<String>? targetType,
    Value<String?>? targetId,
    Value<String>? contributionType,
    Value<int>? physicalDurationMs,
    Value<int>? creditedDurationMs,
    Value<double?>? progressValue,
    Value<bool>? isUnscheduled,
    Value<bool>? isCrossTask,
    Value<bool>? isIdleDerived,
    Value<bool>? isAutomatic,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalContributionsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      activitySegmentId: activitySegmentId ?? this.activitySegmentId,
      attributionId: attributionId ?? this.attributionId,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      contributionType: contributionType ?? this.contributionType,
      physicalDurationMs: physicalDurationMs ?? this.physicalDurationMs,
      creditedDurationMs: creditedDurationMs ?? this.creditedDurationMs,
      progressValue: progressValue ?? this.progressValue,
      isUnscheduled: isUnscheduled ?? this.isUnscheduled,
      isCrossTask: isCrossTask ?? this.isCrossTask,
      isIdleDerived: isIdleDerived ?? this.isIdleDerived,
      isAutomatic: isAutomatic ?? this.isAutomatic,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (activitySegmentId.present) {
      map['activity_segment_id'] = Variable<String>(activitySegmentId.value);
    }
    if (attributionId.present) {
      map['attribution_id'] = Variable<String>(attributionId.value);
    }
    if (targetType.present) {
      map['target_type'] = Variable<String>(targetType.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (contributionType.present) {
      map['contribution_type'] = Variable<String>(contributionType.value);
    }
    if (physicalDurationMs.present) {
      map['physical_duration_ms'] = Variable<int>(physicalDurationMs.value);
    }
    if (creditedDurationMs.present) {
      map['credited_duration_ms'] = Variable<int>(creditedDurationMs.value);
    }
    if (progressValue.present) {
      map['progress_value'] = Variable<double>(progressValue.value);
    }
    if (isUnscheduled.present) {
      map['is_unscheduled'] = Variable<bool>(isUnscheduled.value);
    }
    if (isCrossTask.present) {
      map['is_cross_task'] = Variable<bool>(isCrossTask.value);
    }
    if (isIdleDerived.present) {
      map['is_idle_derived'] = Variable<bool>(isIdleDerived.value);
    }
    if (isAutomatic.present) {
      map['is_automatic'] = Variable<bool>(isAutomatic.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalContributionsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('activitySegmentId: $activitySegmentId, ')
          ..write('attributionId: $attributionId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('contributionType: $contributionType, ')
          ..write('physicalDurationMs: $physicalDurationMs, ')
          ..write('creditedDurationMs: $creditedDurationMs, ')
          ..write('progressValue: $progressValue, ')
          ..write('isUnscheduled: $isUnscheduled, ')
          ..write('isCrossTask: $isCrossTask, ')
          ..write('isIdleDerived: $isIdleDerived, ')
          ..write('isAutomatic: $isAutomatic, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalActivityReviewsTable extends LocalActivityReviews
    with TableInfo<$LocalActivityReviewsTable, LocalActivityReview> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalActivityReviewsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activitySegmentIdMeta = const VerificationMeta(
    'activitySegmentId',
  );
  @override
  late final GeneratedColumn<String> activitySegmentId =
      GeneratedColumn<String>(
        'activity_segment_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _reviewReasonMeta = const VerificationMeta(
    'reviewReason',
  );
  @override
  late final GeneratedColumn<String> reviewReason = GeneratedColumn<String>(
    'review_reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _suggestedTargetTypeMeta =
      const VerificationMeta('suggestedTargetType');
  @override
  late final GeneratedColumn<String> suggestedTargetType =
      GeneratedColumn<String>(
        'suggested_target_type',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _suggestedTargetIdMeta = const VerificationMeta(
    'suggestedTargetId',
  );
  @override
  late final GeneratedColumn<String> suggestedTargetId =
      GeneratedColumn<String>(
        'suggested_target_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _suggestedTargetTitleMeta =
      const VerificationMeta('suggestedTargetTitle');
  @override
  late final GeneratedColumn<String> suggestedTargetTitle =
      GeneratedColumn<String>(
        'suggested_target_title',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _suggestedClassificationMeta =
      const VerificationMeta('suggestedClassification');
  @override
  late final GeneratedColumn<String> suggestedClassification =
      GeneratedColumn<String>(
        'suggested_classification',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _reviewedAtMeta = const VerificationMeta(
    'reviewedAt',
  );
  @override
  late final GeneratedColumn<DateTime> reviewedAt = GeneratedColumn<DateTime>(
    'reviewed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    activitySegmentId,
    reviewReason,
    priority,
    suggestedTargetType,
    suggestedTargetId,
    suggestedTargetTitle,
    suggestedClassification,
    confidence,
    status,
    reviewedAt,
    revision,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_activity_reviews';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalActivityReview> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('activity_segment_id')) {
      context.handle(
        _activitySegmentIdMeta,
        activitySegmentId.isAcceptableOrUnknown(
          data['activity_segment_id']!,
          _activitySegmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activitySegmentIdMeta);
    }
    if (data.containsKey('review_reason')) {
      context.handle(
        _reviewReasonMeta,
        reviewReason.isAcceptableOrUnknown(
          data['review_reason']!,
          _reviewReasonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reviewReasonMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('suggested_target_type')) {
      context.handle(
        _suggestedTargetTypeMeta,
        suggestedTargetType.isAcceptableOrUnknown(
          data['suggested_target_type']!,
          _suggestedTargetTypeMeta,
        ),
      );
    }
    if (data.containsKey('suggested_target_id')) {
      context.handle(
        _suggestedTargetIdMeta,
        suggestedTargetId.isAcceptableOrUnknown(
          data['suggested_target_id']!,
          _suggestedTargetIdMeta,
        ),
      );
    }
    if (data.containsKey('suggested_target_title')) {
      context.handle(
        _suggestedTargetTitleMeta,
        suggestedTargetTitle.isAcceptableOrUnknown(
          data['suggested_target_title']!,
          _suggestedTargetTitleMeta,
        ),
      );
    }
    if (data.containsKey('suggested_classification')) {
      context.handle(
        _suggestedClassificationMeta,
        suggestedClassification.isAcceptableOrUnknown(
          data['suggested_classification']!,
          _suggestedClassificationMeta,
        ),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
        _reviewedAtMeta,
        reviewedAt.isAcceptableOrUnknown(data['reviewed_at']!, _reviewedAtMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalActivityReview map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalActivityReview(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      activitySegmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_segment_id'],
      )!,
      reviewReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_reason'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      suggestedTargetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggested_target_type'],
      ),
      suggestedTargetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggested_target_id'],
      ),
      suggestedTargetTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggested_target_title'],
      ),
      suggestedClassification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggested_classification'],
      ),
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      reviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reviewed_at'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalActivityReviewsTable createAlias(String alias) {
    return $LocalActivityReviewsTable(attachedDatabase, alias);
  }
}

class LocalActivityReview extends DataClass
    implements Insertable<LocalActivityReview> {
  final String id;
  final String userId;
  final String activitySegmentId;
  final String reviewReason;
  final int priority;
  final String? suggestedTargetType;
  final String? suggestedTargetId;
  final String? suggestedTargetTitle;
  final String? suggestedClassification;
  final double? confidence;
  final String status;
  final DateTime? reviewedAt;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const LocalActivityReview({
    required this.id,
    required this.userId,
    required this.activitySegmentId,
    required this.reviewReason,
    required this.priority,
    this.suggestedTargetType,
    this.suggestedTargetId,
    this.suggestedTargetTitle,
    this.suggestedClassification,
    this.confidence,
    required this.status,
    this.reviewedAt,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['activity_segment_id'] = Variable<String>(activitySegmentId);
    map['review_reason'] = Variable<String>(reviewReason);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || suggestedTargetType != null) {
      map['suggested_target_type'] = Variable<String>(suggestedTargetType);
    }
    if (!nullToAbsent || suggestedTargetId != null) {
      map['suggested_target_id'] = Variable<String>(suggestedTargetId);
    }
    if (!nullToAbsent || suggestedTargetTitle != null) {
      map['suggested_target_title'] = Variable<String>(suggestedTargetTitle);
    }
    if (!nullToAbsent || suggestedClassification != null) {
      map['suggested_classification'] = Variable<String>(
        suggestedClassification,
      );
    }
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || reviewedAt != null) {
      map['reviewed_at'] = Variable<DateTime>(reviewedAt);
    }
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalActivityReviewsCompanion toCompanion(bool nullToAbsent) {
    return LocalActivityReviewsCompanion(
      id: Value(id),
      userId: Value(userId),
      activitySegmentId: Value(activitySegmentId),
      reviewReason: Value(reviewReason),
      priority: Value(priority),
      suggestedTargetType: suggestedTargetType == null && nullToAbsent
          ? const Value.absent()
          : Value(suggestedTargetType),
      suggestedTargetId: suggestedTargetId == null && nullToAbsent
          ? const Value.absent()
          : Value(suggestedTargetId),
      suggestedTargetTitle: suggestedTargetTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(suggestedTargetTitle),
      suggestedClassification: suggestedClassification == null && nullToAbsent
          ? const Value.absent()
          : Value(suggestedClassification),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      status: Value(status),
      reviewedAt: reviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewedAt),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalActivityReview.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalActivityReview(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      activitySegmentId: serializer.fromJson<String>(json['activitySegmentId']),
      reviewReason: serializer.fromJson<String>(json['reviewReason']),
      priority: serializer.fromJson<int>(json['priority']),
      suggestedTargetType: serializer.fromJson<String?>(
        json['suggestedTargetType'],
      ),
      suggestedTargetId: serializer.fromJson<String?>(
        json['suggestedTargetId'],
      ),
      suggestedTargetTitle: serializer.fromJson<String?>(
        json['suggestedTargetTitle'],
      ),
      suggestedClassification: serializer.fromJson<String?>(
        json['suggestedClassification'],
      ),
      confidence: serializer.fromJson<double?>(json['confidence']),
      status: serializer.fromJson<String>(json['status']),
      reviewedAt: serializer.fromJson<DateTime?>(json['reviewedAt']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'activitySegmentId': serializer.toJson<String>(activitySegmentId),
      'reviewReason': serializer.toJson<String>(reviewReason),
      'priority': serializer.toJson<int>(priority),
      'suggestedTargetType': serializer.toJson<String?>(suggestedTargetType),
      'suggestedTargetId': serializer.toJson<String?>(suggestedTargetId),
      'suggestedTargetTitle': serializer.toJson<String?>(suggestedTargetTitle),
      'suggestedClassification': serializer.toJson<String?>(
        suggestedClassification,
      ),
      'confidence': serializer.toJson<double?>(confidence),
      'status': serializer.toJson<String>(status),
      'reviewedAt': serializer.toJson<DateTime?>(reviewedAt),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalActivityReview copyWith({
    String? id,
    String? userId,
    String? activitySegmentId,
    String? reviewReason,
    int? priority,
    Value<String?> suggestedTargetType = const Value.absent(),
    Value<String?> suggestedTargetId = const Value.absent(),
    Value<String?> suggestedTargetTitle = const Value.absent(),
    Value<String?> suggestedClassification = const Value.absent(),
    Value<double?> confidence = const Value.absent(),
    String? status,
    Value<DateTime?> reviewedAt = const Value.absent(),
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalActivityReview(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    activitySegmentId: activitySegmentId ?? this.activitySegmentId,
    reviewReason: reviewReason ?? this.reviewReason,
    priority: priority ?? this.priority,
    suggestedTargetType: suggestedTargetType.present
        ? suggestedTargetType.value
        : this.suggestedTargetType,
    suggestedTargetId: suggestedTargetId.present
        ? suggestedTargetId.value
        : this.suggestedTargetId,
    suggestedTargetTitle: suggestedTargetTitle.present
        ? suggestedTargetTitle.value
        : this.suggestedTargetTitle,
    suggestedClassification: suggestedClassification.present
        ? suggestedClassification.value
        : this.suggestedClassification,
    confidence: confidence.present ? confidence.value : this.confidence,
    status: status ?? this.status,
    reviewedAt: reviewedAt.present ? reviewedAt.value : this.reviewedAt,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalActivityReview copyWithCompanion(LocalActivityReviewsCompanion data) {
    return LocalActivityReview(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      activitySegmentId: data.activitySegmentId.present
          ? data.activitySegmentId.value
          : this.activitySegmentId,
      reviewReason: data.reviewReason.present
          ? data.reviewReason.value
          : this.reviewReason,
      priority: data.priority.present ? data.priority.value : this.priority,
      suggestedTargetType: data.suggestedTargetType.present
          ? data.suggestedTargetType.value
          : this.suggestedTargetType,
      suggestedTargetId: data.suggestedTargetId.present
          ? data.suggestedTargetId.value
          : this.suggestedTargetId,
      suggestedTargetTitle: data.suggestedTargetTitle.present
          ? data.suggestedTargetTitle.value
          : this.suggestedTargetTitle,
      suggestedClassification: data.suggestedClassification.present
          ? data.suggestedClassification.value
          : this.suggestedClassification,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      status: data.status.present ? data.status.value : this.status,
      reviewedAt: data.reviewedAt.present
          ? data.reviewedAt.value
          : this.reviewedAt,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalActivityReview(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('activitySegmentId: $activitySegmentId, ')
          ..write('reviewReason: $reviewReason, ')
          ..write('priority: $priority, ')
          ..write('suggestedTargetType: $suggestedTargetType, ')
          ..write('suggestedTargetId: $suggestedTargetId, ')
          ..write('suggestedTargetTitle: $suggestedTargetTitle, ')
          ..write('suggestedClassification: $suggestedClassification, ')
          ..write('confidence: $confidence, ')
          ..write('status: $status, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    activitySegmentId,
    reviewReason,
    priority,
    suggestedTargetType,
    suggestedTargetId,
    suggestedTargetTitle,
    suggestedClassification,
    confidence,
    status,
    reviewedAt,
    revision,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalActivityReview &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.activitySegmentId == this.activitySegmentId &&
          other.reviewReason == this.reviewReason &&
          other.priority == this.priority &&
          other.suggestedTargetType == this.suggestedTargetType &&
          other.suggestedTargetId == this.suggestedTargetId &&
          other.suggestedTargetTitle == this.suggestedTargetTitle &&
          other.suggestedClassification == this.suggestedClassification &&
          other.confidence == this.confidence &&
          other.status == this.status &&
          other.reviewedAt == this.reviewedAt &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class LocalActivityReviewsCompanion
    extends UpdateCompanion<LocalActivityReview> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> activitySegmentId;
  final Value<String> reviewReason;
  final Value<int> priority;
  final Value<String?> suggestedTargetType;
  final Value<String?> suggestedTargetId;
  final Value<String?> suggestedTargetTitle;
  final Value<String?> suggestedClassification;
  final Value<double?> confidence;
  final Value<String> status;
  final Value<DateTime?> reviewedAt;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalActivityReviewsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.activitySegmentId = const Value.absent(),
    this.reviewReason = const Value.absent(),
    this.priority = const Value.absent(),
    this.suggestedTargetType = const Value.absent(),
    this.suggestedTargetId = const Value.absent(),
    this.suggestedTargetTitle = const Value.absent(),
    this.suggestedClassification = const Value.absent(),
    this.confidence = const Value.absent(),
    this.status = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalActivityReviewsCompanion.insert({
    required String id,
    required String userId,
    required String activitySegmentId,
    required String reviewReason,
    this.priority = const Value.absent(),
    this.suggestedTargetType = const Value.absent(),
    this.suggestedTargetId = const Value.absent(),
    this.suggestedTargetTitle = const Value.absent(),
    this.suggestedClassification = const Value.absent(),
    this.confidence = const Value.absent(),
    this.status = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       activitySegmentId = Value(activitySegmentId),
       reviewReason = Value(reviewReason),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalActivityReview> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? activitySegmentId,
    Expression<String>? reviewReason,
    Expression<int>? priority,
    Expression<String>? suggestedTargetType,
    Expression<String>? suggestedTargetId,
    Expression<String>? suggestedTargetTitle,
    Expression<String>? suggestedClassification,
    Expression<double>? confidence,
    Expression<String>? status,
    Expression<DateTime>? reviewedAt,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (activitySegmentId != null) 'activity_segment_id': activitySegmentId,
      if (reviewReason != null) 'review_reason': reviewReason,
      if (priority != null) 'priority': priority,
      if (suggestedTargetType != null)
        'suggested_target_type': suggestedTargetType,
      if (suggestedTargetId != null) 'suggested_target_id': suggestedTargetId,
      if (suggestedTargetTitle != null)
        'suggested_target_title': suggestedTargetTitle,
      if (suggestedClassification != null)
        'suggested_classification': suggestedClassification,
      if (confidence != null) 'confidence': confidence,
      if (status != null) 'status': status,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalActivityReviewsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? activitySegmentId,
    Value<String>? reviewReason,
    Value<int>? priority,
    Value<String?>? suggestedTargetType,
    Value<String?>? suggestedTargetId,
    Value<String?>? suggestedTargetTitle,
    Value<String?>? suggestedClassification,
    Value<double?>? confidence,
    Value<String>? status,
    Value<DateTime?>? reviewedAt,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalActivityReviewsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      activitySegmentId: activitySegmentId ?? this.activitySegmentId,
      reviewReason: reviewReason ?? this.reviewReason,
      priority: priority ?? this.priority,
      suggestedTargetType: suggestedTargetType ?? this.suggestedTargetType,
      suggestedTargetId: suggestedTargetId ?? this.suggestedTargetId,
      suggestedTargetTitle: suggestedTargetTitle ?? this.suggestedTargetTitle,
      suggestedClassification:
          suggestedClassification ?? this.suggestedClassification,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (activitySegmentId.present) {
      map['activity_segment_id'] = Variable<String>(activitySegmentId.value);
    }
    if (reviewReason.present) {
      map['review_reason'] = Variable<String>(reviewReason.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (suggestedTargetType.present) {
      map['suggested_target_type'] = Variable<String>(
        suggestedTargetType.value,
      );
    }
    if (suggestedTargetId.present) {
      map['suggested_target_id'] = Variable<String>(suggestedTargetId.value);
    }
    if (suggestedTargetTitle.present) {
      map['suggested_target_title'] = Variable<String>(
        suggestedTargetTitle.value,
      );
    }
    if (suggestedClassification.present) {
      map['suggested_classification'] = Variable<String>(
        suggestedClassification.value,
      );
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<DateTime>(reviewedAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalActivityReviewsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('activitySegmentId: $activitySegmentId, ')
          ..write('reviewReason: $reviewReason, ')
          ..write('priority: $priority, ')
          ..write('suggestedTargetType: $suggestedTargetType, ')
          ..write('suggestedTargetId: $suggestedTargetId, ')
          ..write('suggestedTargetTitle: $suggestedTargetTitle, ')
          ..write('suggestedClassification: $suggestedClassification, ')
          ..write('confidence: $confidence, ')
          ..write('status: $status, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalEntityRecordsTable extends LocalEntityRecords
    with TableInfo<$LocalEntityRecordsTable, LocalEntityRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalEntityRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _secondaryParentIdMeta = const VerificationMeta(
    'secondaryParentId',
  );
  @override
  late final GeneratedColumn<String> secondaryParentId =
      GeneratedColumn<String>(
        'secondary_parent_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<double> position = GeneratedColumn<double>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dataJsonMeta = const VerificationMeta(
    'dataJson',
  );
  @override
  late final GeneratedColumn<String> dataJson = GeneratedColumn<String>(
    'data_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdByDeviceIdMeta = const VerificationMeta(
    'createdByDeviceId',
  );
  @override
  late final GeneratedColumn<String> createdByDeviceId =
      GeneratedColumn<String>(
        'created_by_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedByDeviceIdMeta = const VerificationMeta(
    'updatedByDeviceId',
  );
  @override
  late final GeneratedColumn<String> updatedByDeviceId =
      GeneratedColumn<String>(
        'updated_by_device_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCommandIdMeta = const VerificationMeta(
    'lastCommandId',
  );
  @override
  late final GeneratedColumn<String> lastCommandId = GeneratedColumn<String>(
    'last_command_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    entityType,
    parentId,
    secondaryParentId,
    title,
    status,
    position,
    dataJson,
    revision,
    createdAt,
    updatedAt,
    createdByDeviceId,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_entity_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalEntityRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('secondary_parent_id')) {
      context.handle(
        _secondaryParentIdMeta,
        secondaryParentId.isAcceptableOrUnknown(
          data['secondary_parent_id']!,
          _secondaryParentIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('data_json')) {
      context.handle(
        _dataJsonMeta,
        dataJson.isAcceptableOrUnknown(data['data_json']!, _dataJsonMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('created_by_device_id')) {
      context.handle(
        _createdByDeviceIdMeta,
        createdByDeviceId.isAcceptableOrUnknown(
          data['created_by_device_id']!,
          _createdByDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('updated_by_device_id')) {
      context.handle(
        _updatedByDeviceIdMeta,
        updatedByDeviceId.isAcceptableOrUnknown(
          data['updated_by_device_id']!,
          _updatedByDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('last_command_id')) {
      context.handle(
        _lastCommandIdMeta,
        lastCommandId.isAcceptableOrUnknown(
          data['last_command_id']!,
          _lastCommandIdMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalEntityRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalEntityRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      secondaryParentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secondary_parent_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}position'],
      )!,
      dataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data_json'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      createdByDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_device_id'],
      ),
      updatedByDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_by_device_id'],
      ),
      lastCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_command_id'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalEntityRecordsTable createAlias(String alias) {
    return $LocalEntityRecordsTable(attachedDatabase, alias);
  }
}

class LocalEntityRecord extends DataClass
    implements Insertable<LocalEntityRecord> {
  final String id;
  final String userId;
  final String entityType;
  final String? parentId;
  final String? secondaryParentId;
  final String title;
  final String status;
  final double position;
  final String dataJson;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByDeviceId;
  final String? updatedByDeviceId;
  final String? lastCommandId;
  final DateTime? deletedAt;
  const LocalEntityRecord({
    required this.id,
    required this.userId,
    required this.entityType,
    this.parentId,
    this.secondaryParentId,
    required this.title,
    required this.status,
    required this.position,
    required this.dataJson,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.createdByDeviceId,
    this.updatedByDeviceId,
    this.lastCommandId,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || secondaryParentId != null) {
      map['secondary_parent_id'] = Variable<String>(secondaryParentId);
    }
    map['title'] = Variable<String>(title);
    map['status'] = Variable<String>(status);
    map['position'] = Variable<double>(position);
    map['data_json'] = Variable<String>(dataJson);
    map['revision'] = Variable<int>(revision);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || createdByDeviceId != null) {
      map['created_by_device_id'] = Variable<String>(createdByDeviceId);
    }
    if (!nullToAbsent || updatedByDeviceId != null) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId);
    }
    if (!nullToAbsent || lastCommandId != null) {
      map['last_command_id'] = Variable<String>(lastCommandId);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalEntityRecordsCompanion toCompanion(bool nullToAbsent) {
    return LocalEntityRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      entityType: Value(entityType),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      secondaryParentId: secondaryParentId == null && nullToAbsent
          ? const Value.absent()
          : Value(secondaryParentId),
      title: Value(title),
      status: Value(status),
      position: Value(position),
      dataJson: Value(dataJson),
      revision: Value(revision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      createdByDeviceId: createdByDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(createdByDeviceId),
      updatedByDeviceId: updatedByDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedByDeviceId),
      lastCommandId: lastCommandId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommandId),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalEntityRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalEntityRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      secondaryParentId: serializer.fromJson<String?>(
        json['secondaryParentId'],
      ),
      title: serializer.fromJson<String>(json['title']),
      status: serializer.fromJson<String>(json['status']),
      position: serializer.fromJson<double>(json['position']),
      dataJson: serializer.fromJson<String>(json['dataJson']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      createdByDeviceId: serializer.fromJson<String?>(
        json['createdByDeviceId'],
      ),
      updatedByDeviceId: serializer.fromJson<String?>(
        json['updatedByDeviceId'],
      ),
      lastCommandId: serializer.fromJson<String?>(json['lastCommandId']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'entityType': serializer.toJson<String>(entityType),
      'parentId': serializer.toJson<String?>(parentId),
      'secondaryParentId': serializer.toJson<String?>(secondaryParentId),
      'title': serializer.toJson<String>(title),
      'status': serializer.toJson<String>(status),
      'position': serializer.toJson<double>(position),
      'dataJson': serializer.toJson<String>(dataJson),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'createdByDeviceId': serializer.toJson<String?>(createdByDeviceId),
      'updatedByDeviceId': serializer.toJson<String?>(updatedByDeviceId),
      'lastCommandId': serializer.toJson<String?>(lastCommandId),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalEntityRecord copyWith({
    String? id,
    String? userId,
    String? entityType,
    Value<String?> parentId = const Value.absent(),
    Value<String?> secondaryParentId = const Value.absent(),
    String? title,
    String? status,
    double? position,
    String? dataJson,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> createdByDeviceId = const Value.absent(),
    Value<String?> updatedByDeviceId = const Value.absent(),
    Value<String?> lastCommandId = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalEntityRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    parentId: parentId.present ? parentId.value : this.parentId,
    secondaryParentId: secondaryParentId.present
        ? secondaryParentId.value
        : this.secondaryParentId,
    title: title ?? this.title,
    status: status ?? this.status,
    position: position ?? this.position,
    dataJson: dataJson ?? this.dataJson,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdByDeviceId: createdByDeviceId.present
        ? createdByDeviceId.value
        : this.createdByDeviceId,
    updatedByDeviceId: updatedByDeviceId.present
        ? updatedByDeviceId.value
        : this.updatedByDeviceId,
    lastCommandId: lastCommandId.present
        ? lastCommandId.value
        : this.lastCommandId,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalEntityRecord copyWithCompanion(LocalEntityRecordsCompanion data) {
    return LocalEntityRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      secondaryParentId: data.secondaryParentId.present
          ? data.secondaryParentId.value
          : this.secondaryParentId,
      title: data.title.present ? data.title.value : this.title,
      status: data.status.present ? data.status.value : this.status,
      position: data.position.present ? data.position.value : this.position,
      dataJson: data.dataJson.present ? data.dataJson.value : this.dataJson,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdByDeviceId: data.createdByDeviceId.present
          ? data.createdByDeviceId.value
          : this.createdByDeviceId,
      updatedByDeviceId: data.updatedByDeviceId.present
          ? data.updatedByDeviceId.value
          : this.updatedByDeviceId,
      lastCommandId: data.lastCommandId.present
          ? data.lastCommandId.value
          : this.lastCommandId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalEntityRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('parentId: $parentId, ')
          ..write('secondaryParentId: $secondaryParentId, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('position: $position, ')
          ..write('dataJson: $dataJson, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdByDeviceId: $createdByDeviceId, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    entityType,
    parentId,
    secondaryParentId,
    title,
    status,
    position,
    dataJson,
    revision,
    createdAt,
    updatedAt,
    createdByDeviceId,
    updatedByDeviceId,
    lastCommandId,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalEntityRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.parentId == this.parentId &&
          other.secondaryParentId == this.secondaryParentId &&
          other.title == this.title &&
          other.status == this.status &&
          other.position == this.position &&
          other.dataJson == this.dataJson &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.createdByDeviceId == this.createdByDeviceId &&
          other.updatedByDeviceId == this.updatedByDeviceId &&
          other.lastCommandId == this.lastCommandId &&
          other.deletedAt == this.deletedAt);
}

class LocalEntityRecordsCompanion extends UpdateCompanion<LocalEntityRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> entityType;
  final Value<String?> parentId;
  final Value<String?> secondaryParentId;
  final Value<String> title;
  final Value<String> status;
  final Value<double> position;
  final Value<String> dataJson;
  final Value<int> revision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> createdByDeviceId;
  final Value<String?> updatedByDeviceId;
  final Value<String?> lastCommandId;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalEntityRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.parentId = const Value.absent(),
    this.secondaryParentId = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.position = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdByDeviceId = const Value.absent(),
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalEntityRecordsCompanion.insert({
    required String id,
    required String userId,
    required String entityType,
    this.parentId = const Value.absent(),
    this.secondaryParentId = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.position = const Value.absent(),
    this.dataJson = const Value.absent(),
    this.revision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.createdByDeviceId = const Value.absent(),
    this.updatedByDeviceId = const Value.absent(),
    this.lastCommandId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       entityType = Value(entityType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalEntityRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? parentId,
    Expression<String>? secondaryParentId,
    Expression<String>? title,
    Expression<String>? status,
    Expression<double>? position,
    Expression<String>? dataJson,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? createdByDeviceId,
    Expression<String>? updatedByDeviceId,
    Expression<String>? lastCommandId,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (parentId != null) 'parent_id': parentId,
      if (secondaryParentId != null) 'secondary_parent_id': secondaryParentId,
      if (title != null) 'title': title,
      if (status != null) 'status': status,
      if (position != null) 'position': position,
      if (dataJson != null) 'data_json': dataJson,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdByDeviceId != null) 'created_by_device_id': createdByDeviceId,
      if (updatedByDeviceId != null) 'updated_by_device_id': updatedByDeviceId,
      if (lastCommandId != null) 'last_command_id': lastCommandId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalEntityRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? entityType,
    Value<String?>? parentId,
    Value<String?>? secondaryParentId,
    Value<String>? title,
    Value<String>? status,
    Value<double>? position,
    Value<String>? dataJson,
    Value<int>? revision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? createdByDeviceId,
    Value<String?>? updatedByDeviceId,
    Value<String?>? lastCommandId,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalEntityRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      parentId: parentId ?? this.parentId,
      secondaryParentId: secondaryParentId ?? this.secondaryParentId,
      title: title ?? this.title,
      status: status ?? this.status,
      position: position ?? this.position,
      dataJson: dataJson ?? this.dataJson,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByDeviceId: createdByDeviceId ?? this.createdByDeviceId,
      updatedByDeviceId: updatedByDeviceId ?? this.updatedByDeviceId,
      lastCommandId: lastCommandId ?? this.lastCommandId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (secondaryParentId.present) {
      map['secondary_parent_id'] = Variable<String>(secondaryParentId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (position.present) {
      map['position'] = Variable<double>(position.value);
    }
    if (dataJson.present) {
      map['data_json'] = Variable<String>(dataJson.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (createdByDeviceId.present) {
      map['created_by_device_id'] = Variable<String>(createdByDeviceId.value);
    }
    if (updatedByDeviceId.present) {
      map['updated_by_device_id'] = Variable<String>(updatedByDeviceId.value);
    }
    if (lastCommandId.present) {
      map['last_command_id'] = Variable<String>(lastCommandId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalEntityRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('parentId: $parentId, ')
          ..write('secondaryParentId: $secondaryParentId, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('position: $position, ')
          ..write('dataJson: $dataJson, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdByDeviceId: $createdByDeviceId, ')
          ..write('updatedByDeviceId: $updatedByDeviceId, ')
          ..write('lastCommandId: $lastCommandId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalOutboxCommandsTable extends LocalOutboxCommands
    with TableInfo<$LocalOutboxCommandsTable, LocalOutboxCommand> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalOutboxCommandsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _commandIdMeta = const VerificationMeta(
    'commandId',
  );
  @override
  late final GeneratedColumn<String> commandId = GeneratedColumn<String>(
    'command_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceSequenceMeta = const VerificationMeta(
    'deviceSequence',
  );
  @override
  late final GeneratedColumn<int> deviceSequence = GeneratedColumn<int>(
    'device_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandTypeMeta = const VerificationMeta(
    'commandType',
  );
  @override
  late final GeneratedColumn<String> commandType = GeneratedColumn<String>(
    'command_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clientTimestampMeta = const VerificationMeta(
    'clientTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> clientTimestamp =
      GeneratedColumn<DateTime>(
        'client_timestamp',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
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
  List<GeneratedColumn> get $columns => [
    commandId,
    userId,
    deviceId,
    deviceSequence,
    entityType,
    entityId,
    commandType,
    baseRevision,
    payloadJson,
    status,
    attemptCount,
    nextAttemptAt,
    lastError,
    clientTimestamp,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_outbox_commands';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalOutboxCommand> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('command_id')) {
      context.handle(
        _commandIdMeta,
        commandId.isAcceptableOrUnknown(data['command_id']!, _commandIdMeta),
      );
    } else if (isInserting) {
      context.missing(_commandIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('device_sequence')) {
      context.handle(
        _deviceSequenceMeta,
        deviceSequence.isAcceptableOrUnknown(
          data['device_sequence']!,
          _deviceSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deviceSequenceMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('command_type')) {
      context.handle(
        _commandTypeMeta,
        commandType.isAcceptableOrUnknown(
          data['command_type']!,
          _commandTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_commandTypeMeta);
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseRevisionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('client_timestamp')) {
      context.handle(
        _clientTimestampMeta,
        clientTimestamp.isAcceptableOrUnknown(
          data['client_timestamp']!,
          _clientTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientTimestampMeta);
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
  Set<GeneratedColumn> get $primaryKey => {commandId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userId, deviceId, deviceSequence},
  ];
  @override
  LocalOutboxCommand map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalOutboxCommand(
      commandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      deviceSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}device_sequence'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      commandType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_type'],
      )!,
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      clientTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_timestamp'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LocalOutboxCommandsTable createAlias(String alias) {
    return $LocalOutboxCommandsTable(attachedDatabase, alias);
  }
}

class LocalOutboxCommand extends DataClass
    implements Insertable<LocalOutboxCommand> {
  final String commandId;
  final String userId;
  final String deviceId;
  final int deviceSequence;
  final String entityType;
  final String entityId;
  final String commandType;
  final int baseRevision;
  final String payloadJson;
  final String status;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final DateTime clientTimestamp;
  final DateTime createdAt;
  const LocalOutboxCommand({
    required this.commandId,
    required this.userId,
    required this.deviceId,
    required this.deviceSequence,
    required this.entityType,
    required this.entityId,
    required this.commandType,
    required this.baseRevision,
    required this.payloadJson,
    required this.status,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastError,
    required this.clientTimestamp,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['command_id'] = Variable<String>(commandId);
    map['user_id'] = Variable<String>(userId);
    map['device_id'] = Variable<String>(deviceId);
    map['device_sequence'] = Variable<int>(deviceSequence);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['command_type'] = Variable<String>(commandType);
    map['base_revision'] = Variable<int>(baseRevision);
    map['payload_json'] = Variable<String>(payloadJson);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['client_timestamp'] = Variable<DateTime>(clientTimestamp);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LocalOutboxCommandsCompanion toCompanion(bool nullToAbsent) {
    return LocalOutboxCommandsCompanion(
      commandId: Value(commandId),
      userId: Value(userId),
      deviceId: Value(deviceId),
      deviceSequence: Value(deviceSequence),
      entityType: Value(entityType),
      entityId: Value(entityId),
      commandType: Value(commandType),
      baseRevision: Value(baseRevision),
      payloadJson: Value(payloadJson),
      status: Value(status),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      clientTimestamp: Value(clientTimestamp),
      createdAt: Value(createdAt),
    );
  }

  factory LocalOutboxCommand.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalOutboxCommand(
      commandId: serializer.fromJson<String>(json['commandId']),
      userId: serializer.fromJson<String>(json['userId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deviceSequence: serializer.fromJson<int>(json['deviceSequence']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      commandType: serializer.fromJson<String>(json['commandType']),
      baseRevision: serializer.fromJson<int>(json['baseRevision']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      clientTimestamp: serializer.fromJson<DateTime>(json['clientTimestamp']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'commandId': serializer.toJson<String>(commandId),
      'userId': serializer.toJson<String>(userId),
      'deviceId': serializer.toJson<String>(deviceId),
      'deviceSequence': serializer.toJson<int>(deviceSequence),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'commandType': serializer.toJson<String>(commandType),
      'baseRevision': serializer.toJson<int>(baseRevision),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'clientTimestamp': serializer.toJson<DateTime>(clientTimestamp),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LocalOutboxCommand copyWith({
    String? commandId,
    String? userId,
    String? deviceId,
    int? deviceSequence,
    String? entityType,
    String? entityId,
    String? commandType,
    int? baseRevision,
    String? payloadJson,
    String? status,
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? clientTimestamp,
    DateTime? createdAt,
  }) => LocalOutboxCommand(
    commandId: commandId ?? this.commandId,
    userId: userId ?? this.userId,
    deviceId: deviceId ?? this.deviceId,
    deviceSequence: deviceSequence ?? this.deviceSequence,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    commandType: commandType ?? this.commandType,
    baseRevision: baseRevision ?? this.baseRevision,
    payloadJson: payloadJson ?? this.payloadJson,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    clientTimestamp: clientTimestamp ?? this.clientTimestamp,
    createdAt: createdAt ?? this.createdAt,
  );
  LocalOutboxCommand copyWithCompanion(LocalOutboxCommandsCompanion data) {
    return LocalOutboxCommand(
      commandId: data.commandId.present ? data.commandId.value : this.commandId,
      userId: data.userId.present ? data.userId.value : this.userId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceSequence: data.deviceSequence.present
          ? data.deviceSequence.value
          : this.deviceSequence,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      commandType: data.commandType.present
          ? data.commandType.value
          : this.commandType,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      clientTimestamp: data.clientTimestamp.present
          ? data.clientTimestamp.value
          : this.clientTimestamp,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalOutboxCommand(')
          ..write('commandId: $commandId, ')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceSequence: $deviceSequence, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('commandType: $commandType, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('clientTimestamp: $clientTimestamp, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    commandId,
    userId,
    deviceId,
    deviceSequence,
    entityType,
    entityId,
    commandType,
    baseRevision,
    payloadJson,
    status,
    attemptCount,
    nextAttemptAt,
    lastError,
    clientTimestamp,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalOutboxCommand &&
          other.commandId == this.commandId &&
          other.userId == this.userId &&
          other.deviceId == this.deviceId &&
          other.deviceSequence == this.deviceSequence &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.commandType == this.commandType &&
          other.baseRevision == this.baseRevision &&
          other.payloadJson == this.payloadJson &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError &&
          other.clientTimestamp == this.clientTimestamp &&
          other.createdAt == this.createdAt);
}

class LocalOutboxCommandsCompanion extends UpdateCompanion<LocalOutboxCommand> {
  final Value<String> commandId;
  final Value<String> userId;
  final Value<String> deviceId;
  final Value<int> deviceSequence;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> commandType;
  final Value<int> baseRevision;
  final Value<String> payloadJson;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<DateTime> clientTimestamp;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalOutboxCommandsCompanion({
    this.commandId = const Value.absent(),
    this.userId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceSequence = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.commandType = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.clientTimestamp = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalOutboxCommandsCompanion.insert({
    required String commandId,
    required String userId,
    required String deviceId,
    required int deviceSequence,
    required String entityType,
    required String entityId,
    required String commandType,
    required int baseRevision,
    required String payloadJson,
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime clientTimestamp,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : commandId = Value(commandId),
       userId = Value(userId),
       deviceId = Value(deviceId),
       deviceSequence = Value(deviceSequence),
       entityType = Value(entityType),
       entityId = Value(entityId),
       commandType = Value(commandType),
       baseRevision = Value(baseRevision),
       payloadJson = Value(payloadJson),
       clientTimestamp = Value(clientTimestamp),
       createdAt = Value(createdAt);
  static Insertable<LocalOutboxCommand> custom({
    Expression<String>? commandId,
    Expression<String>? userId,
    Expression<String>? deviceId,
    Expression<int>? deviceSequence,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? commandType,
    Expression<int>? baseRevision,
    Expression<String>? payloadJson,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<DateTime>? clientTimestamp,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (commandId != null) 'command_id': commandId,
      if (userId != null) 'user_id': userId,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceSequence != null) 'device_sequence': deviceSequence,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (commandType != null) 'command_type': commandType,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (clientTimestamp != null) 'client_timestamp': clientTimestamp,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalOutboxCommandsCompanion copyWith({
    Value<String>? commandId,
    Value<String>? userId,
    Value<String>? deviceId,
    Value<int>? deviceSequence,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? commandType,
    Value<int>? baseRevision,
    Value<String>? payloadJson,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<DateTime>? clientTimestamp,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LocalOutboxCommandsCompanion(
      commandId: commandId ?? this.commandId,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      deviceSequence: deviceSequence ?? this.deviceSequence,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      commandType: commandType ?? this.commandType,
      baseRevision: baseRevision ?? this.baseRevision,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      clientTimestamp: clientTimestamp ?? this.clientTimestamp,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (commandId.present) {
      map['command_id'] = Variable<String>(commandId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceSequence.present) {
      map['device_sequence'] = Variable<int>(deviceSequence.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (commandType.present) {
      map['command_type'] = Variable<String>(commandType.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (clientTimestamp.present) {
      map['client_timestamp'] = Variable<DateTime>(clientTimestamp.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalOutboxCommandsCompanion(')
          ..write('commandId: $commandId, ')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceSequence: $deviceSequence, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('commandType: $commandType, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('clientTimestamp: $clientTimestamp, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSyncStatesTable extends LocalSyncStates
    with TableInfo<$LocalSyncStatesTable, LocalSyncState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastChangeSequenceMeta =
      const VerificationMeta('lastChangeSequence');
  @override
  late final GeneratedColumn<int> lastChangeSequence = GeneratedColumn<int>(
    'last_change_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lastChangeSequence,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSyncState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('last_change_sequence')) {
      context.handle(
        _lastChangeSequenceMeta,
        lastChangeSequence.isAcceptableOrUnknown(
          data['last_change_sequence']!,
          _lastChangeSequenceMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalSyncState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSyncState(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lastChangeSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_change_sequence'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalSyncStatesTable createAlias(String alias) {
    return $LocalSyncStatesTable(attachedDatabase, alias);
  }
}

class LocalSyncState extends DataClass implements Insertable<LocalSyncState> {
  final String id;
  final String userId;
  final int lastChangeSequence;
  final DateTime updatedAt;
  const LocalSyncState({
    required this.id,
    required this.userId,
    required this.lastChangeSequence,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['last_change_sequence'] = Variable<int>(lastChangeSequence);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalSyncStatesCompanion toCompanion(bool nullToAbsent) {
    return LocalSyncStatesCompanion(
      id: Value(id),
      userId: Value(userId),
      lastChangeSequence: Value(lastChangeSequence),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalSyncState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSyncState(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lastChangeSequence: serializer.fromJson<int>(json['lastChangeSequence']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lastChangeSequence': serializer.toJson<int>(lastChangeSequence),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalSyncState copyWith({
    String? id,
    String? userId,
    int? lastChangeSequence,
    DateTime? updatedAt,
  }) => LocalSyncState(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lastChangeSequence: lastChangeSequence ?? this.lastChangeSequence,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalSyncState copyWithCompanion(LocalSyncStatesCompanion data) {
    return LocalSyncState(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lastChangeSequence: data.lastChangeSequence.present
          ? data.lastChangeSequence.value
          : this.lastChangeSequence,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncState(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lastChangeSequence: $lastChangeSequence, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, userId, lastChangeSequence, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSyncState &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lastChangeSequence == this.lastChangeSequence &&
          other.updatedAt == this.updatedAt);
}

class LocalSyncStatesCompanion extends UpdateCompanion<LocalSyncState> {
  final Value<String> id;
  final Value<String> userId;
  final Value<int> lastChangeSequence;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalSyncStatesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lastChangeSequence = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSyncStatesCompanion.insert({
    required String id,
    required String userId,
    this.lastChangeSequence = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       updatedAt = Value(updatedAt);
  static Insertable<LocalSyncState> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<int>? lastChangeSequence,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lastChangeSequence != null)
        'last_change_sequence': lastChangeSequence,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSyncStatesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<int>? lastChangeSequence,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalSyncStatesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lastChangeSequence: lastChangeSequence ?? this.lastChangeSequence,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lastChangeSequence.present) {
      map['last_change_sequence'] = Variable<int>(lastChangeSequence.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncStatesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lastChangeSequence: $lastChangeSequence, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalProfilesTable localProfiles = $LocalProfilesTable(this);
  late final $LocalAppSettingsTable localAppSettings = $LocalAppSettingsTable(
    this,
  );
  late final $LocalDomainsTable localDomains = $LocalDomainsTable(this);
  late final $LocalTasksTable localTasks = $LocalTasksTable(this);
  late final $LocalRuntimeStatesTable localRuntimeStates =
      $LocalRuntimeStatesTable(this);
  late final $LocalRoadmapsTable localRoadmaps = $LocalRoadmapsTable(this);
  late final $LocalActivitySegmentsTable localActivitySegments =
      $LocalActivitySegmentsTable(this);
  late final $LocalAttributionsTable localAttributions =
      $LocalAttributionsTable(this);
  late final $LocalContributionsTable localContributions =
      $LocalContributionsTable(this);
  late final $LocalActivityReviewsTable localActivityReviews =
      $LocalActivityReviewsTable(this);
  late final $LocalEntityRecordsTable localEntityRecords =
      $LocalEntityRecordsTable(this);
  late final $LocalOutboxCommandsTable localOutboxCommands =
      $LocalOutboxCommandsTable(this);
  late final $LocalSyncStatesTable localSyncStates = $LocalSyncStatesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localProfiles,
    localAppSettings,
    localDomains,
    localTasks,
    localRuntimeStates,
    localRoadmaps,
    localActivitySegments,
    localAttributions,
    localContributions,
    localActivityReviews,
    localEntityRecords,
    localOutboxCommands,
    localSyncStates,
  ];
}

typedef $$LocalProfilesTableCreateCompanionBuilder =
    LocalProfilesCompanion Function({
      required String id,
      required String userId,
      Value<String> displayName,
      Value<String?> email,
      Value<String?> imagePath,
      Value<String?> genderIdentity,
      Value<DateTime?> dateOfBirth,
      Value<double?> heightCm,
      Value<bool> onboardingCompleted,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalProfilesTableUpdateCompanionBuilder =
    LocalProfilesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> displayName,
      Value<String?> email,
      Value<String?> imagePath,
      Value<String?> genderIdentity,
      Value<DateTime?> dateOfBirth,
      Value<double?> heightCm,
      Value<bool> onboardingCompleted,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalProfilesTable> {
  $$LocalProfilesTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genderIdentity => $composableBuilder(
    column: $table.genderIdentity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get heightCm => $composableBuilder(
    column: $table.heightCm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get onboardingCompleted => $composableBuilder(
    column: $table.onboardingCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalProfilesTable> {
  $$LocalProfilesTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genderIdentity => $composableBuilder(
    column: $table.genderIdentity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get heightCm => $composableBuilder(
    column: $table.heightCm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get onboardingCompleted => $composableBuilder(
    column: $table.onboardingCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalProfilesTable> {
  $$LocalProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get genderIdentity => $composableBuilder(
    column: $table.genderIdentity,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => column,
  );

  GeneratedColumn<double> get heightCm =>
      $composableBuilder(column: $table.heightCm, builder: (column) => column);

  GeneratedColumn<bool> get onboardingCompleted => $composableBuilder(
    column: $table.onboardingCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalProfilesTable,
          LocalProfile,
          $$LocalProfilesTableFilterComposer,
          $$LocalProfilesTableOrderingComposer,
          $$LocalProfilesTableAnnotationComposer,
          $$LocalProfilesTableCreateCompanionBuilder,
          $$LocalProfilesTableUpdateCompanionBuilder,
          (
            LocalProfile,
            BaseReferences<_$AppDatabase, $LocalProfilesTable, LocalProfile>,
          ),
          LocalProfile,
          PrefetchHooks Function()
        > {
  $$LocalProfilesTableTableManager(_$AppDatabase db, $LocalProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> genderIdentity = const Value.absent(),
                Value<DateTime?> dateOfBirth = const Value.absent(),
                Value<double?> heightCm = const Value.absent(),
                Value<bool> onboardingCompleted = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalProfilesCompanion(
                id: id,
                userId: userId,
                displayName: displayName,
                email: email,
                imagePath: imagePath,
                genderIdentity: genderIdentity,
                dateOfBirth: dateOfBirth,
                heightCm: heightCm,
                onboardingCompleted: onboardingCompleted,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<String> displayName = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> genderIdentity = const Value.absent(),
                Value<DateTime?> dateOfBirth = const Value.absent(),
                Value<double?> heightCm = const Value.absent(),
                Value<bool> onboardingCompleted = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalProfilesCompanion.insert(
                id: id,
                userId: userId,
                displayName: displayName,
                email: email,
                imagePath: imagePath,
                genderIdentity: genderIdentity,
                dateOfBirth: dateOfBirth,
                heightCm: heightCm,
                onboardingCompleted: onboardingCompleted,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalProfilesTable,
      LocalProfile,
      $$LocalProfilesTableFilterComposer,
      $$LocalProfilesTableOrderingComposer,
      $$LocalProfilesTableAnnotationComposer,
      $$LocalProfilesTableCreateCompanionBuilder,
      $$LocalProfilesTableUpdateCompanionBuilder,
      (
        LocalProfile,
        BaseReferences<_$AppDatabase, $LocalProfilesTable, LocalProfile>,
      ),
      LocalProfile,
      PrefetchHooks Function()
    >;
typedef $$LocalAppSettingsTableCreateCompanionBuilder =
    LocalAppSettingsCompanion Function({
      required String id,
      Value<String> userId,
      Value<String> localeCode,
      Value<String> themeKey,
      Value<int> accentColor,
      Value<String> timeZone,
      Value<bool> useDeviceTimeZone,
      Value<String> clockFormat,
      Value<String> notificationSoundKey,
      Value<bool> healthConnectEnabled,
      Value<bool> cycleTrackingEnabled,
      Value<String> cycleStorageMode,
      Value<bool> calendarShowCompleted,
      Value<bool> applicationTrackingEnabled,
      Value<bool> windowTitleTrackingEnabled,
      Value<bool> idleDetectionEnabled,
      Value<int> idleThresholdSeconds,
      Value<bool> detectBreakActivity,
      Value<bool> detectCrossTaskActivity,
      Value<bool> retainUnclassifiedActivity,
      Value<bool> retainTechnicalIdle,
      Value<bool> automaticTrustedRules,
      Value<bool> activitySyncEnabled,
      Value<bool> activityRuleSyncEnabled,
      Value<bool> detailedActivitySyncEnabled,
      Value<int> localActivityRetentionDays,
      Value<bool> hideConfirmedSystemActivity,
      Value<bool> showPossibleSystemActivity,
      Value<double> automaticConfidenceThreshold,
      Value<int> minimumSuggestionDurationMs,
      Value<int> wakeTimeMinutes,
      Value<int> sleepTimeMinutes,
      Value<String> workingDaysJson,
      Value<int> workStartMinutes,
      Value<int> workEndMinutes,
      Value<bool> workScheduleEnabled,
      Value<String> workScheduleRotationJson,
      Value<String> workScheduleAnchorDate,
      Value<bool> workReminderEnabled,
      Value<int> workReminderOffsetMinutes,
      Value<bool> workPomodoroEnabled,
      Value<bool> workActivityCreditEnabled,
      Value<int> quietStartMinutes,
      Value<int> quietEndMinutes,
      Value<bool> sleepReminderEnabled,
      Value<int> sleepReminderOffsetMinutes,
      Value<bool> phoneUsageAnalysisEnabled,
      Value<String> coachingSensitivity,
      Value<String> coachingTone,
      Value<bool> healthSummarySyncEnabled,
      Value<String> healthReportPrivacy,
      Value<String> notificationPreferencesJson,
      Value<String> countryCode,
      Value<String> dateFormat,
      Value<int> firstDayOfWeek,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalAppSettingsTableUpdateCompanionBuilder =
    LocalAppSettingsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> localeCode,
      Value<String> themeKey,
      Value<int> accentColor,
      Value<String> timeZone,
      Value<bool> useDeviceTimeZone,
      Value<String> clockFormat,
      Value<String> notificationSoundKey,
      Value<bool> healthConnectEnabled,
      Value<bool> cycleTrackingEnabled,
      Value<String> cycleStorageMode,
      Value<bool> calendarShowCompleted,
      Value<bool> applicationTrackingEnabled,
      Value<bool> windowTitleTrackingEnabled,
      Value<bool> idleDetectionEnabled,
      Value<int> idleThresholdSeconds,
      Value<bool> detectBreakActivity,
      Value<bool> detectCrossTaskActivity,
      Value<bool> retainUnclassifiedActivity,
      Value<bool> retainTechnicalIdle,
      Value<bool> automaticTrustedRules,
      Value<bool> activitySyncEnabled,
      Value<bool> activityRuleSyncEnabled,
      Value<bool> detailedActivitySyncEnabled,
      Value<int> localActivityRetentionDays,
      Value<bool> hideConfirmedSystemActivity,
      Value<bool> showPossibleSystemActivity,
      Value<double> automaticConfidenceThreshold,
      Value<int> minimumSuggestionDurationMs,
      Value<int> wakeTimeMinutes,
      Value<int> sleepTimeMinutes,
      Value<String> workingDaysJson,
      Value<int> workStartMinutes,
      Value<int> workEndMinutes,
      Value<bool> workScheduleEnabled,
      Value<String> workScheduleRotationJson,
      Value<String> workScheduleAnchorDate,
      Value<bool> workReminderEnabled,
      Value<int> workReminderOffsetMinutes,
      Value<bool> workPomodoroEnabled,
      Value<bool> workActivityCreditEnabled,
      Value<int> quietStartMinutes,
      Value<int> quietEndMinutes,
      Value<bool> sleepReminderEnabled,
      Value<int> sleepReminderOffsetMinutes,
      Value<bool> phoneUsageAnalysisEnabled,
      Value<String> coachingSensitivity,
      Value<String> coachingTone,
      Value<bool> healthSummarySyncEnabled,
      Value<String> healthReportPrivacy,
      Value<String> notificationPreferencesJson,
      Value<String> countryCode,
      Value<String> dateFormat,
      Value<int> firstDayOfWeek,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalAppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalAppSettingsTable> {
  $$LocalAppSettingsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localeCode => $composableBuilder(
    column: $table.localeCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get themeKey => $composableBuilder(
    column: $table.themeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accentColor => $composableBuilder(
    column: $table.accentColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeZone => $composableBuilder(
    column: $table.timeZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get useDeviceTimeZone => $composableBuilder(
    column: $table.useDeviceTimeZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clockFormat => $composableBuilder(
    column: $table.clockFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notificationSoundKey => $composableBuilder(
    column: $table.notificationSoundKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get healthConnectEnabled => $composableBuilder(
    column: $table.healthConnectEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cycleTrackingEnabled => $composableBuilder(
    column: $table.cycleTrackingEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cycleStorageMode => $composableBuilder(
    column: $table.cycleStorageMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get calendarShowCompleted => $composableBuilder(
    column: $table.calendarShowCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get applicationTrackingEnabled => $composableBuilder(
    column: $table.applicationTrackingEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get windowTitleTrackingEnabled => $composableBuilder(
    column: $table.windowTitleTrackingEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get idleDetectionEnabled => $composableBuilder(
    column: $table.idleDetectionEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get idleThresholdSeconds => $composableBuilder(
    column: $table.idleThresholdSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get detectBreakActivity => $composableBuilder(
    column: $table.detectBreakActivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get detectCrossTaskActivity => $composableBuilder(
    column: $table.detectCrossTaskActivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get retainUnclassifiedActivity => $composableBuilder(
    column: $table.retainUnclassifiedActivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get retainTechnicalIdle => $composableBuilder(
    column: $table.retainTechnicalIdle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get automaticTrustedRules => $composableBuilder(
    column: $table.automaticTrustedRules,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activitySyncEnabled => $composableBuilder(
    column: $table.activitySyncEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activityRuleSyncEnabled => $composableBuilder(
    column: $table.activityRuleSyncEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get detailedActivitySyncEnabled => $composableBuilder(
    column: $table.detailedActivitySyncEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localActivityRetentionDays => $composableBuilder(
    column: $table.localActivityRetentionDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hideConfirmedSystemActivity => $composableBuilder(
    column: $table.hideConfirmedSystemActivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showPossibleSystemActivity => $composableBuilder(
    column: $table.showPossibleSystemActivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get automaticConfidenceThreshold => $composableBuilder(
    column: $table.automaticConfidenceThreshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minimumSuggestionDurationMs => $composableBuilder(
    column: $table.minimumSuggestionDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wakeTimeMinutes => $composableBuilder(
    column: $table.wakeTimeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sleepTimeMinutes => $composableBuilder(
    column: $table.sleepTimeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workingDaysJson => $composableBuilder(
    column: $table.workingDaysJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get workStartMinutes => $composableBuilder(
    column: $table.workStartMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get workEndMinutes => $composableBuilder(
    column: $table.workEndMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get workScheduleEnabled => $composableBuilder(
    column: $table.workScheduleEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workScheduleRotationJson => $composableBuilder(
    column: $table.workScheduleRotationJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workScheduleAnchorDate => $composableBuilder(
    column: $table.workScheduleAnchorDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get workReminderEnabled => $composableBuilder(
    column: $table.workReminderEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get workReminderOffsetMinutes => $composableBuilder(
    column: $table.workReminderOffsetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get workPomodoroEnabled => $composableBuilder(
    column: $table.workPomodoroEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get workActivityCreditEnabled => $composableBuilder(
    column: $table.workActivityCreditEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quietStartMinutes => $composableBuilder(
    column: $table.quietStartMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quietEndMinutes => $composableBuilder(
    column: $table.quietEndMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sleepReminderEnabled => $composableBuilder(
    column: $table.sleepReminderEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sleepReminderOffsetMinutes => $composableBuilder(
    column: $table.sleepReminderOffsetMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get phoneUsageAnalysisEnabled => $composableBuilder(
    column: $table.phoneUsageAnalysisEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coachingSensitivity => $composableBuilder(
    column: $table.coachingSensitivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coachingTone => $composableBuilder(
    column: $table.coachingTone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get healthSummarySyncEnabled => $composableBuilder(
    column: $table.healthSummarySyncEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get healthReportPrivacy => $composableBuilder(
    column: $table.healthReportPrivacy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notificationPreferencesJson => $composableBuilder(
    column: $table.notificationPreferencesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countryCode => $composableBuilder(
    column: $table.countryCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dateFormat => $composableBuilder(
    column: $table.dateFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstDayOfWeek => $composableBuilder(
    column: $table.firstDayOfWeek,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalAppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalAppSettingsTable> {
  $$LocalAppSettingsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localeCode => $composableBuilder(
    column: $table.localeCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeKey => $composableBuilder(
    column: $table.themeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accentColor => $composableBuilder(
    column: $table.accentColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeZone => $composableBuilder(
    column: $table.timeZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get useDeviceTimeZone => $composableBuilder(
    column: $table.useDeviceTimeZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clockFormat => $composableBuilder(
    column: $table.clockFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notificationSoundKey => $composableBuilder(
    column: $table.notificationSoundKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get healthConnectEnabled => $composableBuilder(
    column: $table.healthConnectEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cycleTrackingEnabled => $composableBuilder(
    column: $table.cycleTrackingEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cycleStorageMode => $composableBuilder(
    column: $table.cycleStorageMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get calendarShowCompleted => $composableBuilder(
    column: $table.calendarShowCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get applicationTrackingEnabled => $composableBuilder(
    column: $table.applicationTrackingEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get windowTitleTrackingEnabled => $composableBuilder(
    column: $table.windowTitleTrackingEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get idleDetectionEnabled => $composableBuilder(
    column: $table.idleDetectionEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get idleThresholdSeconds => $composableBuilder(
    column: $table.idleThresholdSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get detectBreakActivity => $composableBuilder(
    column: $table.detectBreakActivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get detectCrossTaskActivity => $composableBuilder(
    column: $table.detectCrossTaskActivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get retainUnclassifiedActivity => $composableBuilder(
    column: $table.retainUnclassifiedActivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get retainTechnicalIdle => $composableBuilder(
    column: $table.retainTechnicalIdle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get automaticTrustedRules => $composableBuilder(
    column: $table.automaticTrustedRules,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activitySyncEnabled => $composableBuilder(
    column: $table.activitySyncEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activityRuleSyncEnabled => $composableBuilder(
    column: $table.activityRuleSyncEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get detailedActivitySyncEnabled => $composableBuilder(
    column: $table.detailedActivitySyncEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localActivityRetentionDays => $composableBuilder(
    column: $table.localActivityRetentionDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hideConfirmedSystemActivity => $composableBuilder(
    column: $table.hideConfirmedSystemActivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showPossibleSystemActivity => $composableBuilder(
    column: $table.showPossibleSystemActivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get automaticConfidenceThreshold =>
      $composableBuilder(
        column: $table.automaticConfidenceThreshold,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<int> get minimumSuggestionDurationMs => $composableBuilder(
    column: $table.minimumSuggestionDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wakeTimeMinutes => $composableBuilder(
    column: $table.wakeTimeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sleepTimeMinutes => $composableBuilder(
    column: $table.sleepTimeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workingDaysJson => $composableBuilder(
    column: $table.workingDaysJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get workStartMinutes => $composableBuilder(
    column: $table.workStartMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get workEndMinutes => $composableBuilder(
    column: $table.workEndMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get workScheduleEnabled => $composableBuilder(
    column: $table.workScheduleEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workScheduleRotationJson => $composableBuilder(
    column: $table.workScheduleRotationJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workScheduleAnchorDate => $composableBuilder(
    column: $table.workScheduleAnchorDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get workReminderEnabled => $composableBuilder(
    column: $table.workReminderEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get workReminderOffsetMinutes => $composableBuilder(
    column: $table.workReminderOffsetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get workPomodoroEnabled => $composableBuilder(
    column: $table.workPomodoroEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get workActivityCreditEnabled => $composableBuilder(
    column: $table.workActivityCreditEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quietStartMinutes => $composableBuilder(
    column: $table.quietStartMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quietEndMinutes => $composableBuilder(
    column: $table.quietEndMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sleepReminderEnabled => $composableBuilder(
    column: $table.sleepReminderEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sleepReminderOffsetMinutes => $composableBuilder(
    column: $table.sleepReminderOffsetMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get phoneUsageAnalysisEnabled => $composableBuilder(
    column: $table.phoneUsageAnalysisEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coachingSensitivity => $composableBuilder(
    column: $table.coachingSensitivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coachingTone => $composableBuilder(
    column: $table.coachingTone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get healthSummarySyncEnabled => $composableBuilder(
    column: $table.healthSummarySyncEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get healthReportPrivacy => $composableBuilder(
    column: $table.healthReportPrivacy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notificationPreferencesJson => $composableBuilder(
    column: $table.notificationPreferencesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countryCode => $composableBuilder(
    column: $table.countryCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dateFormat => $composableBuilder(
    column: $table.dateFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstDayOfWeek => $composableBuilder(
    column: $table.firstDayOfWeek,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalAppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalAppSettingsTable> {
  $$LocalAppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get localeCode => $composableBuilder(
    column: $table.localeCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get themeKey =>
      $composableBuilder(column: $table.themeKey, builder: (column) => column);

  GeneratedColumn<int> get accentColor => $composableBuilder(
    column: $table.accentColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timeZone =>
      $composableBuilder(column: $table.timeZone, builder: (column) => column);

  GeneratedColumn<bool> get useDeviceTimeZone => $composableBuilder(
    column: $table.useDeviceTimeZone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clockFormat => $composableBuilder(
    column: $table.clockFormat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notificationSoundKey => $composableBuilder(
    column: $table.notificationSoundKey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get healthConnectEnabled => $composableBuilder(
    column: $table.healthConnectEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get cycleTrackingEnabled => $composableBuilder(
    column: $table.cycleTrackingEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cycleStorageMode => $composableBuilder(
    column: $table.cycleStorageMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get calendarShowCompleted => $composableBuilder(
    column: $table.calendarShowCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get applicationTrackingEnabled => $composableBuilder(
    column: $table.applicationTrackingEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get windowTitleTrackingEnabled => $composableBuilder(
    column: $table.windowTitleTrackingEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get idleDetectionEnabled => $composableBuilder(
    column: $table.idleDetectionEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get idleThresholdSeconds => $composableBuilder(
    column: $table.idleThresholdSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get detectBreakActivity => $composableBuilder(
    column: $table.detectBreakActivity,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get detectCrossTaskActivity => $composableBuilder(
    column: $table.detectCrossTaskActivity,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get retainUnclassifiedActivity => $composableBuilder(
    column: $table.retainUnclassifiedActivity,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get retainTechnicalIdle => $composableBuilder(
    column: $table.retainTechnicalIdle,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get automaticTrustedRules => $composableBuilder(
    column: $table.automaticTrustedRules,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activitySyncEnabled => $composableBuilder(
    column: $table.activitySyncEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activityRuleSyncEnabled => $composableBuilder(
    column: $table.activityRuleSyncEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get detailedActivitySyncEnabled => $composableBuilder(
    column: $table.detailedActivitySyncEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localActivityRetentionDays => $composableBuilder(
    column: $table.localActivityRetentionDays,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hideConfirmedSystemActivity => $composableBuilder(
    column: $table.hideConfirmedSystemActivity,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get showPossibleSystemActivity => $composableBuilder(
    column: $table.showPossibleSystemActivity,
    builder: (column) => column,
  );

  GeneratedColumn<double> get automaticConfidenceThreshold =>
      $composableBuilder(
        column: $table.automaticConfidenceThreshold,
        builder: (column) => column,
      );

  GeneratedColumn<int> get minimumSuggestionDurationMs => $composableBuilder(
    column: $table.minimumSuggestionDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wakeTimeMinutes => $composableBuilder(
    column: $table.wakeTimeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sleepTimeMinutes => $composableBuilder(
    column: $table.sleepTimeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workingDaysJson => $composableBuilder(
    column: $table.workingDaysJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get workStartMinutes => $composableBuilder(
    column: $table.workStartMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get workEndMinutes => $composableBuilder(
    column: $table.workEndMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get workScheduleEnabled => $composableBuilder(
    column: $table.workScheduleEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workScheduleRotationJson => $composableBuilder(
    column: $table.workScheduleRotationJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workScheduleAnchorDate => $composableBuilder(
    column: $table.workScheduleAnchorDate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get workReminderEnabled => $composableBuilder(
    column: $table.workReminderEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get workReminderOffsetMinutes => $composableBuilder(
    column: $table.workReminderOffsetMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get workPomodoroEnabled => $composableBuilder(
    column: $table.workPomodoroEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get workActivityCreditEnabled => $composableBuilder(
    column: $table.workActivityCreditEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quietStartMinutes => $composableBuilder(
    column: $table.quietStartMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quietEndMinutes => $composableBuilder(
    column: $table.quietEndMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get sleepReminderEnabled => $composableBuilder(
    column: $table.sleepReminderEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sleepReminderOffsetMinutes => $composableBuilder(
    column: $table.sleepReminderOffsetMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get phoneUsageAnalysisEnabled => $composableBuilder(
    column: $table.phoneUsageAnalysisEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coachingSensitivity => $composableBuilder(
    column: $table.coachingSensitivity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coachingTone => $composableBuilder(
    column: $table.coachingTone,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get healthSummarySyncEnabled => $composableBuilder(
    column: $table.healthSummarySyncEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get healthReportPrivacy => $composableBuilder(
    column: $table.healthReportPrivacy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notificationPreferencesJson => $composableBuilder(
    column: $table.notificationPreferencesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get countryCode => $composableBuilder(
    column: $table.countryCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dateFormat => $composableBuilder(
    column: $table.dateFormat,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstDayOfWeek => $composableBuilder(
    column: $table.firstDayOfWeek,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalAppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalAppSettingsTable,
          LocalAppSetting,
          $$LocalAppSettingsTableFilterComposer,
          $$LocalAppSettingsTableOrderingComposer,
          $$LocalAppSettingsTableAnnotationComposer,
          $$LocalAppSettingsTableCreateCompanionBuilder,
          $$LocalAppSettingsTableUpdateCompanionBuilder,
          (
            LocalAppSetting,
            BaseReferences<
              _$AppDatabase,
              $LocalAppSettingsTable,
              LocalAppSetting
            >,
          ),
          LocalAppSetting,
          PrefetchHooks Function()
        > {
  $$LocalAppSettingsTableTableManager(
    _$AppDatabase db,
    $LocalAppSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> localeCode = const Value.absent(),
                Value<String> themeKey = const Value.absent(),
                Value<int> accentColor = const Value.absent(),
                Value<String> timeZone = const Value.absent(),
                Value<bool> useDeviceTimeZone = const Value.absent(),
                Value<String> clockFormat = const Value.absent(),
                Value<String> notificationSoundKey = const Value.absent(),
                Value<bool> healthConnectEnabled = const Value.absent(),
                Value<bool> cycleTrackingEnabled = const Value.absent(),
                Value<String> cycleStorageMode = const Value.absent(),
                Value<bool> calendarShowCompleted = const Value.absent(),
                Value<bool> applicationTrackingEnabled = const Value.absent(),
                Value<bool> windowTitleTrackingEnabled = const Value.absent(),
                Value<bool> idleDetectionEnabled = const Value.absent(),
                Value<int> idleThresholdSeconds = const Value.absent(),
                Value<bool> detectBreakActivity = const Value.absent(),
                Value<bool> detectCrossTaskActivity = const Value.absent(),
                Value<bool> retainUnclassifiedActivity = const Value.absent(),
                Value<bool> retainTechnicalIdle = const Value.absent(),
                Value<bool> automaticTrustedRules = const Value.absent(),
                Value<bool> activitySyncEnabled = const Value.absent(),
                Value<bool> activityRuleSyncEnabled = const Value.absent(),
                Value<bool> detailedActivitySyncEnabled = const Value.absent(),
                Value<int> localActivityRetentionDays = const Value.absent(),
                Value<bool> hideConfirmedSystemActivity = const Value.absent(),
                Value<bool> showPossibleSystemActivity = const Value.absent(),
                Value<double> automaticConfidenceThreshold =
                    const Value.absent(),
                Value<int> minimumSuggestionDurationMs = const Value.absent(),
                Value<int> wakeTimeMinutes = const Value.absent(),
                Value<int> sleepTimeMinutes = const Value.absent(),
                Value<String> workingDaysJson = const Value.absent(),
                Value<int> workStartMinutes = const Value.absent(),
                Value<int> workEndMinutes = const Value.absent(),
                Value<bool> workScheduleEnabled = const Value.absent(),
                Value<String> workScheduleRotationJson = const Value.absent(),
                Value<String> workScheduleAnchorDate = const Value.absent(),
                Value<bool> workReminderEnabled = const Value.absent(),
                Value<int> workReminderOffsetMinutes = const Value.absent(),
                Value<bool> workPomodoroEnabled = const Value.absent(),
                Value<bool> workActivityCreditEnabled = const Value.absent(),
                Value<int> quietStartMinutes = const Value.absent(),
                Value<int> quietEndMinutes = const Value.absent(),
                Value<bool> sleepReminderEnabled = const Value.absent(),
                Value<int> sleepReminderOffsetMinutes = const Value.absent(),
                Value<bool> phoneUsageAnalysisEnabled = const Value.absent(),
                Value<String> coachingSensitivity = const Value.absent(),
                Value<String> coachingTone = const Value.absent(),
                Value<bool> healthSummarySyncEnabled = const Value.absent(),
                Value<String> healthReportPrivacy = const Value.absent(),
                Value<String> notificationPreferencesJson =
                    const Value.absent(),
                Value<String> countryCode = const Value.absent(),
                Value<String> dateFormat = const Value.absent(),
                Value<int> firstDayOfWeek = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAppSettingsCompanion(
                id: id,
                userId: userId,
                localeCode: localeCode,
                themeKey: themeKey,
                accentColor: accentColor,
                timeZone: timeZone,
                useDeviceTimeZone: useDeviceTimeZone,
                clockFormat: clockFormat,
                notificationSoundKey: notificationSoundKey,
                healthConnectEnabled: healthConnectEnabled,
                cycleTrackingEnabled: cycleTrackingEnabled,
                cycleStorageMode: cycleStorageMode,
                calendarShowCompleted: calendarShowCompleted,
                applicationTrackingEnabled: applicationTrackingEnabled,
                windowTitleTrackingEnabled: windowTitleTrackingEnabled,
                idleDetectionEnabled: idleDetectionEnabled,
                idleThresholdSeconds: idleThresholdSeconds,
                detectBreakActivity: detectBreakActivity,
                detectCrossTaskActivity: detectCrossTaskActivity,
                retainUnclassifiedActivity: retainUnclassifiedActivity,
                retainTechnicalIdle: retainTechnicalIdle,
                automaticTrustedRules: automaticTrustedRules,
                activitySyncEnabled: activitySyncEnabled,
                activityRuleSyncEnabled: activityRuleSyncEnabled,
                detailedActivitySyncEnabled: detailedActivitySyncEnabled,
                localActivityRetentionDays: localActivityRetentionDays,
                hideConfirmedSystemActivity: hideConfirmedSystemActivity,
                showPossibleSystemActivity: showPossibleSystemActivity,
                automaticConfidenceThreshold: automaticConfidenceThreshold,
                minimumSuggestionDurationMs: minimumSuggestionDurationMs,
                wakeTimeMinutes: wakeTimeMinutes,
                sleepTimeMinutes: sleepTimeMinutes,
                workingDaysJson: workingDaysJson,
                workStartMinutes: workStartMinutes,
                workEndMinutes: workEndMinutes,
                workScheduleEnabled: workScheduleEnabled,
                workScheduleRotationJson: workScheduleRotationJson,
                workScheduleAnchorDate: workScheduleAnchorDate,
                workReminderEnabled: workReminderEnabled,
                workReminderOffsetMinutes: workReminderOffsetMinutes,
                workPomodoroEnabled: workPomodoroEnabled,
                workActivityCreditEnabled: workActivityCreditEnabled,
                quietStartMinutes: quietStartMinutes,
                quietEndMinutes: quietEndMinutes,
                sleepReminderEnabled: sleepReminderEnabled,
                sleepReminderOffsetMinutes: sleepReminderOffsetMinutes,
                phoneUsageAnalysisEnabled: phoneUsageAnalysisEnabled,
                coachingSensitivity: coachingSensitivity,
                coachingTone: coachingTone,
                healthSummarySyncEnabled: healthSummarySyncEnabled,
                healthReportPrivacy: healthReportPrivacy,
                notificationPreferencesJson: notificationPreferencesJson,
                countryCode: countryCode,
                dateFormat: dateFormat,
                firstDayOfWeek: firstDayOfWeek,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> userId = const Value.absent(),
                Value<String> localeCode = const Value.absent(),
                Value<String> themeKey = const Value.absent(),
                Value<int> accentColor = const Value.absent(),
                Value<String> timeZone = const Value.absent(),
                Value<bool> useDeviceTimeZone = const Value.absent(),
                Value<String> clockFormat = const Value.absent(),
                Value<String> notificationSoundKey = const Value.absent(),
                Value<bool> healthConnectEnabled = const Value.absent(),
                Value<bool> cycleTrackingEnabled = const Value.absent(),
                Value<String> cycleStorageMode = const Value.absent(),
                Value<bool> calendarShowCompleted = const Value.absent(),
                Value<bool> applicationTrackingEnabled = const Value.absent(),
                Value<bool> windowTitleTrackingEnabled = const Value.absent(),
                Value<bool> idleDetectionEnabled = const Value.absent(),
                Value<int> idleThresholdSeconds = const Value.absent(),
                Value<bool> detectBreakActivity = const Value.absent(),
                Value<bool> detectCrossTaskActivity = const Value.absent(),
                Value<bool> retainUnclassifiedActivity = const Value.absent(),
                Value<bool> retainTechnicalIdle = const Value.absent(),
                Value<bool> automaticTrustedRules = const Value.absent(),
                Value<bool> activitySyncEnabled = const Value.absent(),
                Value<bool> activityRuleSyncEnabled = const Value.absent(),
                Value<bool> detailedActivitySyncEnabled = const Value.absent(),
                Value<int> localActivityRetentionDays = const Value.absent(),
                Value<bool> hideConfirmedSystemActivity = const Value.absent(),
                Value<bool> showPossibleSystemActivity = const Value.absent(),
                Value<double> automaticConfidenceThreshold =
                    const Value.absent(),
                Value<int> minimumSuggestionDurationMs = const Value.absent(),
                Value<int> wakeTimeMinutes = const Value.absent(),
                Value<int> sleepTimeMinutes = const Value.absent(),
                Value<String> workingDaysJson = const Value.absent(),
                Value<int> workStartMinutes = const Value.absent(),
                Value<int> workEndMinutes = const Value.absent(),
                Value<bool> workScheduleEnabled = const Value.absent(),
                Value<String> workScheduleRotationJson = const Value.absent(),
                Value<String> workScheduleAnchorDate = const Value.absent(),
                Value<bool> workReminderEnabled = const Value.absent(),
                Value<int> workReminderOffsetMinutes = const Value.absent(),
                Value<bool> workPomodoroEnabled = const Value.absent(),
                Value<bool> workActivityCreditEnabled = const Value.absent(),
                Value<int> quietStartMinutes = const Value.absent(),
                Value<int> quietEndMinutes = const Value.absent(),
                Value<bool> sleepReminderEnabled = const Value.absent(),
                Value<int> sleepReminderOffsetMinutes = const Value.absent(),
                Value<bool> phoneUsageAnalysisEnabled = const Value.absent(),
                Value<String> coachingSensitivity = const Value.absent(),
                Value<String> coachingTone = const Value.absent(),
                Value<bool> healthSummarySyncEnabled = const Value.absent(),
                Value<String> healthReportPrivacy = const Value.absent(),
                Value<String> notificationPreferencesJson =
                    const Value.absent(),
                Value<String> countryCode = const Value.absent(),
                Value<String> dateFormat = const Value.absent(),
                Value<int> firstDayOfWeek = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAppSettingsCompanion.insert(
                id: id,
                userId: userId,
                localeCode: localeCode,
                themeKey: themeKey,
                accentColor: accentColor,
                timeZone: timeZone,
                useDeviceTimeZone: useDeviceTimeZone,
                clockFormat: clockFormat,
                notificationSoundKey: notificationSoundKey,
                healthConnectEnabled: healthConnectEnabled,
                cycleTrackingEnabled: cycleTrackingEnabled,
                cycleStorageMode: cycleStorageMode,
                calendarShowCompleted: calendarShowCompleted,
                applicationTrackingEnabled: applicationTrackingEnabled,
                windowTitleTrackingEnabled: windowTitleTrackingEnabled,
                idleDetectionEnabled: idleDetectionEnabled,
                idleThresholdSeconds: idleThresholdSeconds,
                detectBreakActivity: detectBreakActivity,
                detectCrossTaskActivity: detectCrossTaskActivity,
                retainUnclassifiedActivity: retainUnclassifiedActivity,
                retainTechnicalIdle: retainTechnicalIdle,
                automaticTrustedRules: automaticTrustedRules,
                activitySyncEnabled: activitySyncEnabled,
                activityRuleSyncEnabled: activityRuleSyncEnabled,
                detailedActivitySyncEnabled: detailedActivitySyncEnabled,
                localActivityRetentionDays: localActivityRetentionDays,
                hideConfirmedSystemActivity: hideConfirmedSystemActivity,
                showPossibleSystemActivity: showPossibleSystemActivity,
                automaticConfidenceThreshold: automaticConfidenceThreshold,
                minimumSuggestionDurationMs: minimumSuggestionDurationMs,
                wakeTimeMinutes: wakeTimeMinutes,
                sleepTimeMinutes: sleepTimeMinutes,
                workingDaysJson: workingDaysJson,
                workStartMinutes: workStartMinutes,
                workEndMinutes: workEndMinutes,
                workScheduleEnabled: workScheduleEnabled,
                workScheduleRotationJson: workScheduleRotationJson,
                workScheduleAnchorDate: workScheduleAnchorDate,
                workReminderEnabled: workReminderEnabled,
                workReminderOffsetMinutes: workReminderOffsetMinutes,
                workPomodoroEnabled: workPomodoroEnabled,
                workActivityCreditEnabled: workActivityCreditEnabled,
                quietStartMinutes: quietStartMinutes,
                quietEndMinutes: quietEndMinutes,
                sleepReminderEnabled: sleepReminderEnabled,
                sleepReminderOffsetMinutes: sleepReminderOffsetMinutes,
                phoneUsageAnalysisEnabled: phoneUsageAnalysisEnabled,
                coachingSensitivity: coachingSensitivity,
                coachingTone: coachingTone,
                healthSummarySyncEnabled: healthSummarySyncEnabled,
                healthReportPrivacy: healthReportPrivacy,
                notificationPreferencesJson: notificationPreferencesJson,
                countryCode: countryCode,
                dateFormat: dateFormat,
                firstDayOfWeek: firstDayOfWeek,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalAppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalAppSettingsTable,
      LocalAppSetting,
      $$LocalAppSettingsTableFilterComposer,
      $$LocalAppSettingsTableOrderingComposer,
      $$LocalAppSettingsTableAnnotationComposer,
      $$LocalAppSettingsTableCreateCompanionBuilder,
      $$LocalAppSettingsTableUpdateCompanionBuilder,
      (
        LocalAppSetting,
        BaseReferences<_$AppDatabase, $LocalAppSettingsTable, LocalAppSetting>,
      ),
      LocalAppSetting,
      PrefetchHooks Function()
    >;
typedef $$LocalDomainsTableCreateCompanionBuilder =
    LocalDomainsCompanion Function({
      required String id,
      required String userId,
      required String name,
      Value<String> iconName,
      required int colorValue,
      Value<double> position,
      Value<DateTime?> archivedAt,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> createdByDeviceId,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalDomainsTableUpdateCompanionBuilder =
    LocalDomainsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<String> iconName,
      Value<int> colorValue,
      Value<double> position,
      Value<DateTime?> archivedAt,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> createdByDeviceId,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalDomainsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalDomainsTable> {
  $$LocalDomainsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconName => $composableBuilder(
    column: $table.iconName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalDomainsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalDomainsTable> {
  $$LocalDomainsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconName => $composableBuilder(
    column: $table.iconName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalDomainsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalDomainsTable> {
  $$LocalDomainsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get iconName =>
      $composableBuilder(column: $table.iconName, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalDomainsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalDomainsTable,
          LocalDomain,
          $$LocalDomainsTableFilterComposer,
          $$LocalDomainsTableOrderingComposer,
          $$LocalDomainsTableAnnotationComposer,
          $$LocalDomainsTableCreateCompanionBuilder,
          $$LocalDomainsTableUpdateCompanionBuilder,
          (
            LocalDomain,
            BaseReferences<_$AppDatabase, $LocalDomainsTable, LocalDomain>,
          ),
          LocalDomain,
          PrefetchHooks Function()
        > {
  $$LocalDomainsTableTableManager(_$AppDatabase db, $LocalDomainsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalDomainsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalDomainsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalDomainsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> iconName = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<double> position = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> createdByDeviceId = const Value.absent(),
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDomainsCompanion(
                id: id,
                userId: userId,
                name: name,
                iconName: iconName,
                colorValue: colorValue,
                position: position,
                archivedAt: archivedAt,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                createdByDeviceId: createdByDeviceId,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                Value<String> iconName = const Value.absent(),
                required int colorValue,
                Value<double> position = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> createdByDeviceId = const Value.absent(),
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDomainsCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                iconName: iconName,
                colorValue: colorValue,
                position: position,
                archivedAt: archivedAt,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                createdByDeviceId: createdByDeviceId,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalDomainsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalDomainsTable,
      LocalDomain,
      $$LocalDomainsTableFilterComposer,
      $$LocalDomainsTableOrderingComposer,
      $$LocalDomainsTableAnnotationComposer,
      $$LocalDomainsTableCreateCompanionBuilder,
      $$LocalDomainsTableUpdateCompanionBuilder,
      (
        LocalDomain,
        BaseReferences<_$AppDatabase, $LocalDomainsTable, LocalDomain>,
      ),
      LocalDomain,
      PrefetchHooks Function()
    >;
typedef $$LocalTasksTableCreateCompanionBuilder =
    LocalTasksCompanion Function({
      required String id,
      required String userId,
      Value<String?> templateId,
      required String title,
      Value<String> description,
      Value<String?> domainId,
      Value<String> status,
      Value<int> priority,
      Value<String> executionMode,
      Value<DateTime?> scheduledDate,
      Value<DateTime?> plannedStart,
      Value<DateTime?> plannedEnd,
      Value<DateTime?> dueAt,
      Value<int> estimatedDurationMs,
      Value<DateTime?> actualStart,
      Value<DateTime?> actualFinish,
      Value<int> activeDurationMs,
      Value<int> pausedDurationMs,
      Value<int> idleDurationMs,
      Value<double> progress,
      Value<String?> roadmapId,
      Value<String?> roadmapPhaseId,
      Value<String?> occurrenceKey,
      Value<String> dataJson,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> createdByDeviceId,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalTasksTableUpdateCompanionBuilder =
    LocalTasksCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String?> templateId,
      Value<String> title,
      Value<String> description,
      Value<String?> domainId,
      Value<String> status,
      Value<int> priority,
      Value<String> executionMode,
      Value<DateTime?> scheduledDate,
      Value<DateTime?> plannedStart,
      Value<DateTime?> plannedEnd,
      Value<DateTime?> dueAt,
      Value<int> estimatedDurationMs,
      Value<DateTime?> actualStart,
      Value<DateTime?> actualFinish,
      Value<int> activeDurationMs,
      Value<int> pausedDurationMs,
      Value<int> idleDurationMs,
      Value<double> progress,
      Value<String?> roadmapId,
      Value<String?> roadmapPhaseId,
      Value<String?> occurrenceKey,
      Value<String> dataJson,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> createdByDeviceId,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalTasksTableFilterComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get domainId => $composableBuilder(
    column: $table.domainId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get executionMode => $composableBuilder(
    column: $table.executionMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get plannedEnd => $composableBuilder(
    column: $table.plannedEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedDurationMs => $composableBuilder(
    column: $table.estimatedDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualStart => $composableBuilder(
    column: $table.actualStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualFinish => $composableBuilder(
    column: $table.actualFinish,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activeDurationMs => $composableBuilder(
    column: $table.activeDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pausedDurationMs => $composableBuilder(
    column: $table.pausedDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get idleDurationMs => $composableBuilder(
    column: $table.idleDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roadmapId => $composableBuilder(
    column: $table.roadmapId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roadmapPhaseId => $composableBuilder(
    column: $table.roadmapPhaseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get domainId => $composableBuilder(
    column: $table.domainId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get executionMode => $composableBuilder(
    column: $table.executionMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get plannedEnd => $composableBuilder(
    column: $table.plannedEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedDurationMs => $composableBuilder(
    column: $table.estimatedDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualStart => $composableBuilder(
    column: $table.actualStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualFinish => $composableBuilder(
    column: $table.actualFinish,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activeDurationMs => $composableBuilder(
    column: $table.activeDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pausedDurationMs => $composableBuilder(
    column: $table.pausedDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get idleDurationMs => $composableBuilder(
    column: $table.idleDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roadmapId => $composableBuilder(
    column: $table.roadmapId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roadmapPhaseId => $composableBuilder(
    column: $table.roadmapPhaseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get domainId =>
      $composableBuilder(column: $table.domainId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get executionMode => $composableBuilder(
    column: $table.executionMode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get plannedEnd => $composableBuilder(
    column: $table.plannedEnd,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<int> get estimatedDurationMs => $composableBuilder(
    column: $table.estimatedDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get actualStart => $composableBuilder(
    column: $table.actualStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get actualFinish => $composableBuilder(
    column: $table.actualFinish,
    builder: (column) => column,
  );

  GeneratedColumn<int> get activeDurationMs => $composableBuilder(
    column: $table.activeDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pausedDurationMs => $composableBuilder(
    column: $table.pausedDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get idleDurationMs => $composableBuilder(
    column: $table.idleDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get roadmapId =>
      $composableBuilder(column: $table.roadmapId, builder: (column) => column);

  GeneratedColumn<String> get roadmapPhaseId => $composableBuilder(
    column: $table.roadmapPhaseId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalTasksTable,
          LocalTask,
          $$LocalTasksTableFilterComposer,
          $$LocalTasksTableOrderingComposer,
          $$LocalTasksTableAnnotationComposer,
          $$LocalTasksTableCreateCompanionBuilder,
          $$LocalTasksTableUpdateCompanionBuilder,
          (
            LocalTask,
            BaseReferences<_$AppDatabase, $LocalTasksTable, LocalTask>,
          ),
          LocalTask,
          PrefetchHooks Function()
        > {
  $$LocalTasksTableTableManager(_$AppDatabase db, $LocalTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> templateId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> domainId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> executionMode = const Value.absent(),
                Value<DateTime?> scheduledDate = const Value.absent(),
                Value<DateTime?> plannedStart = const Value.absent(),
                Value<DateTime?> plannedEnd = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<int> estimatedDurationMs = const Value.absent(),
                Value<DateTime?> actualStart = const Value.absent(),
                Value<DateTime?> actualFinish = const Value.absent(),
                Value<int> activeDurationMs = const Value.absent(),
                Value<int> pausedDurationMs = const Value.absent(),
                Value<int> idleDurationMs = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<String?> roadmapId = const Value.absent(),
                Value<String?> roadmapPhaseId = const Value.absent(),
                Value<String?> occurrenceKey = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> createdByDeviceId = const Value.absent(),
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTasksCompanion(
                id: id,
                userId: userId,
                templateId: templateId,
                title: title,
                description: description,
                domainId: domainId,
                status: status,
                priority: priority,
                executionMode: executionMode,
                scheduledDate: scheduledDate,
                plannedStart: plannedStart,
                plannedEnd: plannedEnd,
                dueAt: dueAt,
                estimatedDurationMs: estimatedDurationMs,
                actualStart: actualStart,
                actualFinish: actualFinish,
                activeDurationMs: activeDurationMs,
                pausedDurationMs: pausedDurationMs,
                idleDurationMs: idleDurationMs,
                progress: progress,
                roadmapId: roadmapId,
                roadmapPhaseId: roadmapPhaseId,
                occurrenceKey: occurrenceKey,
                dataJson: dataJson,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                createdByDeviceId: createdByDeviceId,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<String?> templateId = const Value.absent(),
                required String title,
                Value<String> description = const Value.absent(),
                Value<String?> domainId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> executionMode = const Value.absent(),
                Value<DateTime?> scheduledDate = const Value.absent(),
                Value<DateTime?> plannedStart = const Value.absent(),
                Value<DateTime?> plannedEnd = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<int> estimatedDurationMs = const Value.absent(),
                Value<DateTime?> actualStart = const Value.absent(),
                Value<DateTime?> actualFinish = const Value.absent(),
                Value<int> activeDurationMs = const Value.absent(),
                Value<int> pausedDurationMs = const Value.absent(),
                Value<int> idleDurationMs = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<String?> roadmapId = const Value.absent(),
                Value<String?> roadmapPhaseId = const Value.absent(),
                Value<String?> occurrenceKey = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> createdByDeviceId = const Value.absent(),
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTasksCompanion.insert(
                id: id,
                userId: userId,
                templateId: templateId,
                title: title,
                description: description,
                domainId: domainId,
                status: status,
                priority: priority,
                executionMode: executionMode,
                scheduledDate: scheduledDate,
                plannedStart: plannedStart,
                plannedEnd: plannedEnd,
                dueAt: dueAt,
                estimatedDurationMs: estimatedDurationMs,
                actualStart: actualStart,
                actualFinish: actualFinish,
                activeDurationMs: activeDurationMs,
                pausedDurationMs: pausedDurationMs,
                idleDurationMs: idleDurationMs,
                progress: progress,
                roadmapId: roadmapId,
                roadmapPhaseId: roadmapPhaseId,
                occurrenceKey: occurrenceKey,
                dataJson: dataJson,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                createdByDeviceId: createdByDeviceId,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalTasksTable,
      LocalTask,
      $$LocalTasksTableFilterComposer,
      $$LocalTasksTableOrderingComposer,
      $$LocalTasksTableAnnotationComposer,
      $$LocalTasksTableCreateCompanionBuilder,
      $$LocalTasksTableUpdateCompanionBuilder,
      (LocalTask, BaseReferences<_$AppDatabase, $LocalTasksTable, LocalTask>),
      LocalTask,
      PrefetchHooks Function()
    >;
typedef $$LocalRuntimeStatesTableCreateCompanionBuilder =
    LocalRuntimeStatesCompanion Function({
      required String id,
      required String userId,
      Value<String?> activeTaskId,
      Value<String?> sessionId,
      Value<String> state,
      Value<DateTime?> segmentStartedAt,
      Value<int> accumulatedActiveMs,
      Value<int> accumulatedPausedMs,
      Value<String> dataJson,
      Value<int> revision,
      required DateTime updatedAt,
      Value<String?> lastCommandId,
      Value<int> rowid,
    });
typedef $$LocalRuntimeStatesTableUpdateCompanionBuilder =
    LocalRuntimeStatesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String?> activeTaskId,
      Value<String?> sessionId,
      Value<String> state,
      Value<DateTime?> segmentStartedAt,
      Value<int> accumulatedActiveMs,
      Value<int> accumulatedPausedMs,
      Value<String> dataJson,
      Value<int> revision,
      Value<DateTime> updatedAt,
      Value<String?> lastCommandId,
      Value<int> rowid,
    });

class $$LocalRuntimeStatesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalRuntimeStatesTable> {
  $$LocalRuntimeStatesTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeTaskId => $composableBuilder(
    column: $table.activeTaskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get segmentStartedAt => $composableBuilder(
    column: $table.segmentStartedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accumulatedActiveMs => $composableBuilder(
    column: $table.accumulatedActiveMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accumulatedPausedMs => $composableBuilder(
    column: $table.accumulatedPausedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalRuntimeStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalRuntimeStatesTable> {
  $$LocalRuntimeStatesTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeTaskId => $composableBuilder(
    column: $table.activeTaskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get segmentStartedAt => $composableBuilder(
    column: $table.segmentStartedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accumulatedActiveMs => $composableBuilder(
    column: $table.accumulatedActiveMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accumulatedPausedMs => $composableBuilder(
    column: $table.accumulatedPausedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalRuntimeStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalRuntimeStatesTable> {
  $$LocalRuntimeStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get activeTaskId => $composableBuilder(
    column: $table.activeTaskId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get segmentStartedAt => $composableBuilder(
    column: $table.segmentStartedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accumulatedActiveMs => $composableBuilder(
    column: $table.accumulatedActiveMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accumulatedPausedMs => $composableBuilder(
    column: $table.accumulatedPausedMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => column,
  );
}

class $$LocalRuntimeStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalRuntimeStatesTable,
          LocalRuntime,
          $$LocalRuntimeStatesTableFilterComposer,
          $$LocalRuntimeStatesTableOrderingComposer,
          $$LocalRuntimeStatesTableAnnotationComposer,
          $$LocalRuntimeStatesTableCreateCompanionBuilder,
          $$LocalRuntimeStatesTableUpdateCompanionBuilder,
          (
            LocalRuntime,
            BaseReferences<
              _$AppDatabase,
              $LocalRuntimeStatesTable,
              LocalRuntime
            >,
          ),
          LocalRuntime,
          PrefetchHooks Function()
        > {
  $$LocalRuntimeStatesTableTableManager(
    _$AppDatabase db,
    $LocalRuntimeStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRuntimeStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRuntimeStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRuntimeStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> activeTaskId = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime?> segmentStartedAt = const Value.absent(),
                Value<int> accumulatedActiveMs = const Value.absent(),
                Value<int> accumulatedPausedMs = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRuntimeStatesCompanion(
                id: id,
                userId: userId,
                activeTaskId: activeTaskId,
                sessionId: sessionId,
                state: state,
                segmentStartedAt: segmentStartedAt,
                accumulatedActiveMs: accumulatedActiveMs,
                accumulatedPausedMs: accumulatedPausedMs,
                dataJson: dataJson,
                revision: revision,
                updatedAt: updatedAt,
                lastCommandId: lastCommandId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<String?> activeTaskId = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime?> segmentStartedAt = const Value.absent(),
                Value<int> accumulatedActiveMs = const Value.absent(),
                Value<int> accumulatedPausedMs = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime updatedAt,
                Value<String?> lastCommandId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRuntimeStatesCompanion.insert(
                id: id,
                userId: userId,
                activeTaskId: activeTaskId,
                sessionId: sessionId,
                state: state,
                segmentStartedAt: segmentStartedAt,
                accumulatedActiveMs: accumulatedActiveMs,
                accumulatedPausedMs: accumulatedPausedMs,
                dataJson: dataJson,
                revision: revision,
                updatedAt: updatedAt,
                lastCommandId: lastCommandId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalRuntimeStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalRuntimeStatesTable,
      LocalRuntime,
      $$LocalRuntimeStatesTableFilterComposer,
      $$LocalRuntimeStatesTableOrderingComposer,
      $$LocalRuntimeStatesTableAnnotationComposer,
      $$LocalRuntimeStatesTableCreateCompanionBuilder,
      $$LocalRuntimeStatesTableUpdateCompanionBuilder,
      (
        LocalRuntime,
        BaseReferences<_$AppDatabase, $LocalRuntimeStatesTable, LocalRuntime>,
      ),
      LocalRuntime,
      PrefetchHooks Function()
    >;
typedef $$LocalRoadmapsTableCreateCompanionBuilder =
    LocalRoadmapsCompanion Function({
      required String id,
      required String userId,
      required String title,
      Value<String> description,
      Value<String> status,
      Value<DateTime?> plannedStart,
      Value<DateTime?> originalTargetDate,
      Value<DateTime?> forecastTargetDate,
      Value<String> finalOutcome,
      Value<double> progress,
      Value<int?> requiredEffortMs,
      Value<int> completedEffortMs,
      Value<String> riskLevel,
      Value<String> forecastConfidence,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalRoadmapsTableUpdateCompanionBuilder =
    LocalRoadmapsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> title,
      Value<String> description,
      Value<String> status,
      Value<DateTime?> plannedStart,
      Value<DateTime?> originalTargetDate,
      Value<DateTime?> forecastTargetDate,
      Value<String> finalOutcome,
      Value<double> progress,
      Value<int?> requiredEffortMs,
      Value<int> completedEffortMs,
      Value<String> riskLevel,
      Value<String> forecastConfidence,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalRoadmapsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalRoadmapsTable> {
  $$LocalRoadmapsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get originalTargetDate => $composableBuilder(
    column: $table.originalTargetDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get forecastTargetDate => $composableBuilder(
    column: $table.forecastTargetDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalOutcome => $composableBuilder(
    column: $table.finalOutcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get requiredEffortMs => $composableBuilder(
    column: $table.requiredEffortMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedEffortMs => $composableBuilder(
    column: $table.completedEffortMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get riskLevel => $composableBuilder(
    column: $table.riskLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get forecastConfidence => $composableBuilder(
    column: $table.forecastConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalRoadmapsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalRoadmapsTable> {
  $$LocalRoadmapsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get originalTargetDate => $composableBuilder(
    column: $table.originalTargetDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get forecastTargetDate => $composableBuilder(
    column: $table.forecastTargetDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalOutcome => $composableBuilder(
    column: $table.finalOutcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get requiredEffortMs => $composableBuilder(
    column: $table.requiredEffortMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedEffortMs => $composableBuilder(
    column: $table.completedEffortMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get riskLevel => $composableBuilder(
    column: $table.riskLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get forecastConfidence => $composableBuilder(
    column: $table.forecastConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalRoadmapsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalRoadmapsTable> {
  $$LocalRoadmapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get plannedStart => $composableBuilder(
    column: $table.plannedStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get originalTargetDate => $composableBuilder(
    column: $table.originalTargetDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get forecastTargetDate => $composableBuilder(
    column: $table.forecastTargetDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get finalOutcome => $composableBuilder(
    column: $table.finalOutcome,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<int> get requiredEffortMs => $composableBuilder(
    column: $table.requiredEffortMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedEffortMs => $composableBuilder(
    column: $table.completedEffortMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get riskLevel =>
      $composableBuilder(column: $table.riskLevel, builder: (column) => column);

  GeneratedColumn<String> get forecastConfidence => $composableBuilder(
    column: $table.forecastConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalRoadmapsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalRoadmapsTable,
          LocalRoadmap,
          $$LocalRoadmapsTableFilterComposer,
          $$LocalRoadmapsTableOrderingComposer,
          $$LocalRoadmapsTableAnnotationComposer,
          $$LocalRoadmapsTableCreateCompanionBuilder,
          $$LocalRoadmapsTableUpdateCompanionBuilder,
          (
            LocalRoadmap,
            BaseReferences<_$AppDatabase, $LocalRoadmapsTable, LocalRoadmap>,
          ),
          LocalRoadmap,
          PrefetchHooks Function()
        > {
  $$LocalRoadmapsTableTableManager(_$AppDatabase db, $LocalRoadmapsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRoadmapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRoadmapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRoadmapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> plannedStart = const Value.absent(),
                Value<DateTime?> originalTargetDate = const Value.absent(),
                Value<DateTime?> forecastTargetDate = const Value.absent(),
                Value<String> finalOutcome = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<int?> requiredEffortMs = const Value.absent(),
                Value<int> completedEffortMs = const Value.absent(),
                Value<String> riskLevel = const Value.absent(),
                Value<String> forecastConfidence = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRoadmapsCompanion(
                id: id,
                userId: userId,
                title: title,
                description: description,
                status: status,
                plannedStart: plannedStart,
                originalTargetDate: originalTargetDate,
                forecastTargetDate: forecastTargetDate,
                finalOutcome: finalOutcome,
                progress: progress,
                requiredEffortMs: requiredEffortMs,
                completedEffortMs: completedEffortMs,
                riskLevel: riskLevel,
                forecastConfidence: forecastConfidence,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String title,
                Value<String> description = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> plannedStart = const Value.absent(),
                Value<DateTime?> originalTargetDate = const Value.absent(),
                Value<DateTime?> forecastTargetDate = const Value.absent(),
                Value<String> finalOutcome = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<int?> requiredEffortMs = const Value.absent(),
                Value<int> completedEffortMs = const Value.absent(),
                Value<String> riskLevel = const Value.absent(),
                Value<String> forecastConfidence = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalRoadmapsCompanion.insert(
                id: id,
                userId: userId,
                title: title,
                description: description,
                status: status,
                plannedStart: plannedStart,
                originalTargetDate: originalTargetDate,
                forecastTargetDate: forecastTargetDate,
                finalOutcome: finalOutcome,
                progress: progress,
                requiredEffortMs: requiredEffortMs,
                completedEffortMs: completedEffortMs,
                riskLevel: riskLevel,
                forecastConfidence: forecastConfidence,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalRoadmapsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalRoadmapsTable,
      LocalRoadmap,
      $$LocalRoadmapsTableFilterComposer,
      $$LocalRoadmapsTableOrderingComposer,
      $$LocalRoadmapsTableAnnotationComposer,
      $$LocalRoadmapsTableCreateCompanionBuilder,
      $$LocalRoadmapsTableUpdateCompanionBuilder,
      (
        LocalRoadmap,
        BaseReferences<_$AppDatabase, $LocalRoadmapsTable, LocalRoadmap>,
      ),
      LocalRoadmap,
      PrefetchHooks Function()
    >;
typedef $$LocalActivitySegmentsTableCreateCompanionBuilder =
    LocalActivitySegmentsCompanion Function({
      required String id,
      required String userId,
      required String deviceId,
      required String deviceEventId,
      required DateTime startedAt,
      required DateTime endedAt,
      required String sourceType,
      Value<String?> processName,
      Value<String?> windowTitle,
      Value<String?> domain,
      Value<String?> url,
      Value<String?> pageTitle,
      Value<String?> idleState,
      Value<double?> captureConfidence,
      Value<String> rawMetadataJson,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalActivitySegmentsTableUpdateCompanionBuilder =
    LocalActivitySegmentsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> deviceId,
      Value<String> deviceEventId,
      Value<DateTime> startedAt,
      Value<DateTime> endedAt,
      Value<String> sourceType,
      Value<String?> processName,
      Value<String?> windowTitle,
      Value<String?> domain,
      Value<String?> url,
      Value<String?> pageTitle,
      Value<String?> idleState,
      Value<double?> captureConfidence,
      Value<String> rawMetadataJson,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalActivitySegmentsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalActivitySegmentsTable> {
  $$LocalActivitySegmentsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceEventId => $composableBuilder(
    column: $table.deviceEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processName => $composableBuilder(
    column: $table.processName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get windowTitle => $composableBuilder(
    column: $table.windowTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageTitle => $composableBuilder(
    column: $table.pageTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idleState => $composableBuilder(
    column: $table.idleState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get captureConfidence => $composableBuilder(
    column: $table.captureConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawMetadataJson => $composableBuilder(
    column: $table.rawMetadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalActivitySegmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalActivitySegmentsTable> {
  $$LocalActivitySegmentsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceEventId => $composableBuilder(
    column: $table.deviceEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processName => $composableBuilder(
    column: $table.processName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get windowTitle => $composableBuilder(
    column: $table.windowTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get domain => $composableBuilder(
    column: $table.domain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageTitle => $composableBuilder(
    column: $table.pageTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idleState => $composableBuilder(
    column: $table.idleState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get captureConfidence => $composableBuilder(
    column: $table.captureConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawMetadataJson => $composableBuilder(
    column: $table.rawMetadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalActivitySegmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalActivitySegmentsTable> {
  $$LocalActivitySegmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceEventId => $composableBuilder(
    column: $table.deviceEventId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processName => $composableBuilder(
    column: $table.processName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get windowTitle => $composableBuilder(
    column: $table.windowTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get domain =>
      $composableBuilder(column: $table.domain, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get pageTitle =>
      $composableBuilder(column: $table.pageTitle, builder: (column) => column);

  GeneratedColumn<String> get idleState =>
      $composableBuilder(column: $table.idleState, builder: (column) => column);

  GeneratedColumn<double> get captureConfidence => $composableBuilder(
    column: $table.captureConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawMetadataJson => $composableBuilder(
    column: $table.rawMetadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalActivitySegmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalActivitySegmentsTable,
          LocalActivitySegment,
          $$LocalActivitySegmentsTableFilterComposer,
          $$LocalActivitySegmentsTableOrderingComposer,
          $$LocalActivitySegmentsTableAnnotationComposer,
          $$LocalActivitySegmentsTableCreateCompanionBuilder,
          $$LocalActivitySegmentsTableUpdateCompanionBuilder,
          (
            LocalActivitySegment,
            BaseReferences<
              _$AppDatabase,
              $LocalActivitySegmentsTable,
              LocalActivitySegment
            >,
          ),
          LocalActivitySegment,
          PrefetchHooks Function()
        > {
  $$LocalActivitySegmentsTableTableManager(
    _$AppDatabase db,
    $LocalActivitySegmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalActivitySegmentsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalActivitySegmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalActivitySegmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> deviceEventId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime> endedAt = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<String?> processName = const Value.absent(),
                Value<String?> windowTitle = const Value.absent(),
                Value<String?> domain = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String?> pageTitle = const Value.absent(),
                Value<String?> idleState = const Value.absent(),
                Value<double?> captureConfidence = const Value.absent(),
                Value<String> rawMetadataJson = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalActivitySegmentsCompanion(
                id: id,
                userId: userId,
                deviceId: deviceId,
                deviceEventId: deviceEventId,
                startedAt: startedAt,
                endedAt: endedAt,
                sourceType: sourceType,
                processName: processName,
                windowTitle: windowTitle,
                domain: domain,
                url: url,
                pageTitle: pageTitle,
                idleState: idleState,
                captureConfidence: captureConfidence,
                rawMetadataJson: rawMetadataJson,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String deviceId,
                required String deviceEventId,
                required DateTime startedAt,
                required DateTime endedAt,
                required String sourceType,
                Value<String?> processName = const Value.absent(),
                Value<String?> windowTitle = const Value.absent(),
                Value<String?> domain = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String?> pageTitle = const Value.absent(),
                Value<String?> idleState = const Value.absent(),
                Value<double?> captureConfidence = const Value.absent(),
                Value<String> rawMetadataJson = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalActivitySegmentsCompanion.insert(
                id: id,
                userId: userId,
                deviceId: deviceId,
                deviceEventId: deviceEventId,
                startedAt: startedAt,
                endedAt: endedAt,
                sourceType: sourceType,
                processName: processName,
                windowTitle: windowTitle,
                domain: domain,
                url: url,
                pageTitle: pageTitle,
                idleState: idleState,
                captureConfidence: captureConfidence,
                rawMetadataJson: rawMetadataJson,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalActivitySegmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalActivitySegmentsTable,
      LocalActivitySegment,
      $$LocalActivitySegmentsTableFilterComposer,
      $$LocalActivitySegmentsTableOrderingComposer,
      $$LocalActivitySegmentsTableAnnotationComposer,
      $$LocalActivitySegmentsTableCreateCompanionBuilder,
      $$LocalActivitySegmentsTableUpdateCompanionBuilder,
      (
        LocalActivitySegment,
        BaseReferences<
          _$AppDatabase,
          $LocalActivitySegmentsTable,
          LocalActivitySegment
        >,
      ),
      LocalActivitySegment,
      PrefetchHooks Function()
    >;
typedef $$LocalAttributionsTableCreateCompanionBuilder =
    LocalAttributionsCompanion Function({
      required String id,
      required String userId,
      required String activitySegmentId,
      required String targetType,
      Value<String?> targetId,
      required String classification,
      required double confidence,
      Value<String> attributionStatus,
      Value<bool> confirmedByUser,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalAttributionsTableUpdateCompanionBuilder =
    LocalAttributionsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> activitySegmentId,
      Value<String> targetType,
      Value<String?> targetId,
      Value<String> classification,
      Value<double> confidence,
      Value<String> attributionStatus,
      Value<bool> confirmedByUser,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalAttributionsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalAttributionsTable> {
  $$LocalAttributionsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attributionStatus => $composableBuilder(
    column: $table.attributionStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get confirmedByUser => $composableBuilder(
    column: $table.confirmedByUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalAttributionsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalAttributionsTable> {
  $$LocalAttributionsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attributionStatus => $composableBuilder(
    column: $table.attributionStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get confirmedByUser => $composableBuilder(
    column: $table.confirmedByUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalAttributionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalAttributionsTable> {
  $$LocalAttributionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get classification => $composableBuilder(
    column: $table.classification,
    builder: (column) => column,
  );

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attributionStatus => $composableBuilder(
    column: $table.attributionStatus,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get confirmedByUser => $composableBuilder(
    column: $table.confirmedByUser,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalAttributionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalAttributionsTable,
          LocalAttribution,
          $$LocalAttributionsTableFilterComposer,
          $$LocalAttributionsTableOrderingComposer,
          $$LocalAttributionsTableAnnotationComposer,
          $$LocalAttributionsTableCreateCompanionBuilder,
          $$LocalAttributionsTableUpdateCompanionBuilder,
          (
            LocalAttribution,
            BaseReferences<
              _$AppDatabase,
              $LocalAttributionsTable,
              LocalAttribution
            >,
          ),
          LocalAttribution,
          PrefetchHooks Function()
        > {
  $$LocalAttributionsTableTableManager(
    _$AppDatabase db,
    $LocalAttributionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAttributionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAttributionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAttributionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> activitySegmentId = const Value.absent(),
                Value<String> targetType = const Value.absent(),
                Value<String?> targetId = const Value.absent(),
                Value<String> classification = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<String> attributionStatus = const Value.absent(),
                Value<bool> confirmedByUser = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAttributionsCompanion(
                id: id,
                userId: userId,
                activitySegmentId: activitySegmentId,
                targetType: targetType,
                targetId: targetId,
                classification: classification,
                confidence: confidence,
                attributionStatus: attributionStatus,
                confirmedByUser: confirmedByUser,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String activitySegmentId,
                required String targetType,
                Value<String?> targetId = const Value.absent(),
                required String classification,
                required double confidence,
                Value<String> attributionStatus = const Value.absent(),
                Value<bool> confirmedByUser = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAttributionsCompanion.insert(
                id: id,
                userId: userId,
                activitySegmentId: activitySegmentId,
                targetType: targetType,
                targetId: targetId,
                classification: classification,
                confidence: confidence,
                attributionStatus: attributionStatus,
                confirmedByUser: confirmedByUser,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalAttributionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalAttributionsTable,
      LocalAttribution,
      $$LocalAttributionsTableFilterComposer,
      $$LocalAttributionsTableOrderingComposer,
      $$LocalAttributionsTableAnnotationComposer,
      $$LocalAttributionsTableCreateCompanionBuilder,
      $$LocalAttributionsTableUpdateCompanionBuilder,
      (
        LocalAttribution,
        BaseReferences<
          _$AppDatabase,
          $LocalAttributionsTable,
          LocalAttribution
        >,
      ),
      LocalAttribution,
      PrefetchHooks Function()
    >;
typedef $$LocalContributionsTableCreateCompanionBuilder =
    LocalContributionsCompanion Function({
      required String id,
      required String userId,
      required String activitySegmentId,
      required String attributionId,
      required String targetType,
      Value<String?> targetId,
      required String contributionType,
      required int physicalDurationMs,
      required int creditedDurationMs,
      Value<double?> progressValue,
      Value<bool> isUnscheduled,
      Value<bool> isCrossTask,
      Value<bool> isIdleDerived,
      Value<bool> isAutomatic,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalContributionsTableUpdateCompanionBuilder =
    LocalContributionsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> activitySegmentId,
      Value<String> attributionId,
      Value<String> targetType,
      Value<String?> targetId,
      Value<String> contributionType,
      Value<int> physicalDurationMs,
      Value<int> creditedDurationMs,
      Value<double?> progressValue,
      Value<bool> isUnscheduled,
      Value<bool> isCrossTask,
      Value<bool> isIdleDerived,
      Value<bool> isAutomatic,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalContributionsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalContributionsTable> {
  $$LocalContributionsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attributionId => $composableBuilder(
    column: $table.attributionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contributionType => $composableBuilder(
    column: $table.contributionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get physicalDurationMs => $composableBuilder(
    column: $table.physicalDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get creditedDurationMs => $composableBuilder(
    column: $table.creditedDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progressValue => $composableBuilder(
    column: $table.progressValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isUnscheduled => $composableBuilder(
    column: $table.isUnscheduled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCrossTask => $composableBuilder(
    column: $table.isCrossTask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isIdleDerived => $composableBuilder(
    column: $table.isIdleDerived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAutomatic => $composableBuilder(
    column: $table.isAutomatic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalContributionsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalContributionsTable> {
  $$LocalContributionsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attributionId => $composableBuilder(
    column: $table.attributionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contributionType => $composableBuilder(
    column: $table.contributionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get physicalDurationMs => $composableBuilder(
    column: $table.physicalDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get creditedDurationMs => $composableBuilder(
    column: $table.creditedDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progressValue => $composableBuilder(
    column: $table.progressValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isUnscheduled => $composableBuilder(
    column: $table.isUnscheduled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCrossTask => $composableBuilder(
    column: $table.isCrossTask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isIdleDerived => $composableBuilder(
    column: $table.isIdleDerived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAutomatic => $composableBuilder(
    column: $table.isAutomatic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalContributionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalContributionsTable> {
  $$LocalContributionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attributionId => $composableBuilder(
    column: $table.attributionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get contributionType => $composableBuilder(
    column: $table.contributionType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get physicalDurationMs => $composableBuilder(
    column: $table.physicalDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get creditedDurationMs => $composableBuilder(
    column: $table.creditedDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progressValue => $composableBuilder(
    column: $table.progressValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isUnscheduled => $composableBuilder(
    column: $table.isUnscheduled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCrossTask => $composableBuilder(
    column: $table.isCrossTask,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isIdleDerived => $composableBuilder(
    column: $table.isIdleDerived,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isAutomatic => $composableBuilder(
    column: $table.isAutomatic,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalContributionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalContributionsTable,
          LocalContribution,
          $$LocalContributionsTableFilterComposer,
          $$LocalContributionsTableOrderingComposer,
          $$LocalContributionsTableAnnotationComposer,
          $$LocalContributionsTableCreateCompanionBuilder,
          $$LocalContributionsTableUpdateCompanionBuilder,
          (
            LocalContribution,
            BaseReferences<
              _$AppDatabase,
              $LocalContributionsTable,
              LocalContribution
            >,
          ),
          LocalContribution,
          PrefetchHooks Function()
        > {
  $$LocalContributionsTableTableManager(
    _$AppDatabase db,
    $LocalContributionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalContributionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalContributionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalContributionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> activitySegmentId = const Value.absent(),
                Value<String> attributionId = const Value.absent(),
                Value<String> targetType = const Value.absent(),
                Value<String?> targetId = const Value.absent(),
                Value<String> contributionType = const Value.absent(),
                Value<int> physicalDurationMs = const Value.absent(),
                Value<int> creditedDurationMs = const Value.absent(),
                Value<double?> progressValue = const Value.absent(),
                Value<bool> isUnscheduled = const Value.absent(),
                Value<bool> isCrossTask = const Value.absent(),
                Value<bool> isIdleDerived = const Value.absent(),
                Value<bool> isAutomatic = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalContributionsCompanion(
                id: id,
                userId: userId,
                activitySegmentId: activitySegmentId,
                attributionId: attributionId,
                targetType: targetType,
                targetId: targetId,
                contributionType: contributionType,
                physicalDurationMs: physicalDurationMs,
                creditedDurationMs: creditedDurationMs,
                progressValue: progressValue,
                isUnscheduled: isUnscheduled,
                isCrossTask: isCrossTask,
                isIdleDerived: isIdleDerived,
                isAutomatic: isAutomatic,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String activitySegmentId,
                required String attributionId,
                required String targetType,
                Value<String?> targetId = const Value.absent(),
                required String contributionType,
                required int physicalDurationMs,
                required int creditedDurationMs,
                Value<double?> progressValue = const Value.absent(),
                Value<bool> isUnscheduled = const Value.absent(),
                Value<bool> isCrossTask = const Value.absent(),
                Value<bool> isIdleDerived = const Value.absent(),
                Value<bool> isAutomatic = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalContributionsCompanion.insert(
                id: id,
                userId: userId,
                activitySegmentId: activitySegmentId,
                attributionId: attributionId,
                targetType: targetType,
                targetId: targetId,
                contributionType: contributionType,
                physicalDurationMs: physicalDurationMs,
                creditedDurationMs: creditedDurationMs,
                progressValue: progressValue,
                isUnscheduled: isUnscheduled,
                isCrossTask: isCrossTask,
                isIdleDerived: isIdleDerived,
                isAutomatic: isAutomatic,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalContributionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalContributionsTable,
      LocalContribution,
      $$LocalContributionsTableFilterComposer,
      $$LocalContributionsTableOrderingComposer,
      $$LocalContributionsTableAnnotationComposer,
      $$LocalContributionsTableCreateCompanionBuilder,
      $$LocalContributionsTableUpdateCompanionBuilder,
      (
        LocalContribution,
        BaseReferences<
          _$AppDatabase,
          $LocalContributionsTable,
          LocalContribution
        >,
      ),
      LocalContribution,
      PrefetchHooks Function()
    >;
typedef $$LocalActivityReviewsTableCreateCompanionBuilder =
    LocalActivityReviewsCompanion Function({
      required String id,
      required String userId,
      required String activitySegmentId,
      required String reviewReason,
      Value<int> priority,
      Value<String?> suggestedTargetType,
      Value<String?> suggestedTargetId,
      Value<String?> suggestedTargetTitle,
      Value<String?> suggestedClassification,
      Value<double?> confidence,
      Value<String> status,
      Value<DateTime?> reviewedAt,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalActivityReviewsTableUpdateCompanionBuilder =
    LocalActivityReviewsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> activitySegmentId,
      Value<String> reviewReason,
      Value<int> priority,
      Value<String?> suggestedTargetType,
      Value<String?> suggestedTargetId,
      Value<String?> suggestedTargetTitle,
      Value<String?> suggestedClassification,
      Value<double?> confidence,
      Value<String> status,
      Value<DateTime?> reviewedAt,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalActivityReviewsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalActivityReviewsTable> {
  $$LocalActivityReviewsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestedTargetType => $composableBuilder(
    column: $table.suggestedTargetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestedTargetId => $composableBuilder(
    column: $table.suggestedTargetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestedTargetTitle => $composableBuilder(
    column: $table.suggestedTargetTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestedClassification => $composableBuilder(
    column: $table.suggestedClassification,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalActivityReviewsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalActivityReviewsTable> {
  $$LocalActivityReviewsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestedTargetType => $composableBuilder(
    column: $table.suggestedTargetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestedTargetId => $composableBuilder(
    column: $table.suggestedTargetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestedTargetTitle => $composableBuilder(
    column: $table.suggestedTargetTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestedClassification => $composableBuilder(
    column: $table.suggestedClassification,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalActivityReviewsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalActivityReviewsTable> {
  $$LocalActivityReviewsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get activitySegmentId => $composableBuilder(
    column: $table.activitySegmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reviewReason => $composableBuilder(
    column: $table.reviewReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get suggestedTargetType => $composableBuilder(
    column: $table.suggestedTargetType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get suggestedTargetId => $composableBuilder(
    column: $table.suggestedTargetId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get suggestedTargetTitle => $composableBuilder(
    column: $table.suggestedTargetTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get suggestedClassification => $composableBuilder(
    column: $table.suggestedClassification,
    builder: (column) => column,
  );

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalActivityReviewsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalActivityReviewsTable,
          LocalActivityReview,
          $$LocalActivityReviewsTableFilterComposer,
          $$LocalActivityReviewsTableOrderingComposer,
          $$LocalActivityReviewsTableAnnotationComposer,
          $$LocalActivityReviewsTableCreateCompanionBuilder,
          $$LocalActivityReviewsTableUpdateCompanionBuilder,
          (
            LocalActivityReview,
            BaseReferences<
              _$AppDatabase,
              $LocalActivityReviewsTable,
              LocalActivityReview
            >,
          ),
          LocalActivityReview,
          PrefetchHooks Function()
        > {
  $$LocalActivityReviewsTableTableManager(
    _$AppDatabase db,
    $LocalActivityReviewsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalActivityReviewsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalActivityReviewsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalActivityReviewsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> activitySegmentId = const Value.absent(),
                Value<String> reviewReason = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> suggestedTargetType = const Value.absent(),
                Value<String?> suggestedTargetId = const Value.absent(),
                Value<String?> suggestedTargetTitle = const Value.absent(),
                Value<String?> suggestedClassification = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> reviewedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalActivityReviewsCompanion(
                id: id,
                userId: userId,
                activitySegmentId: activitySegmentId,
                reviewReason: reviewReason,
                priority: priority,
                suggestedTargetType: suggestedTargetType,
                suggestedTargetId: suggestedTargetId,
                suggestedTargetTitle: suggestedTargetTitle,
                suggestedClassification: suggestedClassification,
                confidence: confidence,
                status: status,
                reviewedAt: reviewedAt,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String activitySegmentId,
                required String reviewReason,
                Value<int> priority = const Value.absent(),
                Value<String?> suggestedTargetType = const Value.absent(),
                Value<String?> suggestedTargetId = const Value.absent(),
                Value<String?> suggestedTargetTitle = const Value.absent(),
                Value<String?> suggestedClassification = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> reviewedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalActivityReviewsCompanion.insert(
                id: id,
                userId: userId,
                activitySegmentId: activitySegmentId,
                reviewReason: reviewReason,
                priority: priority,
                suggestedTargetType: suggestedTargetType,
                suggestedTargetId: suggestedTargetId,
                suggestedTargetTitle: suggestedTargetTitle,
                suggestedClassification: suggestedClassification,
                confidence: confidence,
                status: status,
                reviewedAt: reviewedAt,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalActivityReviewsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalActivityReviewsTable,
      LocalActivityReview,
      $$LocalActivityReviewsTableFilterComposer,
      $$LocalActivityReviewsTableOrderingComposer,
      $$LocalActivityReviewsTableAnnotationComposer,
      $$LocalActivityReviewsTableCreateCompanionBuilder,
      $$LocalActivityReviewsTableUpdateCompanionBuilder,
      (
        LocalActivityReview,
        BaseReferences<
          _$AppDatabase,
          $LocalActivityReviewsTable,
          LocalActivityReview
        >,
      ),
      LocalActivityReview,
      PrefetchHooks Function()
    >;
typedef $$LocalEntityRecordsTableCreateCompanionBuilder =
    LocalEntityRecordsCompanion Function({
      required String id,
      required String userId,
      required String entityType,
      Value<String?> parentId,
      Value<String?> secondaryParentId,
      Value<String> title,
      Value<String> status,
      Value<double> position,
      Value<String> dataJson,
      Value<int> revision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> createdByDeviceId,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalEntityRecordsTableUpdateCompanionBuilder =
    LocalEntityRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> entityType,
      Value<String?> parentId,
      Value<String?> secondaryParentId,
      Value<String> title,
      Value<String> status,
      Value<double> position,
      Value<String> dataJson,
      Value<int> revision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> createdByDeviceId,
      Value<String?> updatedByDeviceId,
      Value<String?> lastCommandId,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$LocalEntityRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalEntityRecordsTable> {
  $$LocalEntityRecordsTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secondaryParentId => $composableBuilder(
    column: $table.secondaryParentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalEntityRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalEntityRecordsTable> {
  $$LocalEntityRecordsTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secondaryParentId => $composableBuilder(
    column: $table.secondaryParentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dataJson => $composableBuilder(
    column: $table.dataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalEntityRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalEntityRecordsTable> {
  $$LocalEntityRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get secondaryParentId => $composableBuilder(
    column: $table.secondaryParentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get dataJson =>
      $composableBuilder(column: $table.dataJson, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get createdByDeviceId => $composableBuilder(
    column: $table.createdByDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedByDeviceId => $composableBuilder(
    column: $table.updatedByDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCommandId => $composableBuilder(
    column: $table.lastCommandId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$LocalEntityRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalEntityRecordsTable,
          LocalEntityRecord,
          $$LocalEntityRecordsTableFilterComposer,
          $$LocalEntityRecordsTableOrderingComposer,
          $$LocalEntityRecordsTableAnnotationComposer,
          $$LocalEntityRecordsTableCreateCompanionBuilder,
          $$LocalEntityRecordsTableUpdateCompanionBuilder,
          (
            LocalEntityRecord,
            BaseReferences<
              _$AppDatabase,
              $LocalEntityRecordsTable,
              LocalEntityRecord
            >,
          ),
          LocalEntityRecord,
          PrefetchHooks Function()
        > {
  $$LocalEntityRecordsTableTableManager(
    _$AppDatabase db,
    $LocalEntityRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalEntityRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalEntityRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalEntityRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> secondaryParentId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> position = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> createdByDeviceId = const Value.absent(),
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalEntityRecordsCompanion(
                id: id,
                userId: userId,
                entityType: entityType,
                parentId: parentId,
                secondaryParentId: secondaryParentId,
                title: title,
                status: status,
                position: position,
                dataJson: dataJson,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                createdByDeviceId: createdByDeviceId,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String entityType,
                Value<String?> parentId = const Value.absent(),
                Value<String?> secondaryParentId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> position = const Value.absent(),
                Value<String> dataJson = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> createdByDeviceId = const Value.absent(),
                Value<String?> updatedByDeviceId = const Value.absent(),
                Value<String?> lastCommandId = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalEntityRecordsCompanion.insert(
                id: id,
                userId: userId,
                entityType: entityType,
                parentId: parentId,
                secondaryParentId: secondaryParentId,
                title: title,
                status: status,
                position: position,
                dataJson: dataJson,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                createdByDeviceId: createdByDeviceId,
                updatedByDeviceId: updatedByDeviceId,
                lastCommandId: lastCommandId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalEntityRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalEntityRecordsTable,
      LocalEntityRecord,
      $$LocalEntityRecordsTableFilterComposer,
      $$LocalEntityRecordsTableOrderingComposer,
      $$LocalEntityRecordsTableAnnotationComposer,
      $$LocalEntityRecordsTableCreateCompanionBuilder,
      $$LocalEntityRecordsTableUpdateCompanionBuilder,
      (
        LocalEntityRecord,
        BaseReferences<
          _$AppDatabase,
          $LocalEntityRecordsTable,
          LocalEntityRecord
        >,
      ),
      LocalEntityRecord,
      PrefetchHooks Function()
    >;
typedef $$LocalOutboxCommandsTableCreateCompanionBuilder =
    LocalOutboxCommandsCompanion Function({
      required String commandId,
      required String userId,
      required String deviceId,
      required int deviceSequence,
      required String entityType,
      required String entityId,
      required String commandType,
      required int baseRevision,
      required String payloadJson,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      required DateTime clientTimestamp,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$LocalOutboxCommandsTableUpdateCompanionBuilder =
    LocalOutboxCommandsCompanion Function({
      Value<String> commandId,
      Value<String> userId,
      Value<String> deviceId,
      Value<int> deviceSequence,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> commandType,
      Value<int> baseRevision,
      Value<String> payloadJson,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<DateTime> clientTimestamp,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$LocalOutboxCommandsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalOutboxCommandsTable> {
  $$LocalOutboxCommandsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deviceSequence => $composableBuilder(
    column: $table.deviceSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientTimestamp => $composableBuilder(
    column: $table.clientTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalOutboxCommandsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalOutboxCommandsTable> {
  $$LocalOutboxCommandsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deviceSequence => $composableBuilder(
    column: $table.deviceSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientTimestamp => $composableBuilder(
    column: $table.clientTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalOutboxCommandsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalOutboxCommandsTable> {
  $$LocalOutboxCommandsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get commandId =>
      $composableBuilder(column: $table.commandId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get deviceSequence => $composableBuilder(
    column: $table.deviceSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get clientTimestamp => $composableBuilder(
    column: $table.clientTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LocalOutboxCommandsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalOutboxCommandsTable,
          LocalOutboxCommand,
          $$LocalOutboxCommandsTableFilterComposer,
          $$LocalOutboxCommandsTableOrderingComposer,
          $$LocalOutboxCommandsTableAnnotationComposer,
          $$LocalOutboxCommandsTableCreateCompanionBuilder,
          $$LocalOutboxCommandsTableUpdateCompanionBuilder,
          (
            LocalOutboxCommand,
            BaseReferences<
              _$AppDatabase,
              $LocalOutboxCommandsTable,
              LocalOutboxCommand
            >,
          ),
          LocalOutboxCommand,
          PrefetchHooks Function()
        > {
  $$LocalOutboxCommandsTableTableManager(
    _$AppDatabase db,
    $LocalOutboxCommandsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalOutboxCommandsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalOutboxCommandsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalOutboxCommandsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> commandId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> deviceSequence = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> commandType = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> clientTimestamp = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalOutboxCommandsCompanion(
                commandId: commandId,
                userId: userId,
                deviceId: deviceId,
                deviceSequence: deviceSequence,
                entityType: entityType,
                entityId: entityId,
                commandType: commandType,
                baseRevision: baseRevision,
                payloadJson: payloadJson,
                status: status,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                clientTimestamp: clientTimestamp,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String commandId,
                required String userId,
                required String deviceId,
                required int deviceSequence,
                required String entityType,
                required String entityId,
                required String commandType,
                required int baseRevision,
                required String payloadJson,
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime clientTimestamp,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalOutboxCommandsCompanion.insert(
                commandId: commandId,
                userId: userId,
                deviceId: deviceId,
                deviceSequence: deviceSequence,
                entityType: entityType,
                entityId: entityId,
                commandType: commandType,
                baseRevision: baseRevision,
                payloadJson: payloadJson,
                status: status,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                clientTimestamp: clientTimestamp,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalOutboxCommandsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalOutboxCommandsTable,
      LocalOutboxCommand,
      $$LocalOutboxCommandsTableFilterComposer,
      $$LocalOutboxCommandsTableOrderingComposer,
      $$LocalOutboxCommandsTableAnnotationComposer,
      $$LocalOutboxCommandsTableCreateCompanionBuilder,
      $$LocalOutboxCommandsTableUpdateCompanionBuilder,
      (
        LocalOutboxCommand,
        BaseReferences<
          _$AppDatabase,
          $LocalOutboxCommandsTable,
          LocalOutboxCommand
        >,
      ),
      LocalOutboxCommand,
      PrefetchHooks Function()
    >;
typedef $$LocalSyncStatesTableCreateCompanionBuilder =
    LocalSyncStatesCompanion Function({
      required String id,
      required String userId,
      Value<int> lastChangeSequence,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LocalSyncStatesTableUpdateCompanionBuilder =
    LocalSyncStatesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<int> lastChangeSequence,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalSyncStatesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSyncStatesTable> {
  $$LocalSyncStatesTableFilterComposer({
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

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastChangeSequence => $composableBuilder(
    column: $table.lastChangeSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSyncStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSyncStatesTable> {
  $$LocalSyncStatesTableOrderingComposer({
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

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastChangeSequence => $composableBuilder(
    column: $table.lastChangeSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSyncStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSyncStatesTable> {
  $$LocalSyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get lastChangeSequence => $composableBuilder(
    column: $table.lastChangeSequence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalSyncStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalSyncStatesTable,
          LocalSyncState,
          $$LocalSyncStatesTableFilterComposer,
          $$LocalSyncStatesTableOrderingComposer,
          $$LocalSyncStatesTableAnnotationComposer,
          $$LocalSyncStatesTableCreateCompanionBuilder,
          $$LocalSyncStatesTableUpdateCompanionBuilder,
          (
            LocalSyncState,
            BaseReferences<
              _$AppDatabase,
              $LocalSyncStatesTable,
              LocalSyncState
            >,
          ),
          LocalSyncState,
          PrefetchHooks Function()
        > {
  $$LocalSyncStatesTableTableManager(
    _$AppDatabase db,
    $LocalSyncStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> lastChangeSequence = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncStatesCompanion(
                id: id,
                userId: userId,
                lastChangeSequence: lastChangeSequence,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<int> lastChangeSequence = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncStatesCompanion.insert(
                id: id,
                userId: userId,
                lastChangeSequence: lastChangeSequence,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalSyncStatesTable,
      LocalSyncState,
      $$LocalSyncStatesTableFilterComposer,
      $$LocalSyncStatesTableOrderingComposer,
      $$LocalSyncStatesTableAnnotationComposer,
      $$LocalSyncStatesTableCreateCompanionBuilder,
      $$LocalSyncStatesTableUpdateCompanionBuilder,
      (
        LocalSyncState,
        BaseReferences<_$AppDatabase, $LocalSyncStatesTable, LocalSyncState>,
      ),
      LocalSyncState,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalProfilesTableTableManager get localProfiles =>
      $$LocalProfilesTableTableManager(_db, _db.localProfiles);
  $$LocalAppSettingsTableTableManager get localAppSettings =>
      $$LocalAppSettingsTableTableManager(_db, _db.localAppSettings);
  $$LocalDomainsTableTableManager get localDomains =>
      $$LocalDomainsTableTableManager(_db, _db.localDomains);
  $$LocalTasksTableTableManager get localTasks =>
      $$LocalTasksTableTableManager(_db, _db.localTasks);
  $$LocalRuntimeStatesTableTableManager get localRuntimeStates =>
      $$LocalRuntimeStatesTableTableManager(_db, _db.localRuntimeStates);
  $$LocalRoadmapsTableTableManager get localRoadmaps =>
      $$LocalRoadmapsTableTableManager(_db, _db.localRoadmaps);
  $$LocalActivitySegmentsTableTableManager get localActivitySegments =>
      $$LocalActivitySegmentsTableTableManager(_db, _db.localActivitySegments);
  $$LocalAttributionsTableTableManager get localAttributions =>
      $$LocalAttributionsTableTableManager(_db, _db.localAttributions);
  $$LocalContributionsTableTableManager get localContributions =>
      $$LocalContributionsTableTableManager(_db, _db.localContributions);
  $$LocalActivityReviewsTableTableManager get localActivityReviews =>
      $$LocalActivityReviewsTableTableManager(_db, _db.localActivityReviews);
  $$LocalEntityRecordsTableTableManager get localEntityRecords =>
      $$LocalEntityRecordsTableTableManager(_db, _db.localEntityRecords);
  $$LocalOutboxCommandsTableTableManager get localOutboxCommands =>
      $$LocalOutboxCommandsTableTableManager(_db, _db.localOutboxCommands);
  $$LocalSyncStatesTableTableManager get localSyncStates =>
      $$LocalSyncStatesTableTableManager(_db, _db.localSyncStates);
}
