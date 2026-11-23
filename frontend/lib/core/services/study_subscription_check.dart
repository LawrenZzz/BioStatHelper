import '../../shared/models/study_model.dart';
import 'api_client.dart';
import 'bilibili_service.dart';

/// Shared by the visible client and the Android headless worker. No UI state.
class StudySubscriptionCheck {
  StudySubscriptionCheck({required this.api, required this.bili});
  final ApiClient api;
  final BilibiliService bili;

  Future<List<String>> run(Iterable<StudySubscription> subscriptions,
      {bool historical = false, bool Function()? cancelled}) async {
    final failures = <String>[];
    for (final subscription
        in subscriptions.where((s) => s.enabled && s.source == 'bilibili')) {
      if (cancelled?.call() == true) break;
      try {
        await bili.initialize();
        for (final reverse in subscription.kind == 'collection' && !historical
            ? [false, true]
            : [false]) {
          var page = 1;
          while (page <= (historical ? 250 : 2)) {
            if (cancelled?.call() == true) break;
            final result = subscription.kind == 'collection'
                ? await bili.getCollectionVideos(
                    studyInt(subscription.sourceData['owner_mid']),
                    studyInt(subscription.sourceData['season_id']),
                    page: page,
                    reverse: reverse)
                : await bili.getUploaderVideos(
                    studyInt(subscription.sourceData['mid']),
                    page: page);
            if (cancelled?.call() == true) break;
            // Commit each page so a timed-out background job can resume safely.
            await api.post('/study/updates', data: {
              'subscription_id': subscription.id,
              'historical': historical,
              'updates': result.items
                  .map((video) => {
                        'title': video.title,
                        'thumbnail_url': video.cover,
                        'duration_seconds': video.duration.inSeconds,
                        'source_data': {
                          ...video.toSourceData(),
                          if (subscription.kind == 'collection')
                            'season_id': subscription.sourceData['season_id'],
                          if (subscription.kind == 'collection')
                            'owner_mid': subscription.sourceData['owner_mid'],
                        },
                        'published_at': (video.publishedAt ??
                                DateTime.fromMillisecondsSinceEpoch(0,
                                    isUtc: true))
                            .toIso8601String(),
                      })
                  .toList(),
            });
            if (!result.hasMore || result.items.isEmpty) break;
            page++;
          }
        }
      } catch (error) {
        failures.add('${subscription.name}：$error');
      }
    }
    return failures;
  }
}
