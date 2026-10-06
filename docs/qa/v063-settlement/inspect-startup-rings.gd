extends SceneTree
var differences:Array=[]
func _initialize()->void:
	var prefix:=OS.get_environment("COMPARE_PREFIX")
	var before:Variant=bytes_to_var(FileAccess.get_file_as_bytes(prefix+"before-no_burn-no_burn.bin"))
	var after:Variant=bytes_to_var(FileAccess.get_file_as_bytes(prefix+"after-no_burn-no_burn.bin"))
	for i:int in range(before.size()):before[i].erase("rings");after[i].erase("rings")
	print("After diagnostic-only omission of startup rings, exact bytes equal: ",var_to_bytes(before)==var_to_bytes(after))
	diff(before,after,"root")
	print(JSON.stringify(differences,"\t",true,true));quit(0)
func diff(a:Variant,b:Variant,path:String)->void:
	if differences.size()>=12:return
	if typeof(a)!=typeof(b):differences.append({"path":path,"reason":"type","a":typeof(a),"b":typeof(b)});return
	if a is Dictionary:
		if var_to_bytes(a.keys())!=var_to_bytes(b.keys()):differences.append({"path":path,"reason":"keys","a":str(a.keys()),"b":str(b.keys())});return
		for k:Variant in a:diff(a[k],b[k],path+"."+str(k))
	elif a is Array:
		if a.size()!=b.size():differences.append({"path":path,"reason":"length","a":a.size(),"b":b.size()});return
		for i:int in range(a.size()):diff(a[i],b[i],path+"["+str(i)+"]")
	elif var_to_bytes(a)!=var_to_bytes(b):differences.append({"path":path,"reason":"value","a":str(a).substr(0,300),"b":str(b).substr(0,300)})
