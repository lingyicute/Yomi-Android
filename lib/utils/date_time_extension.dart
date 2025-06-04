import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:yomi/l10n/l10n.dart';

/// Provides extra functionality for formatting the time.
extension DateTimeExtension on DateTime {
  bool operator <(DateTime other) {
    return millisecondsSinceEpoch < other.millisecondsSinceEpoch;
  }

  bool operator >(DateTime other) {
    return millisecondsSinceEpoch > other.millisecondsSinceEpoch;
  }

  bool operator >=(DateTime other) {
    return millisecondsSinceEpoch >= other.millisecondsSinceEpoch;
  }

  bool operator <=(DateTime other) {
    return millisecondsSinceEpoch <= other.millisecondsSinceEpoch;
  }

  /// Checks if two DateTimes are close enough to belong to the same
  /// environment.
  bool sameEnvironment(DateTime prevTime) =>
      difference(prevTime) < const Duration(hours: 1);

  /// Returns a simple time String.
  String localizedTimeOfDay(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final is24HourFormat = L10n.of(context).alwaysUse24HourFormat == 'true';
    
    if (is24HourFormat) {
      return DateFormat('HH:mm', locale.languageCode).format(this);
    } else {
      // 检查是否是中文环境
      if (locale.languageCode == 'zh') {
        final hour = this.hour;
        final minute = this.minute.toString().padLeft(2, '0');
        String period;
        
        // 根据小时确定时间段
        if (hour >= 0 && hour < 6) {
          period = '凌晨';
        } else if (hour >= 6 && hour < 9) {
          period = '早上';
        } else if (hour >= 9 && hour < 12) {
          period = '上午';
        } else if (hour == 12) {
          period = '中午';
        } else if (hour > 12 && hour < 18) {
          period = '下午';
        } else if (hour >= 18 && hour < 20) {
          period = '傍晚';
        } else {
          period = '晚上';
        }
        
        // 转换为12小时制
        final hour12 = hour % 12 == 0 ? 12 : hour % 12;
        
        return '$period $hour12:$minute';
      } else {
        // 其他语言使用标准格式
        return DateFormat('h:mm a', locale.languageCode).format(this);
      }
    }
  }

  /// Returns [localizedTimeOfDay()] if the ChatTime is today, the name of the week
  /// day if the ChatTime is this week and a date string else.
  String localizedTimeShort(BuildContext context) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context);
    final isZhLocale = locale.languageCode == 'zh';

    final sameYear = now.year == year;

    final sameDay = sameYear && now.month == month && now.day == day;

    final sameWeek = sameYear &&
        !sameDay &&
        now.millisecondsSinceEpoch - millisecondsSinceEpoch <
            1000 * 60 * 60 * 24 * 7;

    if (sameDay) {
      return localizedTimeOfDay(context);
    } else if (sameWeek) {
      if (isZhLocale) {
        // 中文环境下使用 "星期x" 格式
        final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
        final weekdayIndex = weekday - 1; // DateTime的weekday从1开始，周一是1
        return '星期${weekdays[weekdayIndex]}';
      } else {
        return DateFormat.E(locale.languageCode).format(this);
      }
    } else if (sameYear) {
      if (isZhLocale) {
        // 中文环境下使用 "M月d日" 格式
        return '${month}月${day}日';
      } else {
        return DateFormat.MMMd(locale.languageCode).format(this);
      }
    }
    if (isZhLocale) {
      // 中文环境下使用 "yyyy年M月d日" 格式
      return '${year}年${month}月${day}日';
    } else {
      return DateFormat.yMMMd(locale.languageCode).format(this);
    }
  }

  /// If the DateTime is today, this returns [localizedTimeOfDay()], if not it also
  /// shows the date.
  String localizedTime(BuildContext context) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context);
    final isZhLocale = locale.languageCode == 'zh';

    final sameYear = now.year == year;
    final sameDay = sameYear && now.month == month && now.day == day;

    if (sameDay) return localizedTimeOfDay(context);
    
    if (isZhLocale) {
      // 中文环境下日期和时间的组合方式
      return '${localizedTimeShort(context)} ${localizedTimeOfDay(context)}';
    } else {
      return L10n.of(context).dateAndTimeOfDay(
        localizedTimeShort(context),
        localizedTimeOfDay(context),
      );
    }
  }
}
