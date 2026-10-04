class_name ItemRarityStyle
extends RefCounted
static func border(rarity:String)->Color:
	return {"normal":Color("777467"),"magic":Color("42649a"),"rare":Color("ad7f21"),"unique":Color("aa582b"),"special":Color("775285")}.get(rarity,Color("777467"))
static func background(rarity:String)->Color:
	return {"normal":Color("e4dfcf"),"magic":Color("cbd7e8"),"rare":Color("ead89b"),"unique":Color("dfbea1"),"special":Color("dacbe1")}.get(rarity,Color("e4dfcf"))
