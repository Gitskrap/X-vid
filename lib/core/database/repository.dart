import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'entities.dart';
import '../models/tweet.dart';
import '../models/local_video_reaction.dart';
import '../../features/settings/settings_provider.dart';

const String tableAccounts = 'accounts';
const String tableSubscriptions = 'subscriptions';
const String tableCachedMedia = 'cached_media';
const String tableHashtags = 'hashtags';
const String tableLocalReactions = 'local_video_reactions';

class Repository {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    String path;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      path = inMemoryDatabasePath;
    } else {
      path = join(await getDatabasesPath(), 'xflow.db');
    }
    return await openDatabase(
      path,
      version: 12,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE $tableAccounts (id TEXT PRIMARY KEY, screen_name TEXT, rest_id TEXT, auth_header TEXT)',
        );
        await db.execute(
          'CREATE TABLE $tableSubscriptions (id TEXT PRIMARY KEY, screen_name TEXT, name TEXT, profile_image_url TEXT, description TEXT, followers_count INTEGER, following_count INTEGER)',
        );
        await db.execute(
          'CREATE TABLE $tableHashtags (tag TEXT PRIMARY KEY, added_at INTEGER)',
        );
        await db.execute('''
          CREATE TABLE $tableCachedMedia (
            id TEXT PRIMARY KEY,
            text TEXT,
            user_handle TEXT,
            user_avatar_url TEXT,
            media_key TEXT,
            media_urls TEXT,
            thumbnail_url TEXT,
            is_video INTEGER,
            created_at INTEGER,
            favorite_count INTEGER,
            reply_count INTEGER,
            is_liked INTEGER,
            played_count INTEGER DEFAULT 0,
            last_played_at INTEGER,
            duration_watched INTEGER DEFAULT 0,
            last_suggested_at INTEGER,
            retrieved_via TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_discovery_lookup ON $tableCachedMedia (played_count, created_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_media_key ON $tableCachedMedia (media_key)',
        );
        await db.execute(
          'CREATE INDEX idx_suggested ON $tableCachedMedia (last_suggested_at)',
        );
        await db.execute('''
          CREATE TABLE $tableLocalReactions (
            video_id TEXT PRIMARY KEY,
            reaction INTEGER NOT NULL CHECK (reaction IN (-1, 1)),
            caption TEXT NOT NULL,
            author TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db
              .execute('ALTER TABLE $tableAccounts ADD COLUMN rest_id TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS $tableSubscriptions (id TEXT PRIMARY KEY, screen_name TEXT, name TEXT, profile_image_url TEXT)',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE $tableSubscriptions ADD COLUMN description TEXT');
          await db.execute(
              'ALTER TABLE $tableSubscriptions ADD COLUMN followers_count INTEGER');
          await db.execute(
              'ALTER TABLE $tableSubscriptions ADD COLUMN following_count INTEGER');
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableCachedMedia (
              id TEXT PRIMARY KEY,
              text TEXT,
              user_handle TEXT,
              user_avatar_url TEXT,
              media_urls TEXT,
              thumbnail_url TEXT,
              is_video INTEGER,
              created_at INTEGER,
              played_count INTEGER DEFAULT 0,
              last_played_at INTEGER,
              duration_watched INTEGER DEFAULT 0
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_discovery_lookup ON $tableCachedMedia (played_count, created_at DESC)',
          );
        }
        if (oldVersion < 7) {
          await db.execute(
              'ALTER TABLE $tableCachedMedia ADD COLUMN media_key TEXT');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_media_key ON $tableCachedMedia (media_key)');
        }
        if (oldVersion < 8) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS $tableHashtags (tag TEXT PRIMARY KEY, added_at INTEGER)',
          );
        }
        if (oldVersion < 9) {
          await db.execute(
              'ALTER TABLE $tableCachedMedia ADD COLUMN last_suggested_at INTEGER');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_suggested ON $tableCachedMedia (last_suggested_at)');
        }
        if (oldVersion < 10) {
          // Nullable columns: NULL means the value has never been retrieved.
          await db.execute(
            'ALTER TABLE $tableCachedMedia ADD COLUMN favorite_count INTEGER');
          await db.execute(
            'ALTER TABLE $tableCachedMedia ADD COLUMN reply_count INTEGER');
          await db.execute(
            'ALTER TABLE $tableCachedMedia ADD COLUMN is_liked INTEGER');
        }
        if (oldVersion < 11) {
          await db.execute(
            'ALTER TABLE $tableCachedMedia ADD COLUMN retrieved_via TEXT');
        }
        if (oldVersion < 12) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableLocalReactions (
              video_id TEXT PRIMARY KEY,
              reaction INTEGER NOT NULL CHECK (reaction IN (-1, 1)),
              caption TEXT NOT NULL,
              author TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        }
      },
    );
  }

  /// Independent local preferences, intentionally unrelated to X favourites.
  static Future<Map<String, LocalVideoReaction>>
      getLocalVideoReactions() async {
    final db = await database;
    final rows = await db.query(tableLocalReactions);
    return {
      for (final row in rows)
        row['video_id'] as String: LocalVideoReaction(
          videoId: row['video_id'] as String,
          value: row['reaction'] as int,
          caption: row['caption'] as String,
          author: row['author'] as String,
        ),
    };
  }

  static Future<void> setLocalVideoReaction(Tweet tweet, int reaction) async {
    if (reaction != -1 && reaction != 0 && reaction != 1) {
      throw ArgumentError.value(reaction, 'reaction');
    }
    final db = await database;
    if (reaction == 0) {
      await db.delete(tableLocalReactions,
          where: 'video_id = ?', whereArgs: [tweet.id]);
      return;
    }
    await db.insert(
      tableLocalReactions,
      {
        'video_id': tweet.id,
        'reaction': reaction,
        'caption': tweet.text,
        'author': tweet.userHandle,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> clearLocalVideoReactions() async {
    final db = await database;
    await db.delete(tableLocalReactions);
  }

  static Future<void> addHashtag(String tag) async {
    final db = await database;
    await db.insert(
      tableHashtags,
      {'tag': tag, 'added_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<String>> getHashtags() async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query(tableHashtags, orderBy: 'added_at DESC');
    return List.generate(maps.length, (i) => maps[i]['tag'] as String);
  }

  static Future<void> deleteHashtag(String tag) async {
    final db = await database;
    await db.delete(tableHashtags, where: 'tag = ?', whereArgs: [tag]);
  }

  static Future<void> insertAccount(Account account) async {
    final db = await database;
    // Keep one saved X session per handle when the user reconnects.
    await db.delete(tableAccounts,
      where: 'LOWER(screen_name) = LOWER(?) AND id <> ?',
      whereArgs: [account.screenName, account.id]);
    await db.insert(
      tableAccounts,
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Account>> getAccounts() async {
    final db = await database;
    final maps = await db.query(tableAccounts, orderBy: 'rowid DESC');
    return maps.map(Account.fromMap).toList();
  }

  static Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete(tableAccounts, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> insertSubscription(Subscription sub) async {
    final db = await database;
    await db.insert(
      tableSubscriptions,
      sub.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> insertSubscriptions(List<Subscription> subs) async {
    final db = await database;
    final batch = db.batch();
    for (var sub in subs) {
      batch.insert(tableSubscriptions, sub.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Subscription>> getSubscriptions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(tableSubscriptions);
    return List.generate(maps.length, (i) {
      return Subscription.fromMap(maps[i]);
    });
  }

  static Future<void> clearSubscriptions() async {
    final db = await database;
    await db.delete(tableSubscriptions);
  }

  static Future<void> insertCachedMedia(List<Tweet> tweets) async {
    final db = await database;
    final batch = db.batch();
    for (var tweet in tweets) {
      batch.insert(
        tableCachedMedia,
        {
          'id': tweet.id,
          'text': tweet.text,
          'user_handle': tweet.userHandle,
          'user_avatar_url': tweet.userAvatarUrl,
          'media_key': tweet.mediaKey,
          'media_urls': jsonEncode(tweet.mediaUrls),
          'thumbnail_url': tweet.thumbnailUrl,
          'retrieved_via': tweet.retrievedVia,
          'is_video': tweet.isVideo ? 1 : 0,
          'created_at': tweet.createdAt?.millisecondsSinceEpoch,
          'favorite_count': tweet.favoriteCountKnown ? tweet.favoriteCount : null,
          'reply_count': tweet.replyCountKnown ? tweet.replyCount : null,
          'is_liked': tweet.isLikedKnown ? (tweet.isLiked ? 1 : 0) : null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      // Update only newly retrieved metadata. Keep played_count, history and
      // any reliable previously cached metric if X omitted it this time.
      final updates = <String, Object?>{};
      if (tweet.retrievedVia != null) {
        updates['retrieved_via'] = tweet.retrievedVia;
      }
      if (tweet.favoriteCountKnown) {
        updates['favorite_count'] = tweet.favoriteCount;
      }
      if (tweet.replyCountKnown) {
        updates['reply_count'] = tweet.replyCount;
      }
      if (tweet.isLikedKnown) {
        updates['is_liked'] = tweet.isLiked ? 1 : 0;
      }
      if (tweet.createdAt != null) {
        updates['created_at'] = tweet.createdAt!.millisecondsSinceEpoch;
      }
      if (updates.isNotEmpty) {
        batch.update(
          tableCachedMedia,
          updates,
          where: 'id = ?',
          whereArgs: [tweet.id],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Tweet>> getUnplayedCachedMedia(int limit,
      {Set<MediaFilter>? filters, Set<String>? allowedHandles}) async {
    if (allowedHandles != null && allowedHandles.isEmpty) return [];
    final db = await database;

    // Use a subquery to exclude any tweets whose media_key has been played elsewhere
    String whereClause = 'played_count = 0';
    whereClause +=
        ' AND (media_key IS NULL OR media_key NOT IN (SELECT media_key FROM $tableCachedMedia WHERE played_count > 0 AND media_key IS NOT NULL))';

    List<dynamic> whereArgs = [];
    if (allowedHandles != null) {
      whereClause += " AND LOWER(REPLACE(user_handle, '@', '')) IN "
          "(${List.filled(allowedHandles.length, '?').join(',')})";
      whereArgs.addAll(allowedHandles);
    }

    if (filters != null && filters.isNotEmpty) {
      final conditions = <String>[];
      for (final filter in filters) {
        switch (filter) {
          case MediaFilter.video:
            conditions.add('is_video = 1');
            break;
          case MediaFilter.image:
            conditions.add('(media_urls != "[]" AND is_video = 0)');
            break;
          case MediaFilter.text:
            conditions.add('media_urls = "[]"');
            break;
        }
      }
      if (conditions.isNotEmpty) {
        whereClause += ' AND (${conditions.join(' OR ')})';
      }
    }

    final List<Map<String, dynamic>> maps = await db.query(
      tableCachedMedia,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'last_suggested_at ASC',
      limit: limit * 2,
    );

    if (maps.isEmpty) return [];

    final results = List.generate(maps.length, (i) {
      return Tweet(
        id: maps[i]['id'] as String,
        text: maps[i]['text'] as String,
        userHandle: maps[i]['user_handle'] as String,
        userAvatarUrl: maps[i]['user_avatar_url'] as String?,
        mediaKey: maps[i]['media_key'] as String?,
        mediaUrls:
            List<String>.from(jsonDecode(maps[i]['media_urls'] as String)),
        thumbnailUrl: maps[i]['thumbnail_url'] as String?,
        retrievedVia: maps[i]['retrieved_via'] as String?,
        isVideo: (maps[i]['is_video'] as int) == 1,
        favoriteCount: (maps[i]['favorite_count'] as int?) ?? 0,
        replyCount: (maps[i]['reply_count'] as int?) ?? 0,
        isLiked: maps[i]['is_liked'] == 1,
        favoriteCountKnown: maps[i]['favorite_count'] != null,
        replyCountKnown: maps[i]['reply_count'] != null,
        isLikedKnown: maps[i]['is_liked'] != null,
        createdAt: maps[i]['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(maps[i]['created_at'] as int)
            : null,
      );
    });

    // Mark these as suggested
    if (results.isNotEmpty) {
      final ids = results.map((t) => t.id).toList();
      await markAsSuggested(ids);
    }

    return (results..shuffle()).take(limit).toList();
  }

  static Future<List<Tweet>> getCachedMediaCandidates(
    int limit, {
    required bool avoidWatchedContent,
    Set<MediaFilter>? filters,
    Set<String>? allowedHandles,
  }) async {
    if (allowedHandles != null && allowedHandles.isEmpty) return [];
    if (avoidWatchedContent) {
      return getUnplayedCachedMedia(limit,
          filters: filters, allowedHandles: allowedHandles);
    }

    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;
    if (allowedHandles != null) {
      whereClause = "LOWER(REPLACE(user_handle, '@', '')) IN "
          "(${List.filled(allowedHandles.length, '?').join(',')})";
      whereArgs = allowedHandles.toList();
    }

    if (filters != null && filters.isNotEmpty) {
      final conditions = <String>[];
      for (final filter in filters) {
        switch (filter) {
          case MediaFilter.video:
            conditions.add('is_video = 1');
            break;
          case MediaFilter.image:
            conditions.add('(media_urls != "[]" AND is_video = 0)');
            break;
          case MediaFilter.text:
            conditions.add('media_urls = "[]"');
            break;
        }
      }
      if (conditions.isNotEmpty) {
        final filterClause = '(${conditions.join(' OR ')})';
        whereClause = whereClause == null
            ? filterClause
            : '$whereClause AND $filterClause';
      }
    }

    final List<Map<String, dynamic>> maps = await db.query(
      tableCachedMedia,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'last_suggested_at ASC',
      limit: limit * 2, // Fetch more to allow for shuffling
    );

    final results = List.generate(maps.length, (i) {
      return Tweet(
        id: maps[i]['id'] as String,
        text: maps[i]['text'] as String,
        userHandle: maps[i]['user_handle'] as String,
        userAvatarUrl: maps[i]['user_avatar_url'] as String?,
        mediaKey: maps[i]['media_key'] as String?,
        mediaUrls:
            List<String>.from(jsonDecode(maps[i]['media_urls'] as String)),
        thumbnailUrl: maps[i]['thumbnail_url'] as String?,
        retrievedVia: maps[i]['retrieved_via'] as String?,
        isVideo: (maps[i]['is_video'] as int) == 1,
        favoriteCount: (maps[i]['favorite_count'] as int?) ?? 0,
        replyCount: (maps[i]['reply_count'] as int?) ?? 0,
        isLiked: maps[i]['is_liked'] == 1,
        favoriteCountKnown: maps[i]['favorite_count'] != null,
        replyCountKnown: maps[i]['reply_count'] != null,
        isLikedKnown: maps[i]['is_liked'] != null,
        createdAt: maps[i]['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(maps[i]['created_at'] as int)
            : null,
      );
    });

    // Mark these as suggested so they go to the back of the queue
    if (results.isNotEmpty) {
      final ids = results.map((t) => t.id).toList();
      await markAsSuggested(ids);
    }

    return (results..shuffle()).take(limit).toList();
  }

  static Future<void> markAsSuggested(List<String> ids) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(
        tableCachedMedia,
        {'last_suggested_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<Map<String, int>> getPlayedCountsByUser() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT LOWER(REPLACE(user_handle, '@', '')) AS normalized_handle,
             SUM(played_count) AS total_played
      FROM $tableCachedMedia
      GROUP BY normalized_handle
    ''');

    final out = <String, int>{};
    for (final row in rows) {
      final handle = row['normalized_handle'] as String?;
      if (handle == null || handle.isEmpty) continue;
      out[handle] = (row['total_played'] as int?) ?? 0;
    }
    return out;
  }

  static Future<List<Tweet>> getUserCachedMedia(String userHandle, int limit,
      {Set<MediaFilter>? filters}) async {
    final db = await database;
    final rawHandle =
        userHandle.startsWith('@') ? userHandle.substring(1) : userHandle;
    final normalizedHandle = rawHandle.toLowerCase();

    String whereClause = "LOWER(REPLACE(user_handle, '@', '')) = ?";
    List<dynamic> whereArgs = [normalizedHandle];

    if (filters != null && filters.isNotEmpty) {
      final conditions = <String>[];
      for (final filter in filters) {
        switch (filter) {
          case MediaFilter.video:
            conditions.add('is_video = 1');
            break;
          case MediaFilter.image:
            conditions.add('(media_urls != "[]" AND is_video = 0)');
            break;
          case MediaFilter.text:
            conditions.add('media_urls = "[]"');
            break;
        }
      }
      if (conditions.isNotEmpty) {
        whereClause += ' AND (${conditions.join(' OR ')})';
      }
    }

    final List<Map<String, dynamic>> maps = await db.query(
      tableCachedMedia,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return List.generate(maps.length, (i) {
      return Tweet(
        id: maps[i]['id'] as String,
        text: maps[i]['text'] as String,
        userHandle: maps[i]['user_handle'] as String,
        userAvatarUrl: maps[i]['user_avatar_url'] as String?,
        mediaKey: maps[i]['media_key'] as String?,
        mediaUrls:
            List<String>.from(jsonDecode(maps[i]['media_urls'] as String)),
        thumbnailUrl: maps[i]['thumbnail_url'] as String?,
        retrievedVia: maps[i]['retrieved_via'] as String?,
        isVideo: (maps[i]['is_video'] as int) == 1,
        favoriteCount: (maps[i]['favorite_count'] as int?) ?? 0,
        replyCount: (maps[i]['reply_count'] as int?) ?? 0,
        isLiked: maps[i]['is_liked'] == 1,
        favoriteCountKnown: maps[i]['favorite_count'] != null,
        replyCountKnown: maps[i]['reply_count'] != null,
        isLikedKnown: maps[i]['is_liked'] != null,
        createdAt: maps[i]['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(maps[i]['created_at'] as int)
            : null,
      );
    });
  }

  static Future<List<Tweet>> getHashtagCachedMedia(String hashtag, int limit,
      {Set<MediaFilter>? filters}) async {
    final db = await database;

    String whereClause = 'text LIKE ?';
    List<dynamic> whereArgs = ['%$hashtag%'];

    if (filters != null && filters.isNotEmpty) {
      final conditions = <String>[];
      for (final filter in filters) {
        switch (filter) {
          case MediaFilter.video:
            conditions.add('is_video = 1');
            break;
          case MediaFilter.image:
            conditions.add('(media_urls != "[]" AND is_video = 0)');
            break;
          case MediaFilter.text:
            conditions.add('media_urls = "[]"');
            break;
        }
      }
      if (conditions.isNotEmpty) {
        whereClause += ' AND (${conditions.join(' OR ')})';
      }
    }

    final List<Map<String, dynamic>> maps = await db.query(
      tableCachedMedia,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return List.generate(maps.length, (i) {
      return Tweet(
        id: maps[i]['id'] as String,
        text: maps[i]['text'] as String,
        userHandle: maps[i]['user_handle'] as String,
        userAvatarUrl: maps[i]['user_avatar_url'] as String?,
        mediaKey: maps[i]['media_key'] as String?,
        mediaUrls:
            List<String>.from(jsonDecode(maps[i]['media_urls'] as String)),
        thumbnailUrl: maps[i]['thumbnail_url'] as String?,
        retrievedVia: maps[i]['retrieved_via'] as String?,
        isVideo: (maps[i]['is_video'] as int) == 1,
        favoriteCount: (maps[i]['favorite_count'] as int?) ?? 0,
        replyCount: (maps[i]['reply_count'] as int?) ?? 0,
        isLiked: maps[i]['is_liked'] == 1,
        favoriteCountKnown: maps[i]['favorite_count'] != null,
        replyCountKnown: maps[i]['reply_count'] != null,
        isLikedKnown: maps[i]['is_liked'] != null,
        createdAt: maps[i]['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(maps[i]['created_at'] as int)
            : null,
      );
    });
  }

  static Future<void> markMediaAsPlayed(String id) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE $tableCachedMedia 
      SET played_count = played_count + 1, last_played_at = ? 
      WHERE id = ?
    ''', [DateTime.now().millisecondsSinceEpoch, id]);
  }

  static Future<int> getMediaPlayedCount(String id) async {
    final db = await database;
    final maps = await db.query(
      tableCachedMedia,
      columns: ['played_count'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return (maps.first['played_count'] as int?) ?? 0;
    }
    return 0;
  }

  static Future<int> getUserPlayedCount(String userHandle) async {
    final db = await database;
    final normalized = userHandle.replaceAll('@', '').toLowerCase();
    final rows = await db.rawQuery('''
      SELECT SUM(played_count) AS total_played
      FROM $tableCachedMedia
      WHERE LOWER(REPLACE(user_handle, '@', '')) = ?
    ''', [normalized]);

    if (rows.isNotEmpty) {
      return (rows.first['total_played'] as int?) ?? 0;
    }
    return 0;
  }

  static Future<int> getCachedMediaCount() async {
    final db = await database;
    final countSq =
        await db.rawQuery('SELECT COUNT(*) as count FROM $tableCachedMedia');
    return countSq.first['count'] as int;
  }

  static Future<void> pruneCachedMedia({int threshold = 5000}) async {
    final db = await database;

    // 1. Delete by age: Remove anything older than 7 days
    final sevenDaysAgo =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    await db.delete(
      tableCachedMedia,
      where: 'created_at < ?',
      whereArgs: [sevenDaysAgo],
    );

    // 2. Delete by count: If still over threshold, delete oldest watched items
    final countSq =
        await db.rawQuery('SELECT COUNT(*) as count FROM $tableCachedMedia');
    final count = countSq.first['count'] as int;

    if (count > threshold) {
      final deleteCount = count - threshold;
      await db.execute('''
        DELETE FROM $tableCachedMedia 
        WHERE id IN (
          SELECT id FROM $tableCachedMedia 
          ORDER BY COALESCE(last_played_at, created_at) ASC 
          LIMIT ?
        )
      ''', [deleteCount]);
    }
  }

  static Future<void> purgeSeenMetadata() async {
    final db = await database;
    await db.delete(
      tableCachedMedia,
      where: 'played_count > 0',
    );
  }

  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
