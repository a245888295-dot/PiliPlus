import 'dart:math' as math;

// PiliPlus 用的是自己 fork 的 material（见 pubspec 的 material_ui），
// 主题、Scaffold、FAB 都来自这个包。若改用 flutter/material，
// Theme.of 取不到 App 的配色，按钮会变成默认紫。
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// 常驻可拖动的返回键。
///
/// 用途：屏幕左侧边缘触摸失灵时，提供一个随时可点的「返回上一级」入口。
///
/// 外观沿用 PiliPlus 视频页那个浮动 FAB（M3 圆角方形、主题色、带阴影、Icons.reply），
/// 区别是它现在可以按住拖动：
///   · 按住拖动 → 跟手移动，松手吸附到最近的一条竖边
///   · 位置会被记住（归一化存盘，换机型/换方向都还落在合理位置）
///   · 不进全屏播放（横屏）时自动隐藏，退出来又回到原位
///   · 不做滚动隐藏：这是「长驻」的意思——翻内容时它不会躲
///
/// 只改外观的话看下面几个常量就够了。
const double _kSize = 56;
const double _kMargin = 16;
const Duration _kSnapDuration = Duration(milliseconds: 180);
const Duration _kFadeDuration = Duration(milliseconds: 120);

/// 往下/往上滑出时用的位移倍数：比一个按钮高一点，把阴影也带出去。
const double _kSlideFactor = 1.35;

/// 跟踪根 Navigator 的栈深度，决定返回键要不要出现。
///
/// 注册成 GetMaterialApp 的 navigatorObserver 之后，每次 push/pop 都会同步一次
/// `canPop`，按钮据此滑入/滑出。放在首页根路由时 canPop 为 false，按钮隐藏，
/// 不会挡住内容。
class BackStackObserver extends NavigatorObserver {
  BackStackObserver._();

  static final BackStackObserver instance = BackStackObserver._();

  final ValueNotifier<bool> canPop = ValueNotifier<bool>(false);

  void _sync() {
    final state = navigator;
    if (state == null) return;
    canPop.value = state.canPop();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _sync();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _sync();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _sync();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _sync();
}

/// 把整个 App 包一层，上面挂一个可拖动的返回键。
///
/// 放在 GetMaterialApp 的 builder 里，位于 Navigator 之上，所以每个页面都有，
/// 弹层之上也在，且不需要改任何页面。
class BackButtonOverlay extends StatefulWidget {
  const BackButtonOverlay({
    super.key,
    required this.child,
    required this.onBack,
    this.loadPosition,
    this.savePosition,
  });

  final Widget child;

  /// 通常传 main.dart 里已有的 `_onBack`：
  /// 它会先关掉 SmartDialog，再处理 GetPageRoute 的 popDisposition，最后 navigator.pop()。
  final VoidCallback onBack;

  /// 读取上次记住的位置，归一化到 0..1（相对于可用区域的宽/高）。
  /// 传 null 就只在本次运行内记住位置。
  final Offset? Function()? loadPosition;

  /// 拖动结束后把新位置交出去存盘。
  final void Function(Offset frac)? savePosition;

  @override
  State<BackButtonOverlay> createState() => _BackButtonOverlayState();
}

class _BackButtonOverlayState extends State<BackButtonOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  /// 归一化位置；null 表示还没摆过，用默认的右下角。
  Offset? _frac;

  bool _dragging = false;
  bool _landscape = false;

  @override
  void initState() {
    super.initState();
    _frac = widget.loadPosition?.call();
    // value: 1 表示停在「藏起来」那一端，冷启动时不会先闪一下。
    _fade = AnimationController(
      vsync: this,
      duration: _kFadeDuration,
      value: 1,
    );
    BackStackObserver.instance.canPop.addListener(_sync);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final land = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (land != _landscape) {
      _landscape = land;
      _sync();
    }
  }

  @override
  void dispose() {
    BackStackObserver.instance.canPop.removeListener(_sync);
    _fade.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final show = BackStackObserver.instance.canPop.value && !_landscape;
    if (show) {
      _fade.reverse();
    } else {
      _fade.forward();
    }
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    widget.onBack();
  }

