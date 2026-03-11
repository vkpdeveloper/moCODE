class VcsInfo {
  final String branch;

  VcsInfo({required this.branch});

  factory VcsInfo.fromJson(Map<String, dynamic> json) {
    return VcsInfo(branch: json['branch'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'branch': branch};
  }
}
