import 'file_diff.dart';

class SessionSummary {
  final int additions;
  final int deletions;
  final int files;
  final List<FileDiff>? diffs;

  SessionSummary({
    required this.additions,
    required this.deletions,
    required this.files,
    this.diffs,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      additions: json['additions'] as int,
      deletions: json['deletions'] as int,
      files: json['files'] as int,
      diffs: (json['diffs'] as List<dynamic>?)
          ?.map((e) => FileDiff.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'additions': additions,
      'deletions': deletions,
      'files': files,
      if (diffs != null) 'diffs': diffs!.map((e) => e.toJson()).toList(),
    };
  }
}

class SessionShare {
  final String url;

  SessionShare({required this.url});

  factory SessionShare.fromJson(Map<String, dynamic> json) {
    return SessionShare(url: json['url'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'url': url};
  }
}

class SessionTime {
  final int created;
  final int updated;
  final int? compacting;
  final int? archived;

  SessionTime({
    required this.created,
    required this.updated,
    this.compacting,
    this.archived,
  });

  factory SessionTime.fromJson(Map<String, dynamic> json) {
    return SessionTime(
      created: json['created'] as int,
      updated: json['updated'] as int,
      compacting: json['compacting'] as int?,
      archived: json['archived'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'created': created,
      'updated': updated,
      if (compacting != null) 'compacting': compacting,
      if (archived != null) 'archived': archived,
    };
  }
}

class SessionRevert {
  final String messageID;
  final String? partID;
  final String? snapshot;
  final String? diff;

  SessionRevert({
    required this.messageID,
    this.partID,
    this.snapshot,
    this.diff,
  });

  factory SessionRevert.fromJson(Map<String, dynamic> json) {
    return SessionRevert(
      messageID: json['messageID'] as String,
      partID: json['partID'] as String?,
      snapshot: json['snapshot'] as String?,
      diff: json['diff'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageID': messageID,
      if (partID != null) 'partID': partID,
      if (snapshot != null) 'snapshot': snapshot,
      if (diff != null) 'diff': diff,
    };
  }
}

class Session {
  final String id;
  final String slug;
  final String projectID;
  final String directory;
  final String? parentID;
  final SessionSummary? summary;
  final SessionShare? share;
  final String title;
  final String version;
  final SessionTime time;
  final SessionRevert? revert;

  Session({
    required this.id,
    required this.slug,
    required this.projectID,
    required this.directory,
    this.parentID,
    this.summary,
    this.share,
    required this.title,
    required this.version,
    required this.time,
    this.revert,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      slug: json['slug'] as String,
      projectID: json['projectID'] as String,
      directory: json['directory'] as String,
      parentID: json['parentID'] as String?,
      summary: json['summary'] != null
          ? SessionSummary.fromJson(json['summary'] as Map<String, dynamic>)
          : null,
      share: json['share'] != null
          ? SessionShare.fromJson(json['share'] as Map<String, dynamic>)
          : null,
      title: json['title'] as String,
      version: json['version'] as String,
      time: SessionTime.fromJson(json['time'] as Map<String, dynamic>),
      revert: json['revert'] != null
          ? SessionRevert.fromJson(json['revert'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'projectID': projectID,
      'directory': directory,
      if (parentID != null) 'parentID': parentID,
      if (summary != null) 'summary': summary!.toJson(),
      if (share != null) 'share': share!.toJson(),
      'title': title,
      'version': version,
      'time': time.toJson(),
      if (revert != null) 'revert': revert!.toJson(),
    };
  }
}
