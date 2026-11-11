/// v1.3.0：识别官网返回的「占位」流量字段。
///
/// 官网为时长套餐，V2Board 兼容接口固定返回 transfer_enable = 1 TB（1099511627776）、u = d = 0、
/// getStat = [0,0,0]，这些都不是真实数据。直接展示会出现「剩余 1024 GB / 已用 0 GB」的误导信息。
class PlanQuota {
  /// 服务器占位的 1 TB
  static const int placeholderTransfer = 1099511627776;

  final int used;
  final int total;
  final int expiredAt;
  final String? planName;

  /// 时长套餐（不限流量）：服务器没有给出可信的流量配额
  final bool timeBased;

  const PlanQuota._({
    required this.used,
    required this.total,
    required this.expiredAt,
    required this.planName,
    required this.timeBased,
  });

  factory PlanQuota.fromSubscribe(Map<String, dynamic> sub) {
    int n(String k) => (sub[k] as num?)?.toInt() ?? 0;
    final used = n('u') + n('d');
    final total = n('transfer_enable');
    final plan = sub['plan'];
    final name = plan is Map && plan['name'] != null
        ? plan['name'].toString().trim()
        : null;
    // 没有配额，或「0 已用 + ≥1TB 占位配额」= 服务器不计流量
    final timeBased = total <= 0 || (used == 0 && total >= placeholderTransfer);
    return PlanQuota._(
      used: used,
      total: total,
      expiredAt: n('expired_at'),
      planName: (name == null || name.isEmpty) ? null : name,
      timeBased: timeBased,
    );
  }

  bool get hasExpiry => expiredAt > 0;

  /// 剩余天数（未设置到期时间为 null）；已过期为负数
  int? daysLeft(DateTime now) {
    if (!hasExpiry) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(expiredAt * 1000).difference(now);
    if (d.isNegative) return -1;
    return d.inDays;
  }

  bool isExpired(DateTime now) =>
      hasExpiry &&
      DateTime.fromMillisecondsSinceEpoch(expiredAt * 1000).isBefore(now);
}
