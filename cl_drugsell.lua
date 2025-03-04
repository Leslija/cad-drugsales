local QBCore = exports[Config.Core]:GetCoreObject()

-- \ Locals and tables
local SoldPeds = {}
local SellZone = {}
local CurrentZone = nil
local AllowedTarget = (not Config.ShouldToggleSelling)
local InitiateSellProgress = false

-- \ Create Zones for the drug sales
for k, v in pairs(Config.Zones) do
    SellZone[k] = PolyZone:Create(v.points, {
        name= k,
        minZ = v.minZ,
        maxZ = v.maxZ,
        debugPoly = Config.Debug,
    })
end

-- \ Send police alert on drug sale
local function PoliceAlert()
    -- Add Your alert system here
	-- exports['ps-dispatch']:DrugSale() -- (PS DISPATCH)
	TriggerServerEvent('police:server:policeAlert', 'Drug sale in progress') -- (DEFAULT QBCore)
	if Config.Debug then print('Police Notify Function triggered') end
end

-- \ Play five animation for both player and ped
local function PlayGiveAnim(tped)
	local pid = PlayerPedId()
	FreezeEntityPosition(pid, true)
	QBCore.Functions.RequestAnimDict('mp_common')
	TaskPlayAnim(pid, "mp_common", "givetake2_a", 8.0, -8, 2000, 0, 1, 0,0,0)
	TaskPlayAnim(tped, "mp_common", "givetake2_a", 8.0, -8, 2000, 0, 1, 0,0,0)
	FreezeEntityPosition(pid, false)
end

-- \ Add Old Ped to table
local function AddSoldPed(entity)
    SoldPeds[entity] = true
end

--\ Check if ped is in table
local function HasSoldPed(entity)
    return SoldPeds[entity] ~= nil
end

local function ShowSellMenu(ped, item, amt, price)
	InitiateSellProgress = true
	local SaleMenu = {
		{
			header = tostring(amt).."x of "..QBCore.Shared.Items[item]['label'].." for "..QBCore.Shared.Round(amt * price, 0).."$",
			isMenuHeader = true
		},
		{
			header = "Accept Offer",
			params = {
				event = 'cad-drugsales:salesinitiate',
				args = {
					type = 'buy',
					item = item,
					price = price,
					amt = amt,
					tped = ped
				}
			}
		},
		{
			header = "Decline Offer",
			params = {
				event = 'cad-drugsales:salesinitiate',
				args = {
					type = 'close',
					tped = ped
				}
			}
		}
	}
	exports[Config.Menu]:openMenu(SaleMenu)
	SetTimeout(Config.SellTimeout*1000, function()
		if InitiateSellProgress then
			TriggerEvent("cad-drugsales:notify", "You wasted time so the person left")
			TriggerEvent("qb-menu:client:closeMenu")
			SetPedAsNoLongerNeeded(ped)
		end
	end)
end

-- DEPRECATED
--[[
local function HasItem(item, amount)
	if Config.Inventory == 'ox' then
		local count = exports.ox_inventory:Search('count', item)
		return count >= amount
	elseif Config.Inventory == 'qb' then
		return exports["qb-inventory"]:HasItem(item, amount)
	else
		return QBCore.Functions.HasItem(item, amount)
	end
end
]]

local function GetItems(drug)
	if Config.Inventory == 'ox' then
		local count = exports.ox_inventory:Search('count', drug)
		return count
	else
		local amount = 0
		local items = QBCore.Functions.GetPlayerData().items
		for _, v in pairs(items) do
			if v.name == drug then
				amount = v.amount
				break
			end
		end
		return amount
	end
end

