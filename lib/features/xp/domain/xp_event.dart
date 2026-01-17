import 'package:cloud_firestore/cloud_firestore.dart';
import 'ascyn_stat.dart';

enum XpSourceType {
  habitCheck,
  habitCounter,
  habitTimer,
  taskComplete,
  manualAdjustment,
  undoReversal,
}

enum XpEventStatus {
  active,
  reversed,
  softDeleted,
}

class XpEvent {
  final String id;
  final String uid;
  final String characterId;

  final XpSourceType sourceType;
  final String sourceId; // habitId or taskId
  final DateTime occurredAt;

  final double overallXp; // can be negative for undo reversal
  final Map<AscynStat, double> statXp;

  final XpEventStatus status;

  // Undo / integrity tracking
  final String? reversesEventId; // eventId this reverses (if undo)
  final String? note;

  XpEvent({
    required this.id,
    required this.uid,
    required this.characterId,
    required this.sourceType,
    required this.sourceId,
    required this.occurredAt,
    required this.overallXp,
    required this.statXp,
    required this.status,
    this.reversesEventId,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'characterId': characterId,
      'sourceType': sourceType.name,
      'sourceId': sourceId,
      'occurredAt': Timestamp.fromDate(occurredAt),
      'overallXp': overallXp,
      'statXp': statXp.map((k, v) => MapEntry(k.name, v)),
      'status': status.name,
      'reversesEventId': reversesEventId,
      'note': note,
    };
  }

  static XpEvent fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final rawStat = (data['statXp'] as Map<String, dynamic>? ?? {});
    final statXp = rawStat.map(
      (k, v) => MapEntry(AscynStat.values.byName(k), (v as num).toDouble()),
    );

    return XpEvent(
      id: doc.id,
      uid: data['uid'] as String,
      characterId: data['characterId'] as String,
      sourceType: XpSourceType.values.byName(data['sourceType'] as String),
      sourceId: data['sourceId'] as String,
      occurredAt: (data['occurredAt'] as Timestamp).toDate(),
      overallXp: (data['overallXp'] as num).toDouble(),
      statXp: statXp,
      status: XpEventStatus.values.byName(data['status'] as String),
      reversesEventId: data['reversesEventId'] as String?,
      note: data['note'] as String?,
    );
  }
}
