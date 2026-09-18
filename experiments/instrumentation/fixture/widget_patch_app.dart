// ignore_for_file: unnecessary_this

abstract class Widget {
  const Widget();
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget();
}

class BuildContext {}

enum MainAxisSize { min, max }

class TextStyle {
  const TextStyle({double? fontSize});
}

class Text extends Widget {
  const Text(String data, {TextStyle? style});
}

class Column extends Widget {
  const Column({
    MainAxisSize mainAxisSize = MainAxisSize.max,
    required List<Widget> children,
  });
}

class ElevatedButton extends Widget {
  const ElevatedButton({
    required void Function()? onPressed,
    required Widget child,
  });
}

class PricingCard extends StatelessWidget {
  const PricingCard({required this.featured, required this.plan});
  final bool featured;
  final String plan;

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
