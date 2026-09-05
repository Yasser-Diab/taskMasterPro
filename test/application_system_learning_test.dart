import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmaster_pro/core/learning/application_system_learning.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('opt-in is explicit and defaults off', () async {
    final shared = await SharedPreferences.getInstance();
    final preferences = SharedPreferencesApplicationSystemLearningPreferences(
      shared,
    );

    expect(await preferences.isOptedIn(), isFalse);
    await preferences.setOptedIn(true);
    expect(await preferences.isOptedIn(), isTrue);
  });

  test('only a hashed basename or package identity leaves the device', () {
    final windowsPath = applicationLearningIdentity(
      platform: 'Windows',
      applicationIdentifier: r'C:\Private\Work\Example App.exe',
    );
    final windowsName = applicationLearningIdentity(
      platform: 'windows',
      applicationIdentifier: 'example app.exe',
    );
    final android = applicationLearningIdentity(
      platform: 'android',
      applicationIdentifier: 'Com.Example.App',
    );

    expect(windowsPath?.appKeyHash, windowsName?.appKeyHash);
    expect(windowsPath?.appKeyHash, hasLength(64));
    expect(windowsPath?.appKeyHash, isNot(contains('example')));
    expect(android?.appKeyHash, hasLength(64));
  });

  test('local remembered rule wins without any community request', () async {
    final fixture = await _fixture(optedIn: true);

    final result = await fixture.service.possibleSystemSuggestion(
      platform: 'windows',
      applicationIdentifier: 'example.exe',
      hasLocalRememberedRule: true,
    );

    expect(result, isNull);
    expect(fixture.gateway.lookupCount, 0);
  });

  test('disabled learning neither submits nor looks up', () async {
    final fixture = await _fixture(optedIn: false);

    await fixture.service.submitExplicitChoice(
      platform: 'windows',
      applicationIdentifier: 'example.exe',
      isSystemActivity: true,
    );
    final suggestion = await fixture.service.possibleSystemSuggestion(
      platform: 'windows',
      applicationIdentifier: 'example.exe',
      hasLocalRememberedRule: false,
    );

    expect(suggestion, isNull);
    expect(fixture.gateway.submitCount, 0);
    expect(fixture.gateway.lookupCount, 0);
  });

  test(
    'ballot token is stable for one app and unlinkable across apps',
    () async {
      final fixture = await _fixture(optedIn: true);

      await fixture.service.submitExplicitChoice(
        platform: 'windows',
        applicationIdentifier: 'one.exe',
        isSystemActivity: true,
      );
      await fixture.service.submitExplicitChoice(
        platform: 'windows',
        applicationIdentifier: 'one.exe',
        isSystemActivity: false,
      );
      await fixture.service.submitExplicitChoice(
        platform: 'windows',
        applicationIdentifier: 'two.exe',
        isSystemActivity: true,
      );

      expect(fixture.gateway.votes, hasLength(3));
      expect(
        fixture.gateway.votes[0].voterTokenHash,
        fixture.gateway.votes[1].voterTokenHash,
      );
      expect(
        fixture.gateway.votes[0].voterTokenHash,
        isNot(fixture.gateway.votes[2].voterTokenHash),
      );
      expect(fixture.gateway.votes[0].voterTokenHash, hasLength(64));
    },
  );

  test('only a threshold-passing consensus becomes a suggestion', () async {
    final fixture = await _fixture(
      optedIn: true,
      consensus: const ApplicationSystemConsensus(
        sampleSize: 24,
        systemShare: 0.88,
        confidenceLowerBound: 0.69,
        suggestsSystemActivity: true,
      ),
    );

    final first = await fixture.service.possibleSystemSuggestion(
      platform: 'windows',
      applicationIdentifier: 'service.exe',
      hasLocalRememberedRule: false,
    );
    final cached = await fixture.service.possibleSystemSuggestion(
      platform: 'windows',
      applicationIdentifier: 'service.exe',
      hasLocalRememberedRule: false,
    );

    expect(first?.sampleSize, 24);
    expect(cached?.suggestsSystemActivity, isTrue);
    expect(fixture.gateway.lookupCount, 1);
  });

  test(
    'sub-threshold evidence never creates a possible-system suggestion',
    () async {
      final fixture = await _fixture(
        optedIn: true,
        consensus: const ApplicationSystemConsensus(
          sampleSize: 20,
          systemShare: 0.7,
          confidenceLowerBound: 0.48,
          suggestsSystemActivity: false,
        ),
      );

      final result = await fixture.service.possibleSystemSuggestion(
        platform: 'android',
        applicationIdentifier: 'com.example.app',
        hasLocalRememberedRule: false,
      );

      expect(result, isNull);
      expect(fixture.gateway.lookupCount, 1);
    },
  );

  test(
    'category votes are opt-in, hashed, and never carry an app name',
    () async {
      final shared = await SharedPreferences.getInstance();
      final preferences = SharedPreferencesApplicationSystemLearningPreferences(
        shared,
      );
      await preferences.setOptedIn(true);
      final categoryGateway = _CategoryGateway();
      final service = ApplicationSystemLearningService(
        preferences: preferences,
        secretStore: _SecretStore(),
        gateway: _Gateway(null),
        cache: ApplicationSystemLearningCache(shared),
        categoryGateway: categoryGateway,
      );

      await service.submitExplicitClassification(
        platform: 'windows',
        applicationIdentifier: r'C:\Private\Work\Example App.exe',
        classification: 'supporting_work',
      );

      expect(categoryGateway.votes, hasLength(1));
      expect(categoryGateway.votes.single.appKeyHash, hasLength(64));
      expect(
        categoryGateway.votes.single.appKeyHash,
        isNot(contains('example')),
      );
      expect(categoryGateway.votes.single.category, 'productivity');
      expect(categoryGateway.votes.single.isUseful, isTrue);
    },
  );

  test('threshold-passing category evidence remains a proposal', () async {
    final shared = await SharedPreferences.getInstance();
    final preferences = SharedPreferencesApplicationSystemLearningPreferences(
      shared,
    );
    await preferences.setOptedIn(true);
    final service = ApplicationSystemLearningService(
      preferences: preferences,
      secretStore: _SecretStore(),
      gateway: _Gateway(null),
      cache: ApplicationSystemLearningCache(shared),
      categoryGateway: _CategoryGateway(
        const ApplicationCategoryConsensus(
          sampleSize: 24,
          category: 'development',
          isUseful: true,
          confidenceLowerBound: 0.69,
        ),
      ),
    );

    final suggestion = await service.possibleCategorySuggestion(
      platform: 'windows',
      applicationIdentifier: 'dart.exe',
      hasLocalRememberedRule: false,
    );

    expect(suggestion?.suggestedClassification, 'supporting_work');
  });

  test('the complete app taxonomy preserves an explicit music vote', () async {
    final shared = await SharedPreferences.getInstance();
    final preferences = SharedPreferencesApplicationSystemLearningPreferences(
      shared,
    );
    await preferences.setOptedIn(true);
    final categoryGateway = _CategoryGateway();
    final service = ApplicationSystemLearningService(
      preferences: preferences,
      secretStore: _SecretStore(),
      gateway: _Gateway(null),
      cache: ApplicationSystemLearningCache(shared),
      categoryGateway: categoryGateway,
    );

    await service.submitExplicitClassification(
      platform: 'android',
      applicationIdentifier: 'com.example.music',
      classification: 'direct_task_work',
      category: 'music_audio',
      isUseful: false,
    );

    expect(categoryGateway.votes, hasLength(1));
    expect(categoryGateway.votes.single.category, 'music_audio');
    expect(categoryGateway.votes.single.isUseful, isFalse);
    expect(
      ApplicationCategoryConsensus.supportedCategories,
      containsAll(<String>[
        'business',
        'health_fitness',
        'music_audio',
        'entertainment',
        'video_streaming',
        'games',
        'social',
        'news_media',
        'books_reference',
        'system',
        'other',
      ]),
    );
  });
}

