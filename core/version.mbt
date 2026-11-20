// The version the code advertises. It must equal `moon.mod`'s `version`; the
// consistency guard fails when the two drift apart (D75).
//
// A constant rather than a runtime read: MoonBit has no build-time version
// injection, so the manifest is not visible to the compiler.

///|
pub let version : String = "0.3.1"
