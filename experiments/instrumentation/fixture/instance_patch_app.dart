class PricingService {
  late final double taxRate;
  late final double _fee;
  double get adjustment => 0;

  double calculate(double amount, double quantity) {
    // ignore: unnecessary_this
    return amount * quantity + this.taxRate + this._fee + this.adjustment;
  }
}
