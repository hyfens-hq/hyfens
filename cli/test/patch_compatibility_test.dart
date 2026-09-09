import 'package:hyfens_tool/src/patch_compatibility.dart';
import 'package:test/test.dart';

void main() {
  test('legacy classifications map to one typed compatibility vocabulary', () {
    expect(
      PatchCompatibilityAnalyzer.fromLegacyClassification('patchable'),
      PatchCompatibilityDecision.patchable,
    );
    expect(
      PatchCompatibilityAnalyzer.fromLegacyClassification(
        'storeReleaseRequired',
      ),
      PatchCompatibilityDecision.newBaseRelease,
    );
    expect(
      PatchCompatibilityAnalyzer.fromLegacyClassification('unsupported'),
      PatchCompatibilityDecision.notYetSupported,
    );
  });

  test('declaration shape policy keeps field and hierarchy changes closed', () {
    expect(
      PatchCompatibilityAnalyzer.declarationChange(
        'method|Card|instanceMethod|build',
      ),
      PatchCompatibilityDecision.patchable,
    );
    expect(
      PatchCompatibilityAnalyzer.declarationChange('field|app|Card|count'),
      PatchCompatibilityDecision.newBaseRelease,
    );
    expect(
      PatchCompatibilityAnalyzer.declarationChange('classHeader|app|Card'),
      PatchCompatibilityDecision.newBaseRelease,
    );
    expect(
      PatchCompatibilityAnalyzer.declarationChange('generic|app|Card'),
      PatchCompatibilityDecision.notYetSupported,
    );
    expect(
      PatchCompatibilityAnalyzer.explainExclusion(
        'Card: field layout changed for a live State object',
      ),
      contains('live receiver state'),
    );
    expect(
      PatchCompatibilityAnalyzer.forAnalysis(
        classification: 'unsupported',
        detail: 'Changed unsupported declarations: classHeader|Class|Card',
      ),
      PatchCompatibilityDecision.newBaseRelease,
    );
  });

  test(
    'actionable explanations distinguish patchable and no-effect results',
    () {
      expect(
        PatchCompatibilityAnalyzer.explainExclusion('1 function(s) selected'),
        contains('can be patched'),
      );
      expect(
        PatchCompatibilityAnalyzer.explainExclusion(
          'No patchable source changes detected.',
        ),
        contains('No patchable source changes'),
      );
    },
  );
}
