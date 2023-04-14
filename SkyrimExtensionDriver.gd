extends Node

const my_id = "skyrimExtension"

#--- Called by the system when the script is first loaded.
func extension_loaded():
	var popMan = Globals.get_manager("popups")
	var extensionMenu = popMan.get_popup_data("ExtenMenu")
	extensionMenu.register_entity(my_id, self, "handle_extension_menu")
	extensionMenu.add_option(my_id, "Build list from Mo2")
	extensionMenu.add_option(my_id, "Auto Sort Order")
	
	var modMenu = popMan.get_popup_data("ModPop")
	modMenu.register_entity(my_id, self, "handle_mod_menu")
	modMenu.add_separator(my_id)
	modMenu.add_option(my_id, "Adjust Load Orders")
	modMenu.add_option(my_id, "Adjust Priority Orders")
	modMenu.add_option(my_id, "Adjust Both Orders")
	pass

#--- Called by the system when the script is being unloaded.
func extension_unloaded():
	var popMan = Globals.get_manager("popups")
	popMan.get_popup_data("ExtenMenu").unregister_entity(my_id)
	popMan.get_popup_data("EditMenu").unregister_entity(my_id)
	popMan.get_popup_data("ModPop").unregister_entity(my_id)
	pass

func handle_extension_menu(selection):
	match selection:
		"Auto Sort Order":
			Globals.get_manager("console").generate("Assigning load orders...", Globals.green)
			sort_l_o()
		"Build list from Mo2":
			var searcher = Globals.get_manager("search")
			searcher.search_custom(["*.ini"], FileDialog.ACCESS_FILESYSTEM, FileDialog.MODE_OPEN_FILE, "Find the ModOrganizer.ini file", "Select the Mo2 ini file", "file_selected", self, "construct_from_mo2")
	pass

func construct_from_mo2(iniPath:String):
	var file:File = File.new()
	file.open(iniPath, File.READ)
	var textArray = file.get_as_text().split("\n", false)
	file.close()

	#- Get data from the ini script to locate the actual info.
	var profileName = ""
	var folderPath = iniPath.get_base_dir()
	for line in textArray:
		#- Make sure the correct ini was selected.
		if "gameName=" in line:
			var gameName = line.split("=")[1]
			if not "Skyrim" in gameName:
				Globals.get_manager("console").posterr("Selected an ini file for the wrong game. Please select the ini from within a Skyrim related folder.")
				return
		if "selected_profile=@ByteArray" in line:
			profileName = line.replace("selected_profile=@ByteArray(", "").replace(")", "")
			break
	
	#- Get the installed mods from the profile.
	var profilePath = folderPath + "/profiles/" + profileName + "/"
	var modlistPath = profilePath + "modlist.txt"
	file.open(modlistPath, File.READ)
	var modlist = file.get_as_text().split("\n", false)
	file.close()
	var modsToGenerate = []
	for mod in modlist:
		if not "#" in mod && mod[0] != "-":
			mod.erase(0, 1)
			modsToGenerate.append(mod)
	
	#- Read each mod's ini file and generate a mod entry.
	var modPath = folderPath + "/" + "mods/"
	for mod in modsToGenerate:
		var currentModPath = modPath + mod + "/meta.ini"
		if not file.file_exists(currentModPath):
			continue
		file.open(currentModPath, File.READ)
		var metaData = file.get_as_text().split("\n", false)
		file.close()
		
		# - Cache relevant data to construct the mod data.
		var modId:String = ""
		var modVersion:String = ""
		var modRepository:String = ""
		var modUrl:String = ""
		var isCustomUrl:bool = false
		for line in metaData:
			if "modid=" in line && modId == "":
				modId = line.replace("modid=", "")
			elif "version=" in line && modVersion == "":
				modVersion = line.replace("version=", "")
			elif "repository=" in line && modRepository == "":
				modRepository = line.replace("repository=", "")
			elif "url=" in line:
				modUrl = line.replace("url=", "")
			elif "hasCustomURL=" in line:
				var val:String = line.replace("hasCustomURL=", "")
				val = val.to_lower()
				match val:
					"false":
						isCustomUrl = false
					"true":
						isCustomUrl = true
		
		#- Detect custom made mod folders and ignore them.
		if modId == "0":
			continue

		#- Construct the new mod's data.
		var mData = Globals.modData.new()
		if not isCustomUrl:
			mData.extras.Link = "https://www.nexusmods.com/skyrimspecialedition/mods/" + modId
		else:
			mData.extras.Link = modUrl
		mData.fields["Mods"] = mod
		mData.fields["Type"] = "NEEDS EDIT"
		mData.fields["Version"] = modVersion
		mData.fields["Source"] = modRepository
		mData.fields["Priority Order"] = "0"
		mData.fields["Load Order"] = "0"
		Globals.get_manager("main").add_mod(mData)
	pass


