local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Types = require(script.Parent:WaitForChild("Types"))
local VirtualScrollList = require(script.Parent:WaitForChild("VirtualScrollList"))

local AutoScrollingVirtualScrollList = {}
AutoScrollingVirtualScrollList.__index = AutoScrollingVirtualScrollList

export type AutoScrollingVirtualScrollList<T> = {
	ScrollingFrame: ScrollingFrame,
	VirtualScrollList: VirtualScrollList.VirtualScrollList<T>,
	Data: { T },
	AutoScrollEventConnection: RBXScriptConnection?,
	EventConnections: { RBXScriptConnection },
} & typeof(setmetatable({}, AutoScrollingVirtualScrollList))

function AutoScrollingVirtualScrollList.new<T>(
	ScrollingFrame: ScrollingFrame,
	ListEntryConstructor: Types.ListEntryConstructor<T>,
	Direction: Enum.ScrollingDirection?
): AutoScrollingVirtualScrollList<T>
	local self = setmetatable({
		ScrollingFrame = ScrollingFrame,
		VirtualScrollList = VirtualScrollList.new(ScrollingFrame, ListEntryConstructor, Direction),
		Data = {},
		EventConnections = {},
	}, AutoScrollingVirtualScrollList) :: AutoScrollingVirtualScrollList<T>

	self.VirtualScrollList.OverrideAdditionalEntries = 0
	ScrollingFrame.ScrollingEnabled = false
	ScrollingFrame.ScrollBarThickness = 0

	table.insert(
		self.EventConnections,
		ScrollingFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
			self:UpdateScrollingFrameContents()
		end)
	)
	table.insert(
		self.EventConnections,
		ScrollingFrame.Destroying:Connect(function()
			self:Destroy()
		end)
	)

	return self
end

function AutoScrollingVirtualScrollList.UpdateScrollingFrameContents<T>(self: AutoScrollingVirtualScrollList<T>): ()
	local IsHorizontal = (self.VirtualScrollList.Direction == Enum.ScrollingDirection.X)
	local WindowHeight = IsHorizontal and self.ScrollingFrame.AbsoluteWindowSize.X
		or self.ScrollingFrame.AbsoluteWindowSize.Y
	local EntryHeight = self.VirtualScrollList.EntryHeight
	local TotalDisplayEntries = math.ceil(WindowHeight / EntryHeight)

	local TotalDataEntries = #self.Data
	local NewData = {}
	for i = 1, TotalDataEntries do
		table.insert(NewData, self.Data[i])
	end
	if TotalDataEntries > TotalDisplayEntries then
		for i = 1, TotalDisplayEntries do
			table.insert(NewData, self.Data[i])
		end
	end

	self.VirtualScrollList:SetData(NewData)
end

function AutoScrollingVirtualScrollList.MoveCanvasTo<T>(self: AutoScrollingVirtualScrollList<T>, Offset: number): ()
	local IsHorizontal = (self.VirtualScrollList.Direction == Enum.ScrollingDirection.X)
	local EntryHeight = self.VirtualScrollList.EntryHeight
	local CanvasMaxPosition = #self.Data * EntryHeight
	if CanvasMaxPosition == 0 then
		Offset = 0
	end
	while Offset < 0 do
		Offset += CanvasMaxPosition
	end
	while Offset > CanvasMaxPosition do
		Offset += -CanvasMaxPosition
	end

	if IsHorizontal then
		self.ScrollingFrame.CanvasPosition = Vector2.new(Offset, 0)
	else
		self.ScrollingFrame.CanvasPosition = Vector2.new(0, Offset)
	end
end

function AutoScrollingVirtualScrollList.MoveCanvasToRelative<T>(
	self: AutoScrollingVirtualScrollList<T>,
	Multiplier: number
): ()
	self:MoveCanvasTo(Multiplier * self.VirtualScrollList.EntryHeight)
end

function AutoScrollingVirtualScrollList.OffsetCanvas<T>(self: AutoScrollingVirtualScrollList<T>, Offset: number): ()
	local IsHorizontal = (self.VirtualScrollList.Direction == Enum.ScrollingDirection.X)
	local CanvasPosition = IsHorizontal and self.ScrollingFrame.CanvasPosition.X or self.ScrollingFrame.CanvasPosition.Y
	self:MoveCanvasTo(CanvasPosition + Offset)
end

function AutoScrollingVirtualScrollList.OffsetCanvasRelative<T>(
	self: AutoScrollingVirtualScrollList<T>,
	Multiplier: number
): ()
	self:OffsetCanvas(Multiplier * self.VirtualScrollList.EntryHeight)
end

function AutoScrollingVirtualScrollList.StopAutoScrolling<T>(self: AutoScrollingVirtualScrollList<T>): ()
	if not self.AutoScrollEventConnection then
		return
	end
	self.AutoScrollEventConnection:Disconnect()
	self.AutoScrollEventConnection = nil
end

function AutoScrollingVirtualScrollList.StartAutoScrolling<T>(
	self: AutoScrollingVirtualScrollList<T>,
	Multiplier: number
): ()
	self:StopAutoScrolling()

	local LastShiftTime: number? = nil
	self.AutoScrollEventConnection = RunService.Stepped:Connect(function(_, DeltaTime: number)
		if GuiService.ReducedMotionEnabled then
			local IsHorizontal = (self.VirtualScrollList.Direction == Enum.ScrollingDirection.X)
			local EntryHeight = self.VirtualScrollList.EntryHeight
			local WindowHeight = IsHorizontal and self.ScrollingFrame.AbsoluteWindowSize.X
				or self.ScrollingFrame.AbsoluteWindowSize.Y
			if not LastShiftTime then
				local CanvasPosition = IsHorizontal and self.ScrollingFrame.CanvasPosition.X
					or self.ScrollingFrame.CanvasPosition.Y
				self:MoveCanvasToRelative(math.floor(CanvasPosition / EntryHeight))
				LastShiftTime = tick()
			end

			local VisibleEntries = math.floor(WindowHeight / EntryHeight)
			if (tick() - LastShiftTime :: number) >= VisibleEntries / Multiplier then
				self:OffsetCanvasRelative(VisibleEntries)
				LastShiftTime = tick()
			end
		else
			self:OffsetCanvasRelative(DeltaTime * Multiplier)
			LastShiftTime = nil
		end
	end)
end

function AutoScrollingVirtualScrollList.SetScrollWidth<T>(self: AutoScrollingVirtualScrollList<T>, ScrollWidth: UDim): ()
	self.VirtualScrollList:SetScrollWidth(ScrollWidth)
end

function AutoScrollingVirtualScrollList.SetEntryHeight<T>(self: AutoScrollingVirtualScrollList<T>, EntryHeight: number): ()
	self.VirtualScrollList:SetEntryHeight(EntryHeight)
	self:UpdateScrollingFrameContents()
end

function AutoScrollingVirtualScrollList.SetData<T>(self: AutoScrollingVirtualScrollList<T>, Data: { T }): ()
	self.Data = Data
	self:UpdateScrollingFrameContents()
end

function AutoScrollingVirtualScrollList.Destroy<T>(self: AutoScrollingVirtualScrollList<T>): ()
	self:StopAutoScrolling()
	for _, Connection in self.EventConnections do
		Connection:Disconnect()
	end
	self.EventConnections = {}

	self.VirtualScrollList:Destroy()
end

return AutoScrollingVirtualScrollList