  void _onDragStart(DragStartDetails _) {
    setState(() => _dragging = true);
    HapticFeedback.selectionClick();
  }

  void _onDragUpdate(DragUpdateDetails d, Size max) {
    final cur = _resolve(max);
    final next = Offset(
      (cur.dx + d.delta.dx).clamp(0.0, max.width),
      (cur.dy + d.delta.dy).clamp(0.0, max.height),
    );
    setState(() => _frac = Offset(
          max.width <= 0 ? 0 : next.dx / max.width,
          max.height <= 0 ? 0 : next.dy / max.height,
        ));
  }

  void _onDragEnd(DragEndDetails _, Size max) {
    final cur = _resolve(max);
    // 吸附到更近的那条竖边，别停在屏幕中间挡内容。
    final toRight = cur.dx + _kSize / 2 >= max.width / 2 + _kSize / 2;
    final x = toRight ? max.width : 0.0;
    final y = cur.dy;
    final frac = Offset(
      max.width <= 0 ? 0 : x / max.width,
      max.height <= 0 ? 0 : y / max.height,
    );
    setState(() {
      _dragging = false;
      _frac = frac;
    });
    widget.savePosition?.call(frac);
    HapticFeedback.mediumImpact();
  }

  /// 归一化位置 → 像素位置。没摆过就落在右下角（max 本身已经是「右下角」）。
  Offset _resolve(Size max) {
    final f = _frac;
    if (f == null) return Offset(max.width, max.height);
    return Offset(
      (f.dx * max.width).clamp(0.0, max.width),
      (f.dy * max.height).clamp(0.0, max.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    // 键盘弹出时把可用高度收上去，按钮不会沉到键盘底下。
    final usableH = math.max(0.0, mq.size.height - mq.viewInsets.bottom);
    final viewW = mq.size.width - pad.left - pad.right;

    // 按钮左上角能取到的最大坐标。
    final max = Size(
      math.max(0.0, viewW - _kSize - _kMargin * 2),
      math.max(0.0, usableH - _kSize - pad.bottom - _kMargin * 2),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // 横屏 = 全屏播放，这时不显示，免得压在播放控件上。
        if (!_landscape) _buildDraggable(max, pad),
      ],
    );
  }

  Widget _buildDraggable(Size max, EdgeInsets pad) {
    final pos = _resolve(max);
    final radius = BorderRadius.circular(16);

    // 注意层级：AnimatedPositioned 必须是 Stack 的直接子节点，
    // 淡入淡出那层 Transform 要放在它里面，否则 Positioned 的父节点不是 Stack 会报错。
    return AnimatedPositioned(
      // 拖动过程中要跟手（时长 0），松手吸附时才做动画。
      duration: _dragging ? Duration.zero : _kSnapDuration,
      curve: Curves.easeOutCubic,
      left: pad.left + _kMargin + pos.dx,
      top: pad.top + _kMargin + pos.dy,
      child: AnimatedBuilder(
        animation: _fade,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_fade.value);
          return IgnorePointer(
            ignoring: _fade.value > 0.01,
            child: Opacity(
              opacity: 1 - t,
              child: Transform.translate(
                offset: Offset(0, t * _kSize * _kSlideFactor),
                child: child,
              ),
            ),
          );
        },
        child: GestureDetector(
          onTap: _handleTap,
          onPanStart: _onDragStart,
          onPanUpdate: (d) => _onDragUpdate(d, max),
          onPanEnd: (d) => _onDragEnd(d, max),
          child: Semantics(
            button: true,
            label: '返回上一级',
            child: AnimatedScale(
              scale: _dragging ? 1.06 : 1,
              duration: const Duration(milliseconds: 120),
              child: Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                elevation: _dragging ? 10 : 6,
                borderRadius: radius,
                child: SizedBox(
                  width: _kSize,
                  height: _kSize,
                  child: Icon(
                    Icons.reply,
                    size: 26,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