func adjust_field(field:String, selected):
	for mod in Session.data.Mods:
		if mod == selected:
			continue
		if mod.fields[field] >= selected.fields[field]:
			var val = int(mod.fields[field])
			val += 1
			mod.fields[field] = str(val)
	Globals.get_manager("main").repaint_mods()
	Globals.get_manager("console").post(field+"s have been adjusted.")
	pass

func handle_mod_menu(selection):
	match selection:
		#- Pushes every mod back one in the load order to accomodate the new LO placement.
		"Adjust Load Orders": 
			var selected = Globals.get_manager("mtree").get_selected_mod()
			adjust_field("Load Order", selected)
		"Adjust Priority Orders":
			var selected = Globals.get_manager("mtree").get_selected_mod()
			adjust_field("Priority Order", selected)
		"Adjust Both Orders":
			var selected = Globals.get_manager("mtree").get_selected_mod()
			adjust_field("Load Order", selected)
			adjust_field("Priority Order", selected)
	pass

func sort_l_o():
	#- Store any errors in scanData.
	var scanData = Globals.scanData.new()
	
	#- Grab the mod list from the current session.
	var modlist = Session.data.Mods
	var presentMods = {}
	var requiredByAll = []
	var requiresAll = []
	for mod in modlist:
		# "Esp & Archives", "Esp Only", "Archives Only", ".DLL Only", ".DLL & Archives", ".DLL & ESP", ".DLL & ESP & Archives", "Other"
		if mod.fields.Trend == "Get Overwritten":
			requiredByAll.append(mod.extras.Link)
		elif mod.fields.Trend == "Overwrite Others":
			requiresAll.append(mod.extras.Link)
		
		presentMods[mod.extras.Link] = {
			"mod":mod,
			"influence":modlist.size(),
			"masters":[]
		}
		continue
	
	for mod in modlist:
		var requisiteMods = []
		for req in mod.extras.Required:
			if presentMods.has(req.Link):
				requisiteMods.append(presentMods[req.Link])
			else:
				scanData.add_custom("Missing Masters Detected!! Run a scan for more details.", 2)
			continue
		
		if mod.extras.has("Compatible"):
			for com in mod.extras.Compatible:
				if presentMods.has(com.Link):
					requisiteMods.append(presentMods[com.Link])
		
		presentMods[mod.extras.Link].masters = requisiteMods
		continue

	#- Start: Overwrites others logic. Find all mods that require the overwritter mods and ignore them.
	var connectedWriterMods = []
	for mLink in requiresAll:
		connectedWriterMods.append(mLink)

	var doWriterContinue = true
	while (doWriterContinue):
		doWriterContinue = false
		for mLink in presentMods.keys():
			var mod = presentMods[mLink]
			for reqMod in mod.masters:
				if presentMods.has(reqMod.mod.extras.Link) && connectedWriterMods.has(reqMod.mod.extras.Link) && not connectedWriterMods.has(mLink):
					connectedWriterMods.append(mLink)
					doWriterContinue = true
					break
	
	for mLink in presentMods.keys():
		if connectedWriterMods.has(mLink):
			continue
		for cLink in connectedWriterMods:
			presentMods[cLink].masters.append(presentMods[mLink])
	#- End: Overwrites others logic.

	#- Start: Get overwritten logic. Find all mods that are required by the overwritten mods and ignore them.
	var connectedOverwrittenMods = []
	for mLink in requiredByAll:
		connectedOverwrittenMods.append(mLink)
	
	var doOverwrittenContinue = true

	while (doOverwrittenContinue):
		doOverwrittenContinue = false
		for mLink in presentMods.keys():
			var mod = presentMods[mLink]
			for oLink in connectedOverwrittenMods:
				var oMod = presentMods[oLink]
				if oMod.masters.has(mod) && not connectedOverwrittenMods.has(mod.mod.extras.Link):
					connectedOverwrittenMods.append(mod.mod.extras.Link)
					doOverwrittenContinue = true
					break;

	for mLink in presentMods.keys():
		if connectedOverwrittenMods.has(mLink):
			continue
		for cLink in connectedOverwrittenMods:
			presentMods[mLink].masters.append(presentMods[cLink])
	#- End: Get overwritten logic.

	for mod in presentMods.keys():
		var mData = presentMods[mod]
		#- The lower the influence, the lower the resulting load/priority order.
		mData.influence += -1
		increment_masters(presentMods, mData)
		continue
	
	var influnceList = presentMods.values().duplicate()
	influnceList.sort_custom(self, "sort_by_influence")
	var lo = 0
	var po = 0
	for sorted in influnceList:
		# "Esp & Archives", "Esp Only", "Archives Only", "Patch", ".DLL Only", ".DLL & Archives", ".DLL & ESP", ".DLL & ESP & Archives", "Other"
		if sorted.mod.fields["Type"] == ".DLL Only":
			sorted.mod.fields["Load Order"] = str(-1)
			sorted.mod.fields["Priority Order"] = str(-1)
		elif sorted.mod.fields["Type"] == "Archives Only" || sorted.mod.fields["Type"] == ".DLL & Archives":
			sorted.mod.fields["Load Order"] = str(-1)
			sorted.mod.fields["Priority Order"] = str(po)
			po += 1
		elif sorted.mod.fields["Type"] == ".DLL & ESP" || sorted.mod.fields["Type"] == "Esp Only":
			sorted.mod.fields["Load Order"] = str(lo)
			sorted.mod.fields["Priority Order"] = str(-1)
			lo += 1
		else: #"Esp & Archives" || ".DLL & ESP & Archives" || "Patch" || "Other"
			sorted.mod.fields["Load Order"] = str(lo)
			sorted.mod.fields["Priority Order"] = str(po)
			lo += 1
			po += 1
		continue
	
	Globals.get_manager("main").repaint_mods()
	Globals.repaint_app_name(true)
	scanData.closing_msg = "Auto Sort Completed."
	scanData.post_result()
	pass

