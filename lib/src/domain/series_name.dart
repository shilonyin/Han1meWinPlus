/// 系列名推断与繁简转换。
///
/// 上游 Han1meViewer 依赖 `playlistName` 字段，本站 `VideoDetail.playlist` 只是
/// 一组裸 `VideoCard`，没有系列名，只能从标题里剥掉集数标记后取前缀。
library;

/// 尾部集数标记：`第1話`、`#2`、`_3`、`Vol.4`、`Part 5`、`(6)`、`【7】` 等。
final _episodeSuffix = RegExp(
  r'(?:[\s\-_·・.,،]*'
  r'(?:第\s*\d+\s*[话話集回巻卷彈弹]'
  r'|(?:vol|volume|part|ep|episode|act|chapter|ch)\s*\.?\s*\d+'
  r'|#\s*\d+'
  r'|\d+\s*[话話集回巻卷彈弹]'
  r'))'
  r'[\s\-_·・.,،]*(?:[\(\[【（]\s*\d+\s*[\)\]】）])?\s*$',
  caseSensitive: false,
);

/// 纯数字/罗马数字后缀，例如 ` 2`、` Ⅳ`、`_12`。
/// 罗马数字这里一并接受 Unicode 码点（Ⅳ 之类）和 ASCII 写法（IV）。
final _trailingNumber = RegExp(
  r'[\s\-_·・]*(\d{1,3}|[ivxlcdm]{1,5}|[\u2160-\u2188]+)\s*$',
  caseSensitive: false,
);

/// 尾部括号里只有数字，例如 `标题 (2)`。
final _trailingBracket = RegExp(r'[\s]*[\(\[【（]\s*\d{1,3}\s*[\)\]】）]\s*$');

/// 从影片标题推断系列名。推断不出可靠前缀时返回 null。
String? inferSeriesName(String? title) {
  final text = title?.trim() ?? '';
  if (text.isEmpty) return null;

  var stripped = text;
  for (final pattern in [_episodeSuffix, _trailingBracket, _trailingNumber]) {
    final next = stripped.replaceFirst(pattern, '').trim();
    // 这一步没匹配上，继续试下一个模式；匹配上了才继续往下剥。
    if (next == stripped) continue;
    // 别把标题削没了：留下太短的结果说明匹配吃掉了正题，就此打住。
    if (next.length < 2) break;
    stripped = next;
  }
  final name = stripped.replaceAll(RegExp(r'[\s\-_·・.,،]+$'), '').trim();
  // 剥完仍是原样、或短得不像系列名，就认为这不是系列影片。
  if (name == text || name.length < 2) return null;
  return name;
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
