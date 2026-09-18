Map<String, dynamic> transform(Map<String, dynamic> input) {
  return <String, dynamic>{'source': input['name'], 'patched': true};
}