func increment_masters(presentMods, mData):
	for data in mData.masters:
		var masterDat = presentMods[data.mod.extras.Link]
		masterDat.influence += (mData.influence - 1)
		increment_masters(presentMods, masterDat)
	pass

func sort_by_influence(mData1, mData2):
	var a = mData1.influence
	var b = mData2.influence
	if a > b:
		return true
	return false

#--- Called by the system to access a mod's name.
func get_mod_name(mod):
	return mod.fields.Mods

#--- Called by the system to scan for mod compatibility.
func scan_mods(modlist):
	var scanData = Globals.scanData.new()
	var modLinks = {}
	for mod in modlist:
		if not modLinks.has(mod.extras.Link):
			modLinks[mod.extras.Link] = mod
		else:
			scanData.add_duplication_error(get_mod_name(mod))
	
	for mod in modlist:
		var name = get_mod_name(mod)
		var missingReq = []
		for req in mod.extras.Required:
			if not modLinks.has(req.Link):
				missingReq.append(req)
			else:
				var reqMod = modLinks[req.Link]
				# "Esp & Archives", "Esp Only", "Archives Only", ".DLL Only", ".DLL & Archives", ".DLL & ESP", ".DLL & ESP & Archives", "Other"
				#- Hard overwriting Warning. Is an immediate error. For only Archives.
				if mod.fields["Type"] == "Archives Only":
					if	int(reqMod.fields["Priority Order"]) >= int(mod.fields["Priority Order"]):
						var reqName = get_mod_name(reqMod)
						var msg = "ERR117: (" + name + ") overwrites files from (" + reqName + ") however (" + reqName + ") is overwriting its files!"
						scanData.add_custom(msg, 2)
				
				#- Light overwriting Warning. Not an immediate error. For Archives w/ additions.
				if mod.fields["Type"] == "Esp & Archives" || mod.fields["Type"] == ".DLL & Archives" || mod.fields["Type"] == ".DLL & ESP & Archives" || mod.fields["Type"] == "Other":
					if	int(reqMod.fields["Priority Order"]) >= int(mod.fields["Priority Order"]):
						var reqName = get_mod_name(reqMod)
						var msg = "ERR66: ("+ name +") relies on features from ("+ reqName +") however ("+ reqName +") has a higher priority order. Fix this if bugs occur in-game."
						scanData.add_custom(msg, 1)
				
				#- Hard overwriting Warning. Is an immediate error. For all Esp's.
				if mod.fields["Type"] == "Esp & Archives" || mod.fields["Type"] == "Esp Only" || mod.fields["Type"] == ".DLL & ESP" || mod.fields["Type"] == ".DLL & ESP & Archives" || mod.fields["Type"] == "Other":
					if int(reqMod.fields["Load Order"]) >= int(mod.fields["Load Order"]):
						var reqName = get_mod_name(reqMod)
						var msg = "ERR314: (" + name + ") requires (" + reqName + ") as a master however (" + reqName + ") has a higher load order!"
						scanData.add_custom(msg, 2)
		
		for inc in mod.extras.Incompatible:
			if modLinks.has(inc.Link):
				if inc.Patchable:
					if modLinks.has(inc.Patch):
						continue
					else:
						scanData.add_patchable_error(name, inc)
				else:
					scanData.add_unpatchable_error(name, inc)
		
		if mod.extras.has("Compatible"):
			for com in mod.extras.Compatible:
				if modLinks.has(com.Link):
					var orderToCheck = "Load"
					if mod.fields["Type"] == "Archives Only" || mod.fields["Type"] == "Esp & Archives" || mod.fields["Type"] == ".DLL & Archives" || mod.fields["Type"] == ".DLL & ESP & Archives" || mod.fields["Type"] == "Other":
						orderToCheck = "Priority"
					var comName = get_mod_name(modLinks[com.Link])
					if "Do" in com.Overwrite && int(modLinks[com.Link].fields[orderToCheck+" Order"]) > int(mod.fields[orderToCheck+" Order"]):
						scanData.add_custom("Notice: (" + name + ") is compatible with (" + comName + ") however ("+ name + ") should have a higher "+ orderToCheck +" Order. E.g. No--> 0-25 <--Yes")
					elif "Get" in com.Overwrite && int(modLinks[com.Link].fields[orderToCheck+" Order"]) < int(mod.fields[orderToCheck+" Order"]):
						scanData.add_custom("Notice: (" + name + ") is compatible with (" + comName + ") however ("+ comName + ") should have a higher "+ orderToCheck +" Order. E.g. No--> 0-25 <--Yes")
		
		if missingReq.size() > 0:
			for i in range(missingReq.size()):
				scanData.add_required_error(name, missingReq[i])
	
	#- Return the scan results so the system can parse them.
	return scanData

