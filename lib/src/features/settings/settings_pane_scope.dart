import 'package:flutter/material.dart';

/// 设置页在宽屏下的分栏宽度阈值。低于它落回单栏列表（每种设置页各自 push 打开）。
const double settingsPaneMinWidth = 760;

/// 当前这个设置子页是不是**嵌在宽屏右栏里**渲染的。
///
/// 宽屏下左栏已经列出了所有分类并把当前页高亮，右栏再顶一个 AppBar 标题就是重复。
/// 窄屏时这些页面是被独立 push 打开的，AppBar 还要负责标题和返回按钮，不能去掉。
///
/// 用法：`appBar: embeddedInSettingsPanes(context) ? null : AppBar(...)`。
bool embeddedInSettingsPanes(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= settingsPaneMinWidth;
