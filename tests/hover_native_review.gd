extends SceneTree
const Card=preload("res://scripts/ui/item_hover_card.gd")
const Presentation=preload("res://scripts/ui/unified_item_presentation.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const VisualTheme=preload("res://scripts/visuals/visual_theme.gd")
const Rarity=preload("res://scripts/ui/item_rarity_style.gd")
class Model extends RefCounted:
	var gem:Dictionary
	func item(_uid:String)->Dictionary:return gem
	func item_definition(_uid:String)->Dictionary:return Gems.metadata_for_instance(gem)
	func location(_uid:String)->Dictionary:return {"group_id":"test"}
	func get_group_cast(_group:String)->Dictionary:return Compiler.compile_group("chain",Combat.snapshot({"damage":18.0},[]),["chain_reach"])
var card
var host:Control
func _initialize()->void:call_deferred("run")
func run()->void:
	root.title="Item tooltip native review"
	host=Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.theme=VisualTheme.create_theme()
	root.add_child(host)
	var bg=ColorRect.new()
	bg.color=Color("645541")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)
	var model=Model.new()
	model.gem=Gems.create_instance("review-support","support:chain_reach")
	var source=Button.new()
	source.text="远链辅助"
	source.position=Vector2(780,150)
	source.size=Vector2(160,50)
	host.add_child(source)
	card=Card.new()
	host.add_child(card)
	var view=Presentation.view(model,"review-support")
	source.mouse_entered.connect(func():card.present(view,[],source.get_rect(),Rect2(0,0,1000,320)))
	for i:int in range(3):
		var rarity:String=["normal","magic","rare"][i]
		var sample=Button.new()
		sample.text=["普通","魔法","稀有"][i]
		sample.position=Vector2(740+i*80,300)
		sample.size=Vector2(70,70)
		sample.add_theme_stylebox_override("normal",VisualTheme.panel(Rarity.background(rarity),Rarity.border(rarity),4,2,5))
		host.add_child(sample)
	card.present(view,[],source.get_rect(),Rect2(0,0,1000,320))
var last_scroll:=-1
func _process(_delta:float)->bool:
	if is_instance_valid(card):
		var scroll:ScrollContainer=card.find_child("ItemDetailsScroll",true,false)
		if scroll!=null and last_scroll!=scroll.scroll_vertical:
			last_scroll=scroll.scroll_vertical
			print("Native hover scroll offset: ",last_scroll)
	return false