Future<_Fixture> _fixture({
  required bool optedIn,
  ApplicationSystemConsensus? consensus,
}) async {
  final shared = await SharedPreferences.getInstance();
  final preferences = SharedPreferencesApplicationSystemLearningPreferences(
    shared,
  );
  await preferences.setOptedIn(optedIn);
  final gateway = _Gateway(consensus);
  return _Fixture(
    gateway,
    ApplicationSystemLearningService(
      preferences: preferences,
      secretStore: _SecretStore(),
      gateway: gateway,
      cache: ApplicationSystemLearningCache(shared),
    ),
  );
}

class _Fixture {
  const _Fixture(this.gateway, this.service);

  final _Gateway gateway;
  final ApplicationSystemLearningService service;
}

class _SecretStore implements ApplicationLearningSecretStore {
  @override
  Future<List<int>> readOrCreateSecret() async =>
      List<int>.generate(32, (index) => index);
}

class _Vote {
  const _Vote(this.appKeyHash, this.voterTokenHash);

  final String appKeyHash;
  final String voterTokenHash;
}

class _Gateway implements ApplicationSystemLearningGateway {
  _Gateway(this.consensus);

  final ApplicationSystemConsensus? consensus;
  final List<_Vote> votes = [];
  int submitCount = 0;
  int lookupCount = 0;

  @override
  Future<ApplicationSystemConsensus?> readConsensus({
    required String platform,
    required String appKeyHash,
  }) async {
    lookupCount += 1;
    return consensus;
  }

  @override
  Future<void> submitVote({
    required String platform,
    required String appKeyHash,
    required String voterTokenHash,
    required bool isSystemActivity,
  }) async {
    submitCount += 1;
    votes.add(_Vote(appKeyHash, voterTokenHash));
  }
}

class _CategoryVote {
  const _CategoryVote({
    required this.appKeyHash,
    required this.category,
    required this.isUseful,
  });

  final String appKeyHash;
  final String category;
  final bool isUseful;
}

class _CategoryGateway implements ApplicationCategoryLearningGateway {
  _CategoryGateway([this.consensus]);

  final ApplicationCategoryConsensus? consensus;
  final List<_CategoryVote> votes = [];

  @override
  Future<ApplicationCategoryConsensus?> readCategoryConsensus({
    required String platform,
    required String appKeyHash,
  }) async => consensus;

  @override
  Future<void> submitCategoryVote({
    required String platform,
    required String appKeyHash,
    required String voterTokenHash,
    required String category,
    required bool isUseful,
  }) async {
    votes.add(
      _CategoryVote(
        appKeyHash: appKeyHash,
        category: category,
        isUseful: isUseful,
      ),
    );
  }
}
