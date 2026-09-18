import 'package:flutter/material.dart';

import '../../domain/waypoint_offer.dart';
import '../waypoint_theme.dart';

final class WaypointOfferBanner extends StatelessWidget {
  const WaypointOfferBanner({
    super.key,
    required this.offer,
    required this.onAction,
    required this.onDismiss,
  });

  final WaypointOffer offer;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey<String>('waypoint-offer-banner'),
    padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
    decoration: BoxDecoration(
      color: waypointColor(offer.accentColor),
      borderRadius: const BorderRadius.all(Radius.circular(22)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.auto_awesome_rounded, color: WaypointColors.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(offer.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                offer.message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              TextButton(
                key: const ValueKey<String>('waypoint-offer-action'),
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: WaypointColors.ink,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                ),
                child: Text(offer.actionLabel),
              ),
            ],
          ),
        ),
        if (offer.isDismissible)
          IconButton(
            key: const ValueKey<String>('waypoint-offer-dismiss'),
            onPressed: onDismiss,
            tooltip: 'Dismiss offer',
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    ),
  );
}
