local Studio_Viewport_Size = Vector2.new(1920, 1080)

local Auto_Tag = false

local Update_Delay = 1

local Billboard_Tag = "Billboard"
local Screen_Gui_Tag = "ScreenGui"
local Screen_Stroke_Tag = "ScreenStroke"
local Default_Billboard_Distance = 10

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui", 100)

local camera = workspace.CurrentCamera

local function getBox(vector: Vector2): number
	return math.min(vector.X, vector.Y)
end

local function getScreenRatio(): number
	return getBox(camera.ViewportSize) / getBox(Studio_Viewport_Size)
end

local function tagRecursive(instance: Instance, objectType: string, tag: string)
	if instance:IsA(objectType) then
		CollectionService:AddTag(instance, tag)
	end
	for _, child in instance:GetChildren() do
		tagRecursive(child, objectType, tag)
	end
	instance.ChildAdded:Connect(function(child)
		tagRecursive(child, objectType, tag)
	end)
end

local function getInstancePosition(instance: Instance): Vector3
	if instance:IsA("Part") then
		return instance.Position
	elseif instance:IsA("Model") then
		local cf, size = instance:GetBoundingBox()
		return cf.Position
	end
	return Vector3.new(0, 0, 0)
end

local ScreenStrokes = {}

local function updateScreenGuiStrokes()
	for uiStroke, originalThickness in ScreenStrokes do
		if not uiStroke.Parent then
			ScreenStrokes[uiStroke] = nil
		else
			uiStroke.Thickness = originalThickness * getScreenRatio()
		end
	end
end

if Auto_Tag then
	tagRecursive(PlayerGui, "ScreenGui", Screen_Gui_Tag)
	tagRecursive(PlayerGui, "BillboardGui", Billboard_Tag)
end

local initialized = false

function init()
	local function newScreenGuiTag(screenGui)
		tagRecursive(screenGui, "UIStroke", Screen_Stroke_Tag)
	end

	local function newScreenStrokeTag(uiStroke)
		ScreenStrokes[uiStroke] = uiStroke.Thickness
		uiStroke.Thickness *= getScreenRatio()
	end

	local function newBillboardTag(billboardGui)
		local BillboardStrokes = {}
		local function getUiStrokeFromInstance(instance: Instance)
			if instance:IsA("UIStroke") then
				BillboardStrokes[instance] = instance.Thickness
			end
			for _, uiStroke in instance:GetChildren() do
				getUiStrokeFromInstance(uiStroke)
			end
			instance.ChildAdded:Connect(getUiStrokeFromInstance)
		end
		getUiStrokeFromInstance(billboardGui)

		local start = tick()
		local update
		update = RunService.Heartbeat:Connect(function()
			if tick() - start > Update_Delay then
				return
			end
			start = tick()

			if not billboardGui.Parent then
				update:Disconnect()
			else
				local adornee = billboardGui.Adornee
				local origin = adornee and getInstancePosition(adornee) or getInstancePosition(billboardGui.Parent)
				local magnitude = (camera.CFrame.Position - origin).Magnitude
				local distanceRatio = (
					(billboardGui:GetAttribute("Distance") or Default_Billboard_Distance) / magnitude
				)
				for stroke, originalThickness in BillboardStrokes do
					if not stroke.Parent then
						BillboardStrokes[stroke] = nil
					else
						stroke.Thickness = originalThickness * distanceRatio * getScreenRatio()
					end
				end
			end
		end)
	end

	CollectionService:GetInstanceAddedSignal(Screen_Gui_Tag):Connect(function(screenGui: ScreenGui)
		newScreenGuiTag(screenGui)
	end)

	CollectionService:GetInstanceAddedSignal(Screen_Stroke_Tag):Connect(function(uiStroke: UIStroke)
		newScreenStrokeTag(uiStroke)
	end)

	CollectionService:GetInstanceAddedSignal(Billboard_Tag):Connect(function(billboardGui: BillboardGui)
		newBillboardTag(billboardGui)
	end)

	local TaggedScreenGui = CollectionService:GetTagged(Screen_Gui_Tag)
	for _, obj in ipairs(TaggedScreenGui) do
		if obj:IsA("ScreenGui") then
			newScreenGuiTag(obj)
		end
	end

	local TaggedScreenStroke = CollectionService:GetTagged(Screen_Stroke_Tag)
	for _, obj in ipairs(TaggedScreenStroke) do
		if obj:IsA("UIStroke") then
			newScreenStrokeTag(obj)
		end
	end

	local TaggedBillboards = CollectionService:GetTagged(Billboard_Tag)
	for _, obj in ipairs(TaggedBillboards) do
		if obj:IsA("BillboardGui") and obj:IsDescendantOf(workspace) then
			newBillboardTag(obj)
		end
	end

	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScreenGuiStrokes)
end

if not initialized then
	initialized = true
	init()
end

local UIStrokeAdjuster = {}

function UIStrokeAdjuster:TagScreenGui(screenGui: ScreenGui)
	if screenGui:IsA("ScreenGui") then
		CollectionService:AddTag(screenGui, Screen_Gui_Tag)
	end
end

function UIStrokeAdjuster:TagBillboardGui(billboardGui: BillboardGui)
	if billboardGui:IsA("BillboardGui") then
		CollectionService:AddTag(billboardGui, Billboard_Tag)
	end
end

return UIStrokeAdjuster
