import 'package:flutter/material.dart';

/// v6 设计稿的视觉基准值（Figma「page/categoryList-hentai-v6 / page/search-v6 / page/home-v5」实测）。
///
/// 本模块**不是** ColorScheme 的转发层，也不重复主题里已有的东西：只收
/// 「设计稿里明确写了、而 Material 的 ColorScheme/TextTheme 表达不出来」的那几条。
/// 需要的地方仍然优先用 `Theme.of(context).colorScheme`，只有落在下面的取舍上才来这里取。
///
/// 颜色一律按设计稿取值（用户要求「按 v6 设计稿来」），**不跟随用户的主题色**：
/// 设计稿的主色 #C8527C 与主题色 white 的种子 #FB7299 是不同色相，
/// 跟着种子走就还原不出设计稿的那片胭脂粉。换主题色的能力由报告页/播放页等处保留，
/// 侧栏、顶栏、首页这几处是设计稿的「基准面」，不参与换色。
abstract final class AppDesignTokens {
  // ── 颜色 ──────────────────────────────────────────────────────────
  /// 主色（设计稿里所有强调元素：选中导航项、tab 下划线、tag、播放数胶囊）
  static const accent = Color(0xFFC8527C);

  /// 设计稿里**选中态实际用的**那支色：#B3265A，比 [accent] 暗一档。
  /// 导航项选中文字的填充就是它（`navText/里番`），背景是它压到 8% 透明度。
  ///
  /// **只在设计稿的基准面用**（侧栏、顶栏、首页这些「骨架」）。设置页里的控件
  /// （开关、滑块、选中描边、按钮）不要用它，改用 [accentOf] —— 那些地方必须跟随
  /// 用户选的主题色，否则用户在「主题与色彩」页把颜色换成青，控件还是粉的，
  /// 看起来就像「换色没生效」。
  static const accentDeep = Color(0xFFB3265A);

  /// 当前主题的强调色（跟随用户的主题色设置）。
  ///
  /// 与 [accentDeep] 的分工：骨架（侧栏 / 顶栏 / 首页）用固定的设计稿色，
  /// 设置页里可交互的控件用它 —— 那些控件的颜色本身就是用户选出来的结果，
  /// 写死会和用户的选择自相矛盾。
  ///
  /// 取 `colorScheme.primary` 而不是自己算一遍种子色：主题已经由 `appTheme`
  /// 按「预设 / 自定义 / 动态取色（Monet）」三种来源解析好了，这里直接拿最终值。
  static Color accentOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  /// 侧栏 / 卡片底板
  static const surface = Color(0xFFFFFFFF);

  /// 页面底。设计稿的侧栏右边这一大片是 #F4F4F7 —— 比纯白暗一点点，
  /// 白卡、白胶囊压在上面才立得起来。
  static const pageBackground = Color(0xFFF4F4F7);

  /// 卡片、输入框、胶囊的分隔描边
  static const stroke = Color(0xFFE2E2E8);

  /// 侧栏分组之间的细线（`groupDivider`：#ECECF1，左边距 16、宽 144）
  static const divider = Color(0xFFECECF1);

  /// 正文（`head/title` 一类的页头、`title0` 一类的卡片标题）
  static const ink = Color(0xFF1B1B1F);

  /// 次级正文（`author0` 一类的作者行、排序胶囊里未选中的项、导航项未选中态）。
  /// 设计稿这几处都是同一个 #5F5F6B，不再按语义再分一层。
  static const inkSubtle = Color(0xFF5F5F6B);

  /// 说明文字（计数、"共 128 部"、"10-24" 这类日期）
  static const inkMuted = Color(0xFF8A8A96);

  /// 输入框的底色与占位文字（`head/searchBg` / `head/searchHint`）。
  ///
  /// 首页顶栏那个搜索框走的是 g1455 的玻璃胶囊，自带材质，用不上这两支；
  /// 它们是给非玻璃的输入框（分类页头的搜索框、筛选框）留的。
  static const fieldFill = Color(0xFFEDEDF2);

  /// 输入框占位文字。
  ///
  /// 原来这里另有一支 `fieldHint=#9595A0`，但它和 [inkMuted](#8A8A96) 只差 11 级、
  /// 肉眼几乎不可分，等于让「说明文字」这一层有两个几乎一样的灰（违反「最多三种
  /// 文字色」的层级纪律）。现统一并入 [inkMuted]：占位文字比说明文字还淡一点没
  /// 有信息价值，保留两个近似灰只会让界面显得不整齐。
  static const fieldHint = inkMuted;

  /// 封面上那两枚胶囊的底（播放数 / 时长）：#1B1B1F
  static const chipScrim = Color(0xFF1B1B1F);

  /// 选中导航项的背景：设计稿是 [accentDeep] 压到 8% —— 极淡的一层粉，
  /// 靠它区分选中，而不是靠整块实色把这一行框出来。
  static const navSelectedWash = Color(0x14B3265A);

