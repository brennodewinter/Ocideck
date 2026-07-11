import '../models/finding_spec.dart';
import '../models/slide.dart';

/// Builds a **finding slide group** (PENTEST_MIAUW §3.1/§4.1): the structured
/// `finding` header carrying [spec], plus optional placeholder **detail** and
/// **evidence** slides, all sharing one [findingId]. This is what the finding
/// wizard emits in one shot; the slides round-trip as a unit through their
/// `ocideck_finding_id` / `ocideck_finding_role` markers, and survive
/// `Slide.duplicate` (which keeps the id/role) when inserted.
///
/// The header is always a `finding`-typed slide (the group's structured card);
/// a detail slide is a `bullets` scaffold and an evidence slide an `image`
/// scaffold, matching the round-trip fixtures. All three carry [spec]'s heading
/// as their title so they read as one finding in the slide list.
List<Slide> buildFindingGroup({
  required FindingSpec spec,
  required String findingId,
  bool addDetail = false,
  bool addEvidence = true,
}) {
  Slide member(SlideType type, FindingRole role) => Slide.create(
    type,
  ).copyWith(title: spec.heading, findingId: findingId, findingRole: role);
  return [
    member(
      SlideType.finding,
      FindingRole.header,
    ).copyWith(customMarkdown: spec.toMarkdown()),
    if (addDetail) member(SlideType.bullets, FindingRole.detail),
    if (addEvidence) member(SlideType.image, FindingRole.evidence),
  ];
}