local function InitiateSell(ped)
	if not CurrentZone then return end
	local index = Config.ZoneDrugs[CurrentZone.name]
	local randamt = math.random(Config.RandomMinSell, Config.RandomMaxSell)
	local tries = 0
	for i=1, #index do
		Wait(200) -- done change this
		local data = index[math.random(1, #index)]
		local maxamt = GetItems(data.item)
		local price = data.price
		if maxamt ~= 0 then
			if randamt > maxamt then randamt = 1 end
			ShowSellMenu(ped, data.item, randamt, price)
			break
		else
			tries += i
			if tries == #index then SetPedAsNoLongerNeeded(ped) TriggerEvent('QBCore:Notify', 'Person wanted more stuff but you dint have!') end
			if Config.Debug then print('You dont have ['..data.item..'] to sell') end
		end
	end
end

-- \ Interact with the ped
local function InteractPed(ped)
	local Playerjob = QBCore.Functions.GetPlayerData().job
	SetEntityAsMissionEntity(ped, true, true)
	TaskTurnPedToFaceEntity(ped, PlayerPedId(), Config.SellTimeout*1000)
	Wait(500)
	if Playerjob.name == 'police' then
		TriggerEvent('QBCore:Notify', 'Locals hate cops!')
		SetPedAsNoLongerNeeded(ped)
		if Config.Debug then print('Police Not allowed') end
		return
	end
	local percent = math.random(1, 100)
	if percent < Config.ChanceSell then
		InitiateSell(ped)
	else
		if Config.Debug then print('Police has been notified') end
		TriggerEvent('cad-drugsales:notify', 'The buyer is calling the police!')
		TaskUseMobilePhoneTimed(ped, 8000)
		PoliceAlert()
		SetPedAsNoLongerNeeded(ped)
	end
end

-- \ Initialize the drug sales
local function InitiateSales(entity)
	QBCore.Functions.TriggerCallback('cad-drugsales:server:GetCops', function(result)
		if result < Config.MinimumCops then
			TriggerEvent('cad-drugsales:notify', 'Buyer is not interested to buy now!')
			if Config.Debug then print('Not Enough Cops') end
		else
			local netId = NetworkGetNetworkIdFromEntity(entity)
			local isSoldtoPed = HasSoldPed(netId)
			if isSoldtoPed then TriggerEvent('cad-drugsales:notify', 'You already spoke with this local') return false end
			AddSoldPed(netId)
			InteractPed(entity)
			if Config.Debug then print('Drug Sales Initiated now proceding to interact') end
		end
	end)
end

-- \ Blacklist Ped Models
local function isPedBlacklisted(ped)
	local model = GetEntityModel(ped)
	for i = 1, #Config.BlacklistPeds do
		if model == GetHashKey(Config.BlacklistPeds[i]) then
			return true
		end
	end
	return false
end

-- \ Sell Drugs to peds inside the sellzone
local function CreateTarget()
	exports[Config.Target]:AddGlobalPed({
		options = {
			{
				icon = 'fas fa-comments',
				label = 'Talk',
				action = function(entity)
					InitiateSales(entity)
				end,
				canInteract = function(entity)
					if CurrentZone then
						if not IsPedDeadOrDying(entity, false) and not IsPedInAnyVehicle(entity, false) and CurrentZone.inside and (GetPedType(entity)~=28) and (not IsPedAPlayer(entity)) and (not isPedBlacklisted(entity)) and not IsPedInAnyVehicle(PlayerPedId(), false) then
							return true
						end
					end
					return false
				end,
			}
		},
		distance = 4,
	})
end
exports('CreateTarget', CreateTarget)

-- \ Remove Sell Drugs to peds inside the sellzone
local function RemoveTarget()
	exports[Config.Target]:RemoveGlobalPed({"Talk"})
end
exports('RemoveTarget', RemoveTarget)

-- \ This will toggle allowing/disallowing target even if inside zone
local function IsTargetAllowed(value)
	AllowedTarget = value
end
exports('AllowedTarget', IsTargetAllowed)

-- \ Notify event for client/server
RegisterNetEvent('cad-drugsales:notify', function(msg)
	if Config.Debug then print('Notify:'..msg) end
	TriggerEvent('QBCore:Notify', msg, "primary", 5000)
end)

-- \ event handler to server (execute server side)
RegisterNetEvent('cad-drugsales:salesinitiate', function(cad)
	if cad.type == 'close' then
		InitiateSellProgress = false
		TriggerEvent("cad-drugsales:notify", "You rejected the offer")
		TriggerEvent("qb-menu:client:closeMenu")
		SetPedAsNoLongerNeeded(cad.tped)
	else
		InitiateSellProgress = false
		PlayGiveAnim(cad.tped)
		TriggerServerEvent("cad-drugsales:initiatedrug", cad)
		SetPedAsNoLongerNeeded(cad.tped)
	end
end)

-- \ Toggle selling (radialmenu)
if Config.ShouldToggleSelling then
RegisterNetEvent('cad-drugsales:toggleselling', function()
	AllowedTarget = not AllowedTarget
	if AllowedTarget then
		CreateTarget()
		TriggerEvent("cad-drugsales:notify", "Enabled Selling")
	else
		RemoveTarget()
		TriggerEvent("cad-drugsales:notify", "Disabled Selling")
	end
end)

exports[Config.RadialMenu]:AddOption({
	id = 'caddrugsales',
	title = 'Corner Selling',
	icon = 'cannabis',
	type = 'client',
	event = 'cad-drugsales:toggleselling',
	shouldClose = true
})
end

-- \ Check if inside sellzone
CreateThread(function()
	while true do
		if SellZone and next(SellZone) then
			local ped = PlayerPedId()
			local coord = GetEntityCoords(ped)
			for k, _ in pairs(SellZone) do
				if SellZone[k] then
					if SellZone[k]:isPointInside(coord) then
						SellZone[k].inside = true
                        CurrentZone = SellZone[k]
						if not SellZone[k].target then
							SellZone[k].target = true
							if not Config.ShouldToggleSelling then CreateTarget() end
							if Config.Debug then print("Target Added ["..CurrentZone.name.."]") end
						end
						if Config.Debug then print(json.encode(CurrentZone)) end
					else
						SellZone[k].inside = false
						if SellZone[k].target then
							SellZone[k].target = false
							if not Config.ShouldToggleSelling then RemoveTarget() end
							if Config.Debug then print("Target Removed ["..CurrentZone.name.."]") end
						end
					end
				end
			end
		end
		Wait(1000)
	end
end)
