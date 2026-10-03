/// The newest rule-semantics version this package implements (`rules=` on the
/// `form` marker, FORM_INTAKE.md §4.7).
///
/// A form that needs behaviour a client does not know raises `rules=`; the
/// client then refuses to fill it instead of silently judging it by older rules
/// (§4.8). Raise this constant only together with the semantics it names.
const int kFormRulesVersion = 1;

/// Whether this engine can judge a form that declares `rules=[declared]`.
///
/// A declaration below 1 is malformed, and one above [kFormRulesVersion] needs a
/// newer client; both answer `false`.
bool supportsFormRules(int declared) =>
    declared >= 1 && declared <= kFormRulesVersion;
