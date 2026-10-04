extends SceneTree
const Card=preload("res://scripts/ui/item_hover_card.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var checks:Array[bool]=[]
	var host:=Control.new()
	host.size=Vector2(1000,700)
	host.scale=Vector2(1.2,1.2)
	root.add_child(host)
	var card=Card.new()
	host.add_child(card)
	var lines:Array[String]=[]
	for i:int in range(60): lines.append("测试词缀 %d：增加伤害与其他效果"%i)
	var view={"uid":"test","name":"长物品","rarity":"rare","base_lines":lines}
	card.present(view,[],Rect2(600,200,40,40),Rect2(0,0,1000,700))
	await process_frame
	await process_frame
	var scroll:ScrollContainer=card.find_child("ItemDetailsScroll",true,false)
	checks.append(scroll.get_v_scroll_bar().max_value>scroll.size.y)
	var source:Vector2=host.get_global_transform_with_canvas()*Vector2(610,210)
	checks.append(card.scroll_at(source,1,3))
	checks.append(scroll.scroll_vertical>0)
	var before:int=scroll.scroll_vertical
	var card_point:Vector2=scroll.get_global_transform_with_canvas()*Vector2(20,20)
	checks.append(card.scroll_at(card_point,1,3))
	checks.append(scroll.scroll_vertical>before)
	checks.append(not card.scroll_at(Vector2(-20,-20),1))
	checks.append(card.contains_viewport_point(card_point))
	var title:Control=card.find_child("ItemName",true,false)
	checks.append(not scroll.is_ancestor_of(title))
	card.set_drag_active(true)
	checks.append(not card.scroll_at(source,1))
	checks.append(not card.visible)
	host.queue_free()
	await process_frame
	print("Hover scroll v37: %d checks, %d failures"%[checks.size(),checks.count(false)])
	quit(1 if checks.count(false)>0 else 0)
