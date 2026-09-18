// ignore_for_file: unnecessary_this, unused_element

import 'dart:convert';
import 'dart:math' as e0_runtime;

final class _E0ReceiverAdapter0 {}

class PricingService {
  const PricingService(this.taxRate, this._fee);

  final double taxRate;
  final double _fee;

  double get adjustment => 3.0;

  double calculate(double amount, double quantity) {
    final $e0Patch = 0.0;
    final $e0Result = 0.0;
    return amount +
        quantity +
        this.taxRate +
        this._fee +
        this.adjustment +
        $e0Patch +
        $e0Result;
  }
}

class RegionalPricingService extends PricingService {
  const RegionalPricingService(super.taxRate, super._fee);
}

class OverridePricingService extends PricingService {
  const OverridePricingService(super.taxRate, super._fee);

  @override
  double calculate(double amount, double quantity) => 99.0;
}

void main(List<String> arguments) {
  const direct = PricingService(1.5, 2.0);
  const PricingService virtual = RegionalPricingService(1.5, 2.0);
  const PricingService overridden = OverridePricingService(1.5, 2.0);
  final tearOff = direct.calculate;
  final amount = e0_runtime.max(10.0, 2.0);
  print(
    jsonEncode(<String, double>{
      'direct': direct.calculate(amount, 2.0),
      'virtual': virtual.calculate(amount, 2.0),
      'tearOff': tearOff(amount, 2.0),
      'override': overridden.calculate(amount, 2.0),
    }),
  );
}
