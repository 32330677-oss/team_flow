import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xff1a2a6c);
  static const Color accent = Color(0xfffdbb2d);
  static const Color danger = Color(0xffb21f1f);

  static const Color background = Color(0xfff7f8fc);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xff1f2937);
  static const Color textSecondary = Color(0xff6b7280);
  static const Color border = Color(0xffe5e7eb);
}

class AppDataTableCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color accentColor;
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String emptyMessage;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const AppDataTableCard({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.icon,
    this.accentColor = AppColors.primary,
    this.emptyMessage = 'No records found',
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = padding.horizontal;

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),

            const SizedBox(height: 18),

            Container(
              height: 1,
              color: AppColors.border,
            ),

            const SizedBox(height: 18),

            if (rows.isEmpty)
              _buildEmptyState()
            else
              _buildTable(
                context,
                horizontalPadding,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: accentColor,
              size: 21,
            ),
          ),
          const SizedBox(width: 13),
        ],

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),

              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),

        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }

  Widget _buildTable(
    BuildContext context,
    double horizontalPadding,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xffd9dee7),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width -
                  horizontalPadding,
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: const Color(0xffdfe3e8),
              ),
              child: DataTable(
                columnSpacing: 0,
                horizontalMargin: 0,

                headingRowHeight: 44,

                dataRowMinHeight: 48,
                dataRowMaxHeight: 58,

                showCheckboxColumn: false,

                dividerThickness: 1,

                border: TableBorder.all(
                  color: const Color(0xffdfe3e8),
                  width: 1,
                ),

                headingRowColor: WidgetStateProperty.all(
                  accentColor.withOpacity(0.07),
                ),

                headingTextStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),

                dataTextStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),

                columns: columns,
                rows: _styledRows(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<DataRow> _styledRows() {
    return rows.asMap().entries.map((entry) {
      final index = entry.key;
      final row = entry.value;

      return DataRow(
        key: row.key,
        selected: row.selected,
        onSelectChanged: row.onSelectChanged,

        color: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.selected)) {
              return accentColor.withOpacity(0.10);
            }

            if (states.contains(WidgetState.hovered)) {
              return accentColor.withOpacity(0.045);
            }

            if (index.isOdd) {
              return const Color(0xfff7f9fc);
            }

            return Colors.white;
          },
        ),

        cells: row.cells,
      );
    }).toList();
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 34,
        horizontal: 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xfffafbfc),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inbox_outlined,
              color: accentColor.withOpacity(0.75),
              size: 23,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  factory StatusBadge.fromStatus(String status) {
    switch (status) {
      case 'Active':
      case 'Approved':
        return StatusBadge(
          label: status,
          color: Colors.green.shade700,
        );

      case 'Suspended':
      case 'Pending':
        return StatusBadge(
          label: status,
          color: Colors.orange.shade800,
        );

      case 'Rejected':
      case 'Inactive':
        return StatusBadge(
          label: status,
          color: AppColors.danger,
        );

      case 'Completed':
        return StatusBadge(
          label: status,
          color: Colors.grey.shade700,
        );

      default:
        return StatusBadge(
          label: status,
          color: Colors.blueGrey,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.16),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 6),

          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}