#--- Called by the system to sort the mod tree.
#- orientation: 0 = descending, 1 = ascending.
func sort_mod_list(category, orientation, modlist:Array):
	var copy = modlist.duplicate()
	match category:
		"Mods":
			if orientation == 0:
				copy.sort_custom(self, "s_m_d")
			elif orientation == 1:
				copy.sort_custom(self, "s_m_a")
		"Type":
			if orientation == 0:
				copy.sort_custom(self, "s_t_d")
			elif orientation == 1:
				copy.sort_custom(self, "s_t_a")
		"Version":
			if orientation == 0:
				copy.sort_custom(self, "s_v_d")
			elif orientation == 1:
				copy.sort_custom(self, "s_v_a")
		"Source":
			if orientation == 0:
				copy.sort_custom(self, "s_s_d")
			elif orientation == 1:
				copy.sort_custom(self, "s_s_a")
		"Priority Order":
			if orientation == 0:
				copy.sort_custom(self, "s_p_d")
			elif orientation == 1:
				copy.sort_custom(self, "s_p_a")
		"Load Order":
			if orientation == 0:
				copy.sort_custom(self, "s_l_d")
			elif orientation == 1:
				copy.sort_custom(self, "s_l_a")
	return copy

func sort_desc(mod_a, mod_b, field, isString = true):
	var a = mod_a.fields[field] if isString == true else int(mod_a.fields[field])
	var b = mod_b.fields[field] if isString == true else int(mod_b.fields[field])
	if a > b:
		return true
	return false

func sort_asce(mod_a, mod_b, field, isString = true):
	var a = mod_a.fields[field] if isString == true else int(mod_a.fields[field])
	var b = mod_b.fields[field] if isString == true else int(mod_b.fields[field])
	if a < b:
		return true
	return false

func s_m_d(mod_a, mod_b):
	return sort_desc(mod_a, mod_b, "Mods")

func s_m_a(mod_a, mod_b):
	return sort_asce(mod_a, mod_b, "Mods")

func s_t_d(mod_a, mod_b):
	return sort_desc(mod_a, mod_b, "Type")

func s_t_a(mod_a, mod_b):
	return sort_asce(mod_a, mod_b, "Type")

func s_v_d(mod_a, mod_b):
	return sort_desc(mod_a, mod_b, "Version")

func s_v_a(mod_a, mod_b):
	return sort_asce(mod_a, mod_b, "Version")

func s_s_d(mod_a, mod_b):
	return sort_desc(mod_a, mod_b, "Source")

func s_s_a(mod_a, mod_b):
	return sort_asce(mod_a, mod_b, "Source")

func s_p_d(mod_a, mod_b):
	return sort_desc(mod_a, mod_b, "Priority Order", false)

func s_p_a(mod_a, mod_b):
	return sort_asce(mod_a, mod_b, "Priority Order", false)

func s_l_d(mod_a, mod_b):
	return sort_desc(mod_a, mod_b, "Load Order", false)

func s_l_a(mod_a, mod_b):
	return sort_asce(mod_a, mod_b, "Load Order", false)