  /// 开关**关闭态**的轨道色。
  ///
  /// 设计稿实测约 #B7B7B9（`主题与色彩页 · v6` 里那几行关着的开关）：一支中灰，
  /// 压在白卡上能看出「这儿有个关掉的开关」。比它淡一档（如 #D4D4D5）就几乎消失，
  /// 比它深又会跟标题抢注意力。
  static const switchTrackOff = Color(0xFFB7B7B9);

  /// 侧栏底部账号卡的底。#F6F6F9，比侧栏的白暗一点点、比 [fieldFill] 浅得多。
  ///
  /// 设计稿这张卡**没有描边**：它靠「浅灰压在白上」立起来，加一条 1px 反而会
  /// 和多出来的分割线抢注意力（`home_v5_base.png` 实测卡内 144×56 全是这一色，
  /// 卡外紧邻像素就是纯白 255）。
  static const accountCardFill = Color(0xFFF6F6F9);

  // ── 尺度 ──────────────────────────────────────────────────────────
  /// 桌面侧栏宽度。设计稿 176，改造前是 168 —— 那 8px 是导航项文字与
  /// 「观 看 历 史」这类四字项不换行、且图标到文字留白 24 的下限。
  static const sidebarWidth = 176.0;

  /// 侧栏导航项的图标边长（设计稿 18，改造前 22）
  static const sidebarIconSize = 18.0;

  /// 侧栏导航项的文字字号。设计稿 `sidebarMaster` 的 `navText/*` 是 **13**，
  /// 之前放 12 是照着更早一版设计稿的 11 顺延过来的。
  static const sidebarLabelSize = 13.0;

  /// 侧栏导航项的行距（项中心到项中心，设计稿 52）
  static const sidebarItemPitch = 52.0;

  /// 侧栏导航项**选中底**的高度（设计稿 34，落在 52 的行距里，上下各留 9）。
  ///
  /// 这一条必须和行距分开：改造时一开始把「项高」直接当成 44（= 52 - 上下 8），
  /// 选中底色于是比设计稿高了 10 —— 看着就是「一选中尺寸就变了」。
  static const sidebarItemHeight = 34.0;

  /// 侧栏导航项的上下留白。由行距和项高推出来（(52 - 34) / 2 = 9），
  /// 写成一个式子是为了让这两条永远自洽：改哪个都不会把行距带偏。
  static const sidebarItemInsetY = (sidebarItemPitch - sidebarItemHeight) / 2;

  /// 顶栏高度。
  ///
  /// 设计稿 `page/home-v5` 的顶栏分两层：上方 y0~34 是窗口按钮带（最小化/最大化/关闭
  /// 各 34×34），下方 y34~112 才是内容带（搜索框 y56 高 34、页签文字 y70 高 15、
  /// 下划线 y90 高 3）。banner 从 y112 开始，所以顶栏总高就是 112。
  ///
  /// 之前写 100 是照「banner 从 112 起、顶栏取整到 100」估的，结果内容带只有 66 高，
  /// 搜索框被摆到 y50、页签下划线到 y79 —— 比设计稿整体高了 12，顶栏也少了一条
  /// 底部留白。改 112 之后内容带 34~112 高 78，搜索框居中正好落在 56~90。
  static const topBarHeight = 112.0;

  /// 顶栏顶部窗口按钮带的高度（设计稿 titleBarBtn 34 高）。
  static const topBarChromeHeight = 34.0;

  /// 主窗口自绘标题栏的高度（右侧三个窗口按钮就落在这条带子里）。
  ///
  /// 与 `app_title_bar.dart` 的 `appTitleBarHeight` 同值：页面的顶栏要往上让出这一段，
  /// 否则「最大化 / 关闭」两个按钮会压住页面右上角的操作按钮（缓存页的「清理」
  /// 就被压住过）。`AppTopBar` 用它算顶部留白。
  static const windowControlsHeight = 28.0;

  /// 顶栏页签那一排离它所在 Stack 底边的下留白。
  ///
  /// 设计稿：页签下划线落在 y90~92，内容带底是 y112 —— 中间正好还留 20。
  /// 也就是说页签是**贴底**摆的，不是和搜索框一起垂直居中。
  ///
  /// 这里取 12.5 而不是 20：顶栏那一层 Stack 的底边并不落在内容带底（y112），
  /// 实测比它高约 7.5（Stack 高度 63、在 78 高的内容带里居中）——
  /// 20 - 7.5 = 12.5 才能把下划线真正落到设计稿的 y90~92。改了顶栏结构的话
  /// 这条要跟着重新校准。
  static const topBarTabBaselineGap = 12.5;

  /// 顶栏右侧搜索框的静止宽度（设计稿 316）
  static const searchBoxWidth = 316.0;

  /// 搜索框高度（设计稿 34）
  static const searchBoxHeight = 34.0;

  /// 分区标题字号（设计稿 22）
  static const sectionTitleSize = 22.0;
}
