local GamepadService = game:GetService("GamepadService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Gamepad = {}
local Icon

function Gamepad.start(incomingIcon)
	Icon = incomingIcon
	Icon.highlightKey = Enum.KeyCode.DPadUp
	Icon.highlightIcon = false

	task.delay(1, function()
		local iconsDict = Icon.iconsDictionary
		local function getIconFromSelectedObject()
			local clickRegion = GuiService.SelectedObject
			local iconUID = clickRegion and clickRegion:GetAttribute("CorrespondingIconUID")
			local icon = iconUID and iconsDict[iconUID]
			return icon
		end

		local previousHighlightedIcon
		local iconDisplayingHighlightKey
		local usedIndicatorOnce = false
		local usedBOnce = false
		local Utility = require(script.Parent.Parent.Utility)
		local Selection = require(script.Parent.Parent.Elements.Selection)
		local function updateSelectedObject()
			local icon = getIconFromSelectedObject()
			local gamepadEnabled = UserInputService.GamepadEnabled
			if icon then
				if gamepadEnabled then
					local clickRegion = icon:getInstance("ClickRegion")
					local selection = icon.selection
					if not selection then
						selection = icon.janitor:Add(Selection(Icon))
						selection:SetAttribute("IgnoreVisibilityUpdater", true)
						selection.Parent = icon.widget
						icon.selection = selection
						icon:refreshAppearance(selection)
					end
					clickRegion.SelectionImageObject = selection.Selection
				end
				if previousHighlightedIcon and previousHighlightedIcon ~= icon then
					previousHighlightedIcon:setIndicator()
				end
				local newIndicator = if gamepadEnabled
						and not usedBOnce
						and not icon.parentIconUID
					then Enum.KeyCode.ButtonB
					else nil
				previousHighlightedIcon = icon
				Icon.lastHighlightedIcon = icon
				icon:setIndicator(newIndicator)
			else
				local newIndicator = if gamepadEnabled and not usedIndicatorOnce then Icon.highlightKey else nil
				if not previousHighlightedIcon then
					previousHighlightedIcon = Gamepad.getIconToHighlight()
				end
				if newIndicator == Icon.highlightKey then
					usedIndicatorOnce = true
				else
				end
				if previousHighlightedIcon then
					previousHighlightedIcon:setIndicator(newIndicator)
				end
			end
		end
		GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(updateSelectedObject)

		local function checkGamepadEnabled()
			local gamepadEnabled = UserInputService.GamepadEnabled
			if not gamepadEnabled then
				usedIndicatorOnce = false
				usedBOnce = false
			end
			updateSelectedObject()
		end
		UserInputService:GetPropertyChangedSignal("GamepadEnabled"):Connect(checkGamepadEnabled)
		checkGamepadEnabled()

		UserInputService.InputBegan:Connect(function(input, touchingAnObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local icon = getIconFromSelectedObject()
				if icon then
					GuiService.SelectedObject = nil
				end
				return
			end
			if input.KeyCode ~= Icon.highlightKey then
				return
			end
			local iconToHighlight = Gamepad.getIconToHighlight()
			if iconToHighlight then
				if GamepadService.GamepadCursorEnabled then
					task.wait(0.2)
					GamepadService:DisableGamepadCursor()
				end
				local clickRegion = iconToHighlight:getInstance("ClickRegion")
				GuiService.SelectedObject = clickRegion
			end
		end)
	end)
end

function Gamepad.getIconToHighlight()
	local iconsDict = Icon.iconsDictionary
	local iconToHighlight = Icon.highlightIcon or Icon.lastHighlightedIcon
	if not iconToHighlight then
		local currentX
		for _, icon in pairs(iconsDict) do
			if icon.parentIconUID then
				continue
			end
			local thisX = icon.widget.AbsolutePosition.X
			if not currentX or thisX < currentX then
				iconToHighlight = icon
				currentX = iconToHighlight.widget.AbsolutePosition.X
			end
		end
	end
	return iconToHighlight
end

function Gamepad.registerButton(buttonInstance)
	local inputBegan = false
	buttonInstance.InputBegan:Connect(function(input)
		inputBegan = true
		task.wait()
		task.wait()
		inputBegan = false
	end)
	local connection = UserInputService.InputBegan:Connect(function(input)
		task.wait()
		if input.KeyCode == Enum.KeyCode.ButtonA and inputBegan then
			task.wait(0.2)
			GamepadService:DisableGamepadCursor()
			GuiService.SelectedObject = buttonInstance
			return
		end
		local isSelected = GuiService.SelectedObject == buttonInstance
		local unselectKeyCodes = { "ButtonB", "ButtonSelect" }
		local keyName = input.KeyCode.Name
		if table.find(unselectKeyCodes, keyName) and isSelected then
			if not (keyName == "ButtonSelect" and not GamepadService.GamepadCursorEnabled) then
				GuiService.SelectedObject = nil
			end
		end
	end)
	buttonInstance.Destroying:Once(function()
		connection:Disconnect()
	end)
end

return Gamepad
