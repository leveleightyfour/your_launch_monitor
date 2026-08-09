import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The app's icon vocabulary, backed by Lucide (https://lucide.dev).
///
/// Screens reference these semantic names instead of a concrete icon set, so
/// the set can evolve (or individual glyphs be swapped for custom ones)
/// without touching call sites.
abstract final class AppIcons {
  // Golf domain
  static const IconData golf = LucideIcons.landPlot;
  static const IconData hole = LucideIcons.flagTriangleRight;
  static const IconData flag = LucideIcons.flag;
  static const IconData dispersion = LucideIcons.chartScatter;
  static const IconData ruler = LucideIcons.ruler;
  static const IconData flight3d = LucideIcons.box;
  static const IconData optimizer = LucideIcons.slidersHorizontal;
  static const IconData insights = LucideIcons.chartNoAxesCombined;
  static const IconData trendingUp = LucideIcons.trendingUp;
  static const IconData mountain = LucideIcons.mountain;

  // Navigation & layout
  static const IconData sessions = LucideIcons.zap;
  static const IconData profile = LucideIcons.user;
  static const IconData menu = LucideIcons.menu;
  static const IconData more = LucideIcons.ellipsisVertical;
  static const IconData back = LucideIcons.arrowLeft;
  static const IconData forward = LucideIcons.arrowRight;
  static const IconData up = LucideIcons.arrowUp;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData chevronUp = LucideIcons.chevronUp;
  static const IconData chevronLeft = LucideIcons.chevronLeft;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData tiles = LucideIcons.layoutGrid;
  static const IconData table = LucideIcons.rows3;
  static const IconData columns = LucideIcons.columns3;
  static const IconData rows = LucideIcons.rows2;
  static const IconData fullscreen = LucideIcons.maximize;
  static const IconData fullscreenExit = LucideIcons.minimize;
  static const IconData dragHandle = LucideIcons.gripHorizontal;

  // Actions
  static const IconData add = LucideIcons.plus;
  static const IconData remove = LucideIcons.minus;
  static const IconData close = LucideIcons.x;
  static const IconData check = LucideIcons.check;
  static const IconData checkCircle = LucideIcons.circleCheck;
  static const IconData checklist = LucideIcons.listChecks;
  static const IconData delete = LucideIcons.trash2;
  static const IconData edit = LucideIcons.squarePen;
  static const IconData undo = LucideIcons.undo2;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData replay = LucideIcons.rotateCcw;
  static const IconData rotate = LucideIcons.rotateCwSquare;
  static const IconData flip = LucideIcons.flipHorizontal2;
  static const IconData swap = LucideIcons.arrowLeftRight;
  static const IconData share = LucideIcons.share;
  static const IconData download = LucideIcons.download;
  static const IconData filter = LucideIcons.funnel;
  static const IconData play = LucideIcons.play;
  static const IconData stop = LucideIcons.circleStop;

  // Status & feedback
  static const IconData dot = LucideIcons.circle;
  static const IconData error = LucideIcons.circleAlert;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData info = LucideIcons.info;
  static const IconData help = LucideIcons.circleHelp;
  static const IconData lock = LucideIcons.lock;
  static const IconData bug = LucideIcons.bug;
  static const IconData terminal = LucideIcons.terminal;
  static const IconData sparkle = LucideIcons.sparkles;
  static const IconData palette = LucideIcons.palette;

  // Device & connectivity
  static const IconData bluetooth = LucideIcons.bluetooth;
  static const IconData bluetoothSearching = LucideIcons.bluetoothSearching;
  static const IconData bluetoothOff = LucideIcons.bluetoothOff;
  static const IconData usbOff = LucideIcons.unplug;
  static const IconData battery = LucideIcons.batteryMedium;
  static const IconData batteryFull = LucideIcons.batteryFull;
  static const IconData batteryCharging = LucideIcons.batteryCharging;
  static const IconData batteryAlert = LucideIcons.batteryWarning;
  static const IconData appUpdate = LucideIcons.download;

  // Camera & playback
  static const IconData video = LucideIcons.video;
  static const IconData videoOff = LucideIcons.videoOff;
  static const IconData addCamera = LucideIcons.webcam;
  static const IconData aspectRatio = LucideIcons.ratio;
  static const IconData slowMotion = LucideIcons.gauge;
  static const IconData copies = LucideIcons.copy;

  // Measurement & targeting
  static const IconData gauge = LucideIcons.gauge;
  static const IconData locate = LucideIcons.locate;
  static const IconData locateFixed = LucideIcons.locateFixed;
  static const IconData recenter = LucideIcons.crosshair;
  static const IconData topView = LucideIcons.arrowUpToLine;
  static const IconData layers = LucideIcons.layers;
}
