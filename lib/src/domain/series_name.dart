/// 系列名推断与繁简转换。
///
/// 上游 Han1meViewer 依赖 `playlistName` 字段，本站 `VideoDetail.playlist` 只是
/// 一组裸 `VideoCard`，没有系列名，只能从标题里剥掉集数标记后取前缀。
library;

/// 集数标记：`第1話`、`#2`、`_3`、`Vol.4`、`Part 5`、`(6)`、`【7】`，以及 `上巻`/`下巻`
/// `前編`/`後編` 这类卷标。
///
/// 注意这里**不锚定字符串末尾**：真实标题的集数标记后面常常还跟着副标题和字幕标签，
/// 例如「Tentacle and Witches ～第2話 プールの水で濡れてるんだから！～ [中文字幕]」。
/// 旧写法要求集数落在标题最后，导致这类标题一律识别不出系列名。
final _episodeMarker = RegExp(
  r'(?:第\s*\d+\s*[话話集回巻卷彈弹]'
  r'|(?:vol|volume|part|ep|episode|act|chapter|ch)\s*\.?\s*\d+'
  r'|#\s*\d+'
  r'|\d+\s*[话話集回巻卷彈弹]'
  // 卷标：上巻 / 下巻 / 前編 / 後編 / 中編 / 上集 / 下集。成人动画常用这种分卷写法，
  // 没有它的话「…THE ANIMATION 上巻」这类标题永远凑不出系列名。
  r'|[上前中下後]\s*[巻卷編编篇集]'
  r'|(?:part|vol)\s*[ⅠⅡⅢⅣ]'
  r')',
  caseSensitive: false,
);

/// 尾部的噪声标签：`[中文字幕]`、`[1080P]`、`(無修正)`、`【新作】` 等。
/// 这类方括号内容不参与系列名，先剥掉再找集数标记。
final _noiseTag = RegExp(r'[\s]*[\(\[【（]\s*[^\(\)\[\]【】（）]{1,12}\s*[\)\]】）][\s]*$');

/// 纯数字/罗马数字后缀，例如 ` 2`、` Ⅳ`、`_12`。
/// 罗马数字这里一并接受 Unicode 码点（Ⅳ 之类）和 ASCII 写法（IV）。
final _trailingNumber = RegExp(
  r'[\s\-_·・]*(\d{1,3}|[ivxlcdm]{1,5}|[\u2160-\u2188]+)\s*$',
  caseSensitive: false,
);

/// 尾部括号里只有数字，例如 `标题 (2)`。
final _trailingBracket = RegExp(r'[\s]*[\(\[【（]\s*\d{1,3}\s*[\)\]】）]\s*$');

/// 从影片标题推断系列名。推断不出可靠前缀时返回 null。
///
/// 做法是「找到第一个集数标记 → 取它前面的部分 → 剥掉尾部残留的括号与分隔符」——
/// 这是 Sonarr / Prowlarr 一类剧集刮削器的通行思路，比在标题尾部做锚定匹配稳得多。
///
/// 顺序很重要：必须先定位集数再剥括号。反过来的话，像「呪いの指輪 【第01話】[中文字幕]」
/// 这种集数**被括号包住**的标题，括号会连同集数一起被当成噪声剥掉，切分点就没了。
String? inferSeriesName(String? title) {
  final text = title?.trim() ?? '';
  if (text.isEmpty) return null;

  // 1) 定位第一个集数标记，取它前面的部分当系列名。
  final marker = _episodeMarker.firstMatch(text);
  if (marker != null) {
    final name = _cleanHead(text.substring(0, marker.start));
    if (name.length >= 2) return name;
  }

  // 2) 没有「第N話」这类标记时，退回处理纯数字/括号编号后缀
  //    （`某系列 (6)`、`某系列【7】`、`某系列_2`、`某系列 Ⅳ`）。
  //
  //    注意顺序：先试 `_trailingBracket`（括号里只有数字），因为 `_noiseTag` 会把
  //    `【7】` 当成普通噪声标签一并吞掉，之后 `strippedNumber` 就永远是 false，
  //    `某系列【7】` 会被错判成非系列。
  final head = _cleanHead(text.replaceFirst(_trailingBracket, ''));
  if (head != text.trim() && head.length >= 2) return head;

  final stripped = _stripNoiseTags(text);
  var numbered = stripped;
  var strippedNumber = false;
  for (final pattern in [_trailingNumber]) {
    final next = numbered.replaceFirst(pattern, '').trim();
    if (next == numbered) continue;
    if (next.length < 2) break;
    numbered = next;
    strippedNumber = true;
  }
  // 关键：必须真的剥掉了编号才算系列名。只剥掉 `[中文字幕]` 之类的噪声标签不算——
  // 例如「ビュアホリック ～…～ THE ANIMATION 上巻 [中文字幕]」剥完字幕标签后仍不等于
  // 原标题，但它根本没有集数，不该被当成系列。
  if (!strippedNumber) return null;
  final name = _cleanHead(numbered);
  if (name.length < 2) return null;
  return name;
}

