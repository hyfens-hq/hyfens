void main() {}

/// Returns the compiled destination ID for an ordinary app-owned cohort.
///
/// The router owns the route table and maps `0` and `1` to already-compiled
/// destinations. A negative cohort is deliberately outside the decision
/// function's accepted domain.
int chooseDestination(int cohort) {
  if (cohort < 0) return -1;
  return cohort.isEven ? 0 : 1;
}
