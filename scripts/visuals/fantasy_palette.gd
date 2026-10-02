class_name FantasyPalette
extends RefCounted
## Presentation mapping only. GameData damage tags, mechanics, and rarity are untouched.
const SKILLS: Dictionary={"basic":Color("d4c6a1"),"tornado":Color("b6bf89"),"bolt":Color("d2c39d"),"frost":Color("a6c5d0"),"nova":Color("b7a0c5"),"dash":Color("cdb583"),"ward":Color("b4c3a0"),"meteor":Color("d79c67"),"chain":Color("dcc48a")}
static func skill(id: String, fallback: Color=Color("cabb93")) -> Color:
	return SKILLS.get(id,fallback.lerp(Color("bfb79c"),0.35))
static func effect(kind: String, skill_id: String, fallback: Color) -> Color:
	if kind=="cast": return skill(skill_id,fallback)
	if kind in ["meteor","explosion"]: return SKILLS.meteor
	if kind=="return": return Color("b3a0bd")
	if kind=="split": return SKILLS.tornado
	return skill(kind,fallback)