/// 反复剥掉尾部的 `[标签]` / `(标签)`（字幕、画质、修正说明之类）。
String _stripNoiseTags(String value) {
  var result = value;
  for (var i = 0; i < 4; i++) {
    final next = result.replaceFirst(_noiseTag, '').trim();
    if (next == result || next.isEmpty) break;
    result = next;
  }
  return result;
}

/// 清掉系列名尾部残留的括号骨架与分隔符。
String _cleanHead(String value) {
  var result = value.trim();
  for (var i = 0; i < 4; i++) {
    final next = result.replaceFirst(RegExp(r'[\s\-_·・.,،～~]+$'), '').trim();
    final opened = next.replaceFirst(RegExp(r'[\(\[【（]\s*$'), '').trim();
    if (opened == result) break;
    result = opened;
  }
  return result;
}

/// 组名候选：系列名优先，取不到就退回影片标题。
String suggestGroupName({required String title, String? seriesName, required bool useSeriesName}) {
  if (!useSeriesName) return title.trim();
  final series = seriesName?.trim() ?? '';
  if (series.isEmpty) return title.trim();
  return series;
}

/// 高频简繁对照。只覆盖组名这类短文本，不做通用转换。
const _traditionalMap = <String, String>{
  '软': '軟', '体': '體', '画': '畫', '动': '動', '无': '無', '学': '學',
  '码': '碼', '剧': '劇', '电': '電', '视': '視', '声': '聲', '优': '優',
  '质': '質', '频': '頻', '网': '網', '络': '絡', '关': '關', '键': '鍵',
  '开': '開', '闭': '閉', '门': '門', '问': '問', '题': '題', '这': '這',
  '个': '個', '们': '們', '时': '時', '间': '間', '长': '長', '会': '會',
  '为': '為', '对': '對', '过': '過', '还': '還', '进': '進', '说': '說',
  '话': '話', '语': '語', '读': '讀', '写': '寫', '听': '聽', '见': '見',
  '现': '現', '场': '場', '发': '發', '变': '變', '换': '換', '爱': '愛',
  '恋': '戀', '欢': '歡', '乐': '樂', '绪': '緒', '续': '續', '结': '結',
  '级': '級', '纪': '紀', '录': '錄', '档': '檔', '术': '術', '艺': '藝',
  '馆': '館', '图': '圖', '书': '書', '报': '報', '纸': '紙', '签': '簽',
  '约': '約', '绑': '綁', '联': '聯', '系': '係', '统': '統', '类': '類',
  '别': '別', '号': '號', '标': '標', '页': '頁', '览': '覽', '询': '詢',
  '检': '檢', '测': '測', '试': '試', '验': '驗', '证': '證', '确': '確',
  '认': '認', '误': '誤', '错': '錯', '败': '敗', '坏': '壞', '旧': '舊',
  '复': '復', '杂': '雜', '简': '簡', '单': '單', '双': '雙', '数': '數',
  '据': '據', '库': '庫', '储': '儲', '盘': '盤', '内': '內', '里': '裡',
  '边': '邊', '头': '頭', '层': '層', '设': '設', '备': '備', '项': '項',
  '删': '刪', '创': '創', '组': '組', '静': '靜', '暂': '暫', '载': '載',
  '传': '傳', '程': '程', '应': '應', '义': '義', '默': '默',
};

/// 组名用的简易简→繁转换。非汉字与未收录字原样保留。
String toTraditionalForGroupName(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_traditionalMap[char] ?? char);
  }
  return buffer.toString();
}
