class GetchuPreviewFeed {
  const GetchuPreviewFeed({required this.month, required this.groups});

  final String month;
  final List<GetchuPreviewGroup> groups;
}

class GetchuPreviewGroup {
  const GetchuPreviewGroup({required this.releaseDate, required this.items});

  final String releaseDate;
  final List<GetchuPreviewItem> items;
}

class GetchuPreviewItem {
  const GetchuPreviewItem({required this.id, required this.title, required this.detailUrl, this.brand, this.coverUrl, this.price});

  final String id;
  final String title;
  final String detailUrl;
  final String? brand;
  final String? coverUrl;
  final String? price;
}

class GetchuPreviewDetail {
  const GetchuPreviewDetail({
    required this.id,
    required this.title,
    required this.productUrl,
    required this.trailers,
    required this.sections,
    required this.sampleImages,
    required this.seriesItems,
    this.brand,
    this.coverUrl,
    this.description,
    this.releaseDate,
    this.price,
  });

  final String id;
  final String title;
  final String productUrl;
  final String? brand;
  final String? coverUrl;
  final String? description;
  final String? releaseDate;
  final String? price;
  final List<GetchuPreviewTrailer> trailers;
  final List<GetchuPreviewSection> sections;
  final List<String> sampleImages;
  final List<GetchuPreviewItem> seriesItems;
}

/// 一条预告片：可能带多档清晰度（第三方播放器会把 1080p/720p/480p 都列出来）。
class GetchuPreviewTrailer {
  const GetchuPreviewTrailer({required this.sources, this.posterUrl});

  final List<GetchuPreviewSource> sources;
  final String? posterUrl;
}

class GetchuPreviewSource {
  const GetchuPreviewSource({required this.url, this.quality});

  final String url;
  final String? quality;
}

class GetchuPreviewSection {
  const GetchuPreviewSection({required this.title, required this.body});

  final String title;
  final String body;
}
