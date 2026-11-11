# bento-ui-motion-grid skill 学习笔记

来源：https://bento-ui-motion-skill.vercel.app/ （免费 skill，模板 zip 可下载）。
性质：**不是 UI 组件库，而是「用 HTML + Playwright + ffmpeg 生成 120fps 静音 bento 网格动效视频」的完整制作技能**。

## 它是什么
一条 24 秒、1440x1080(4:3)、120fps 的静音视频：一个锁死镜头对着整屏 bento 网格（20-30 张精致 UI 卡：音乐播放器、时钟、地图路线、聊天、看板、2FA、取色器、计时器、圆环、通知、定价开关、部署按钮…），每张卡各自独立持续动效，弹簧入场、里程表数字滚动、旋钮滑动、圆环扫过、对勾自绘、FLIP 堆叠、明暗交叉淡化。用于展示设计品味/组件库/App 概念。

## 视觉规格（模板默认）
- 舞台 1024x768 CSS px，deviceScale 2.8125 截图(2880x2160)，Lanczos 缩到 1440x1080 → 字体锐利
- 调色：bg #F7F7F5 / tray #EEEEEA / 白卡双层柔和阴影 / 深卡 #0F0F12 / ink #141416 / muted #8B8B87 / 唯一强调色 #2F5BFF + tint #EEF2FF
- 字体：Inter + tnum/cv11/ss01；标签 9-11px，数字 16-36px，字距略负
- 网格：5 列(x 22,232,392,642,802；宽 200,150,240,150,200)，10px 间距，tray 圆角 22，内卡圆角 14；每列高度总和都=720px
- 时间线：0~1.6s 错峰弹簧入场(scale .86→1 + opacity + 内容上浮 6px，按 x/y 延迟)；之后每卡跑自己周期(2.2~7.5s，相位错开 1.2~4.5s)+环境动效(eq 柱、迷你折线滚动、车在地图跑、计时、打字点、脉冲环)，保证永远有东西在动。

## 架构
- index.html：CSS token + 缓动/计时 helper + roll() 里程表数字 + 24 个 W.<name>(t) widget 函数 + 布局表 L=[[id,x,y,w,h,'w'|'d'|'']...] + draw(t) 按时间 t 重渲染整页
- scripts/render.py：并行 Playwright worker，第 i 帧→draw(i/fps)→截图 2.8125x→1440x1080 PNG
- scripts/snap.py：指定秒数出静帧(快速评审)
- scripts/smoothness.py：逐卡帧差尖峰检测器(找出跳变/循环接缝)
- scripts/encode.sh：帧→mp4(120fps master + 每2帧的60fps发布版)，ffprobe 校验

## 动效语言（最有迁移价值的部分）
```js
spring(p) // 从静止起的阻尼弹簧 zeta.55 ~12% 过冲，p=1 恰为1；用于一切位移：旋钮/滑杆/环/数字/卡片
soft(p)   // 临界阻尼无过冲零初速；用于交叉淡化、颜色/主题翻转、堆叠推挤、重置
expo(p)   // ease-out-expo；只用于透明度出现，start fast 绝不用于大面积颜色(会像闪光)
io(p)     // quintic in-out 长距离移动(地图上的车)
st(t,P,o)  // -> {k,l,pre} 周期序号 + 周期内秒数
st2/tw(t,P,o,vals,dur,ease) // 在一组值之间补间，首个变化发生在 o
roll(from,to,l,dur,stagger) // 逐位里程表列(等宽数字)，从左到右错峰；非数字交叉淡化
```
- spring 公式：1-e^(-6.5p)(cos(9.86p)+(6.5/9.86)sin(9.86p))，归一化 sprRaw(p)/sprRaw(1)
- 滚动数字：每位一个 .rc 竖向列，translateY(-y*1.2em) 在 0-9 之间滚

## 关键法则（Recipe + Gotchas）
1. 每张卡是纯 t 的函数：不用 Math.random / Date / CSS transition/animation
2. 每次状态变化都必须连续：检查周期接缝(末尾状态 = 下一周期开头)和预启动状态
3. 先淡出再淡入，不要硬切；二元切换(心形变实心/文字互换/进度条消失)把两态都叠着做 opacity 交叉淡化
4. 有速度的弹簧在 120fps 第 1 帧会顿一下，要用从静止起的弹簧
5. expo 用在大色块(专辑封面/主题翻转)会像闪光，用 soft
6. 会绕回的值((t*k)%x)会跳，改单调值
7. 两 widget 共享一个值(圆环和百分比标签)必须用同一周期索引(st 与 st2 差一)
8. 校验流程：snap.py 看静帧 → render.py 渲染 → smoothness.py 查尖峰 → 修 → encode.sh

## 与之前学到的 affectUI 的关系
- affectUI = 具体组件形态（Tool Call Card/Agent Tree 的可视结构）
- bento skill = 动效语言 + 视频流水线（怎么让 UI 卡一直动、且丝滑到 120fps）
两者互补：一个给长什么样，一个给怎么动 + 怎么录成视频。

## 迁到本项目（Han1meWinPlus, Flutter）可用之处
- 动效曲线可直接移植：spring/soft/expo/io 都是标准数学函数，Flutter 用 Curve 或 Simulation(SpringSimulation 天然支持 from-rest 阻尼弹簧)
- 每卡各自持续循环、相位错开的思路适合做：首页/空状态/加载态的轻量环境动效(封面 hover 脉冲、音乐波形 eq 柱、数字滚动)
- 里程表 roll() 适合播放量/评分/倒计时数字(Flutter 用 Tween + 裁剪列)
- 交叉淡化的二元切换原则同样适用：心形收藏填充、标签互换、进度完成——Flutter 用 AnimatedSwitcher/显式双层 opacity
- 注意：本项目不需要生成视频(那是 web+Playwright+ffmpeg 的产物)，只取动效手法；且要遵守可访问性(Flutter 用 MediaQuery.disableAnimations 对应 prefers-reduced-motion)
