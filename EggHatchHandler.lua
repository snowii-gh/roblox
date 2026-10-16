local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ServerScriptService:WaitForChild("Modules")
local popUpHandler = require(modules:WaitForChild("PopUpHandler"))
local mutationColourer = require(modules:WaitForChild("MutationColourer"))

local eggsHandler = script.Parent
local eggInfo = require(eggsHandler:WaitForChild("EggInfo"))
local duckInfo = require(eggsHandler:WaitForChild("DuckInfo"))
local mutationsInfo = require(eggsHandler:WaitForChild("MutationsInfo"))

local sharedModules = ReplicatedStorage:WaitForChild("Modules")
local modelToTool = require(sharedModules:WaitForChild("ModelToTool"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local events = remotes:WaitForChild("Events")
local PlaceEggEvent = events:WaitForChild("PlaceEgg")
local PlaySoundEvent = events:WaitForChild("PlaySound")
local PlayVFXEvent = events:WaitForChild("PlayVFX")

local eggModels = ReplicatedStorage:WaitForChild("Eggs")
local duckModels = ReplicatedStorage:WaitForChild("Ducks")

local eggHatchHandler = {}

local function updateMoneyLabel(infoGui, money)
	local moneyLabel = infoGui:FindFirstChild("Money")

	if moneyLabel then
		moneyLabel.Text = `${money}`
	end
end

local function updateMPSLabel(player: Player, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local MPS = leaderstats:FindFirstChild("MPS")

	local playerGui = player:WaitForChild("PlayerGui")
	local buttonsGui = playerGui:WaitForChild("ButtonsGui")
	local totalMPSLabel = buttonsGui:WaitForChild("TotalMPSLabel")

	MPS.Value += amount
	totalMPSLabel.Text = `MPS: ${MPS.Value}/s`
end

function eggHatchHandler.mainLoop(player: Player, duck)
	local currentDuckInfo = duckInfo[duck.Name]
	local moneyPerSecond = currentDuckInfo.Money
	local MPSLabel = duck:FindFirstChild("MPSLabel", true)

	local mutation = duck:GetAttribute("Mutation")
	local mutationInfo = mutationsInfo[mutation]
	local mutationMoneyMultipler = mutationInfo.MoneyMultiplier

	if mutationMoneyMultipler then
		moneyPerSecond *= mutationMoneyMultipler
	else
		warn(`Could not money multiplier for {mutation}!`)
	end

	updateMPSLabel(player, moneyPerSecond)

	if MPSLabel then
		MPSLabel.Text = `${moneyPerSecond}/s`
	else
		warn("No MPS label for " .. duck.Name)
	end

	local cooldown = false

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats:FindFirstChild("Money")
	if not leaderstats or not money then warn("No leaderstats/money for " .. player.Name) return end

	local hitbox = duck:FindFirstChild("Hitbox", true)
	if not hitbox then return end

	local infoGui = duck:FindFirstChild("InfoGui")

	local hitboxConnection = hitbox.Touched:Connect(function(hit)
		if hit:FindFirstAncestor(player.Character.Name) and not cooldown then
			cooldown = true
			money.Value += duck:GetAttribute("Money")
			duck:SetAttribute("Money", 0)
			if infoGui then
				updateMoneyLabel(infoGui, 0)
			end

			PlaySoundEvent:FireClient(player, "Purchase")

			task.wait(0.5)
			cooldown = false
		end
	end)

	while duck do
		duck:SetAttribute("Money", duck:GetAttribute("Money") + moneyPerSecond)
		if infoGui then
			updateMoneyLabel(infoGui, duck:GetAttribute("Money"))
		else
			warn(`Could not find money gui inside of {duck.Name}!`)
		end

		task.wait(1)
	end

	hitboxConnection:Disconnect()
end

local function formatTime(totalSeconds)
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = totalSeconds % 60

	return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

function eggHatchHandler.hatch(eggModel, hatchTime)
	local infoGui = eggModel:WaitForChild("InfoGui")
	
	hatchTime = hatchTime or eggInfo[eggModel.Name].HatchTime
	local hatchTimeLabel = infoGui:WaitForChild("TimeLabel")

	hatchTimeLabel.Visible = true
	
	for i = hatchTime, 0, -1 do
		if not eggModel.Parent then return end
		hatchTimeLabel.Text = `Hatches in: {formatTime(i)}`
		task.wait(1)
	end
	
	local mainSpot = eggModel.Parent
	print(mainSpot)
	local placementPart = mainSpot:FindFirstChild("PlacementPart")

	local mutation = eggModel:GetAttribute("Mutation")

	local currentEggInfo = eggInfo[eggModel.Name]
	local duckPool = currentEggInfo.Ducks

	local counter = 1
	local randomNumber = math.random(1, 100)
	local chosenDuck

	for duck, chance in duckPool do
		counter += chance
		if randomNumber < counter then
			chosenDuck = duck
			break
		end
	end

	eggModel:Destroy()

	chosenDuck = duckModels:FindFirstChild(chosenDuck)
	if not chosenDuck then
		warn(`Unable to find {chosenDuck} inside of duckModels. Check that chances add to 0, and that the model actually exists.`)
		chosenDuck = duckModels["Dirty Duck"]
	end
	
	chosenDuck = chosenDuck:Clone()

	chosenDuck:SetAttribute("Mutation", mutation)
	mutationColourer.colour(chosenDuck, mutation)
	
	if mutation ~= "Nothing" then
		local infoGui = chosenDuck:FindFirstChild("InfoGui")
		local mutationLabel = infoGui:FindFirstChild("MutationLabel")

		mutationLabel.Visible = true
		mutationLabel.Text = mutation
		mutationColourer.colourLabel(mutationLabel, mutation)
	end

	chosenDuck:PivotTo(CFrame.new(placementPart.Position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(placementPart.Orientation.Y), 0))

	chosenDuck.Parent = mainSpot

	return chosenDuck
end

function eggHatchHandler.unlockSpot(player: Player, mainSpot: Model, loadingData: boolean)
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats:FindFirstChild("Money")

	local spotPrice = mainSpot:GetAttribute("Price")
	if not spotPrice then return end
	
	local placementPart = mainSpot:FindFirstChild("PlacementPart")
	
	local numberOfUnlocked = 0
	for i, child in mainSpot.Parent:GetChildren() do
		if child:GetAttribute("Unlocked") then
			numberOfUnlocked += 1
		end
	end

	local triggeredPrompt = placementPart:FindFirstChildOfClass("ProximityPrompt")

	if money.Value >= spotPrice or loadingData then
		if not loadingData then
			money.Value -= spotPrice
		end

		mainSpot:SetAttribute("Unlocked", true)

		triggeredPrompt.ActionText = "Place Item"
		triggeredPrompt.ObjectText = "Spot"

		local spotsFolder = mainSpot:FindFirstAncestor("Spots")
		if not spotsFolder then return end

		local nextSpot = spotsFolder:FindFirstChild(tostring(numberOfUnlocked + 2))
		if nextSpot then
			local nextPrompt = nextSpot:FindFirstChild("ProximityPrompt", true)
			if nextPrompt then
				nextPrompt.Enabled = true
			end

			local nextPlacementPart = nextSpot:FindFirstChild("PlacementPart")
			if nextPlacementPart then
				nextPlacementPart.Color = Color3.fromRGB(0, 255, 0)
			end

			for _, child in nextSpot:GetChildren() do
				if child:IsA("Part") then
					child.Transparency = 0
				end
			end

			local nextPriceGui = nextSpot:FindFirstChild("Price")
			if nextPriceGui then
				nextPriceGui.Enabled = true
			end
		end

		local priceGui = mainSpot:FindFirstChild("Price")
		if priceGui then
			priceGui.Enabled = false
		end

		if placementPart then
			placementPart.Color = Color3.fromRGB(99, 95, 98)
		end

		PlaySoundEvent:FireClient(player, "Purchase")
		PlayVFXEvent:FireClient(player, "Purchase", placementPart)
	else
		popUpHandler.popUp(player, "Not enough money!", Color3.fromRGB(255, 0, 0))
	end
end

PlaceEggEvent.OnServerEvent:Connect(function(player, triggeredPrompt)
	local character = player.Character
	local currentTool = character:FindFirstChildOfClass("Tool")

	local mainSpot = triggeredPrompt.Parent.Parent
	local placementPart = mainSpot:FindFirstChild("PlacementPart")

	if mainSpot:GetAttribute("HasEgg") then
		local model = mainSpot:FindFirstChildOfClass("Model")
		local mutation = model:GetAttribute("Mutation")

		if model then
			local tool

			local storedEggModel = eggModels:FindFirstChild(model.Name, true)
			local storedDuckModel = duckModels:FindFirstChild(model.Name, true)
			if storedEggModel then
				tool = modelToTool.convertToTool(storedEggModel, 0.5)
			elseif storedDuckModel then
				tool = modelToTool.convertToTool(storedDuckModel, 0.7)
			end

			if tool then
				tool = tool:Clone()
				tool.Parent = player.Backpack
				local starterTool = tool:Clone()
				starterTool.Parent = player.StarterGear

				if mutation then
					tool:SetAttribute("Mutation", mutation)
					starterTool:SetAttribute("Mutation", mutation)
					mutationColourer.colour(tool, mutation)
					mutationColourer.colour(starterTool, mutation)
				end

				model:Destroy()
				mainSpot:SetAttribute("HasEgg", false)

				triggeredPrompt.ActionText = "Place Item"
				triggeredPrompt.ObjectText = "Spot"

				if storedDuckModel then
					local currentDuckInfo = duckInfo[storedDuckModel.Name]
					local rawDuckMPS = currentDuckInfo.Money
					local currentMutationInfo = mutationsInfo[mutation]
					local mutationMoneyMultiplier = currentMutationInfo.MoneyMultiplier

					local finalDuckMPS = rawDuckMPS * mutationMoneyMultiplier
					updateMPSLabel(player, -finalDuckMPS)
				end
			else
				warn(`Could not find tool: {model.Name}, {model.Parent}`)
			end
		end

		return
	end

	if not mainSpot:GetAttribute("Unlocked") then
		eggHatchHandler.unlockSpot(player, mainSpot, false)

		return
	end

	if triggeredPrompt:FindFirstAncestor(tostring(player.UserId)) and currentTool then
		local mutation = currentTool:GetAttribute("Mutation")
		print(mutation)

		local toolModel

		for i, descendant in eggModels:GetDescendants() do
			if descendant.Name == currentTool.Name and descendant.Parent:IsA("Folder") then
				toolModel = descendant
				break
			end
		end

		if not toolModel then
			toolModel = duckModels:FindFirstChild(currentTool.Name)

			if toolModel then
				toolModel = toolModel:Clone()

				toolModel:SetAttribute("Mutation", mutation)
				mutationColourer.colour(toolModel, mutation)

				toolModel:PivotTo(CFrame.new(placementPart.Position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(placementPart.Orientation.Y), 0))
				toolModel.Parent = mainSpot

				currentTool:Destroy()

				triggeredPrompt.ActionText = "Pick up"
				triggeredPrompt.ObjectText = "Duck"

				mainSpot:SetAttribute("HasEgg", true)

				eggHatchHandler.mainLoop(player, toolModel)
			else
				warn("Could not find tool model for " .. currentTool.Name)
			end

			return
		end

		toolModel = toolModel:Clone()

		local nameColor

		local infoGui = toolModel:FindFirstChild("InfoGui")

		for _, child in infoGui:GetChildren() do
			if child:IsA("TextLabel") or child:IsA("CanvasGroup") then
				if child.Name == "Name" then
					nameColor = child.TextColor3
					continue
				end

				if child.Name ~= "TimeLabel" and child.Name ~= "MutationLabel" then
					child:Destroy()
				end
			end
		end

		local placementPart = triggeredPrompt.Parent
		if not placementPart then
			warn(`Could not find placement part for {mainSpot.Name}`)
			return
		end

		mainSpot:SetAttribute("HasEgg", true)

		toolModel:SetAttribute("Mutation", mutation)
		mutationColourer.colour(toolModel, mutation)

		toolModel:PivotTo(CFrame.new(placementPart.Position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(placementPart.Orientation.Y), 0))
		toolModel.Parent = mainSpot

		currentTool:Destroy()

		if mutation ~= "Nothing" then
			local mutationLabel = infoGui:FindFirstChild("MutationLabel")
			
			mutationLabel.Visible = true
			mutationLabel.Text = mutation
			mutationColourer.colourLabel(mutationLabel, mutation)
		end

		triggeredPrompt.ActionText = "Pick Up"
		triggeredPrompt.ObjectText = "Egg"

		local duck = eggHatchHandler.hatch(toolModel)
		
		triggeredPrompt.ObjectText = "Duck"
		
		eggHatchHandler.mainLoop(player, duck)
	end
end)

return eggHatchHandler