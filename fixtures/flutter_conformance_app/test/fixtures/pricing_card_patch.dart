// ignore_for_file: unnecessary_this

import 'package:flutter/material.dart';

class PricingCard extends StatelessWidget {
  const PricingCard({super.key, required this.featured, required this.plan});

  final bool featured;
  final String plan;

  @override
  Widget build(BuildContext context) {
    if (this.featured) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('PATCH ${this.plan}', style: TextStyle(fontSize: 24.0)),
          Text('conditional hierarchy'),
          ElevatedButton(onPressed: null, child: Text('Upgrade')),
        ],
      );
    }
    return Text('standard ${this.plan}');
  }
}
