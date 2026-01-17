import 'ascyn_stat.dart';

class XpAward {
  final double overallXp;
  final Map<AscynStat, double> statXp;
  final String note;

  const XpAward({
    required this.overallXp,
    required this.statXp,
    required this.note,
  });
}
