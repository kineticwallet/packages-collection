local ADDITIONAL_ENTRIES_MULTIPLUER = 0.5

local Types = require(script.Parent:WaitForChild("Types"))

local VirtualScrollList = {}
VirtualScrollList.__index = VirtualScrollList

export type VirtualScrollList<T> = {
	ListEntryConstructor: Types.ListEntryConstructor<T>,
	ScrollingFrame: ScrollingFrame,
	Direction: Enum.ScrollingDirection,
	ScrollWidth: UDim,
	EntryHeight: number,
	OverrideAdditionalEntries: number?,
	LastEntryHeight: number,
	Data: { T },
	Entries: { [number]: Types.ListEntry<T> },
	StaleEntries: { { LastIndex: number, Entry: Types.ListEntry<T> } },
	EventConnections: { RBXScriptConnection },
} & typeof(setmetatable({}, VirtualScrollList))

function VirtualScrollList.new<T>(
	ScrollingFrame: ScrollingFrame,
	ListEntryConstructor: Types.ListEntryConstructor<T>,
	Direction: Enum.ScrollingDirection?
): VirtualScrollList<T>
	local self = setmetatable({
		ListEntryConstructor = ListEntryConstructor,
		ScrollingFrame = ScrollingFrame,
		ScrollWidth = UDim.new(0, 0),
		Direction = Direction or Enum.ScrollingDirection.Y,
		EntryHeight = 20,
		LastEntryHeight = 20,
		Data = {},
		Entries = {},
		StaleEntries = {},
		EventConnections = {},
	}, VirtualScrollList) :: VirtualScrollList<T>

	table.insert(
		self.EventConnections,
		ScrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self:UpdateScrollingFrameContents()
		end)
	)
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

function VirtualScrollList.UpdateScrollingFrameContents<T>(self: VirtualScrollList<T>): ()
	debug.profilebegin("VirtualScrollList.UpdateScrollingFrameContents")
	local IsHorizontal = (self.Direction == Enum.ScrollingDirection.X)
	local CanvasPosition = IsHorizontal and self.ScrollingFrame.CanvasPosition.X or self.ScrollingFrame.CanvasPosition.Y
	local WindowHeight = IsHorizontal and self.ScrollingFrame.AbsoluteWindowSize.X
		or self.ScrollingFrame.AbsoluteWindowSize.Y
	local EntryHeight = self.EntryHeight
	local TotalDisplayEntries = math.ceil(WindowHeight / EntryHeight)
	local AdditionalEntries = self.OverrideAdditionalEntries
		or math.ceil(ADDITIONAL_ENTRIES_MULTIPLUER * TotalDisplayEntries)
	local BaseStartIndex = math.floor(CanvasPosition / EntryHeight)
	local StartIndex = math.max(0, BaseStartIndex - AdditionalEntries)
	local EndIndex = math.min(#self.Data - 1, BaseStartIndex + TotalDisplayEntries + AdditionalEntries)

	debug.profilebegin("VirtualScrollList.UpdateScrollingFrameContents.InvalidateFrames")
	local ResizeExistingEntries = (self.LastEntryHeight ~= EntryHeight)
	local EntriesToRemove = {}
	for i, Entry in self.Entries do
		if i - 1 >= StartIndex and i - 1 <= EndIndex then
			continue
		end
		EntriesToRemove[i] = Entry
	end
	for i, Entry in EntriesToRemove do
		self.Entries[i] = nil
		if ResizeExistingEntries or i > #self.Data then
			Entry:Destroy()
		else
			table.insert(self.StaleEntries, { LastIndex = i, Entry = Entry })
		end
	end
	debug.profileend()

	debug.profilebegin("VirtualScrollList.UpdateScrollingFrameContents.ReuseStaleFrames")
	local EntrySize = (IsHorizontal and UDim2.new(0, EntryHeight, 1, 0) or UDim2.new(1, 0, 0, EntryHeight))
	for i = #self.StaleEntries, 1, -1 do
		local StaleEntry = self.StaleEntries[i]
		local StaleEntryIndex = StaleEntry.LastIndex
		if self.Entries[StaleEntryIndex] then
			continue
		end
		if StaleEntryIndex - 1 < StartIndex or StaleEntryIndex - 1 > EndIndex then
			continue
		end

		local EntryPosition = (
			IsHorizontal and UDim2.new(0, (StaleEntryIndex - 1) * EntryHeight, 0, 0)
			or UDim2.new(0, 0, 0, (StaleEntryIndex - 1) * EntryHeight)
		)
		local ExistingEntry = StaleEntry.Entry
		ExistingEntry.GuiInstance.Position = EntryPosition
		ExistingEntry.GuiInstance.Size = EntrySize
		ExistingEntry:Update(StaleEntryIndex, self.Data[StaleEntryIndex])
		table.remove(self.StaleEntries, i)
		self.Entries[StaleEntryIndex] = ExistingEntry
	end
	debug.profileend()

	debug.profilebegin("VirtualScrollList.UpdateScrollingFrameContents.UpdateContents")
	for i = StartIndex, EndIndex do
		local Index = i + 1
		local ExistingEntry = self.Entries[Index]
		local EntryPosition = (
			IsHorizontal and UDim2.new(0, i * EntryHeight, 0, 0) or UDim2.new(0, 0, 0, i * EntryHeight)
		)
		if ExistingEntry then
			if ResizeExistingEntries then
				ExistingEntry.GuiInstance.Position = EntryPosition
				ExistingEntry.GuiInstance.Size = EntrySize
			end
			continue
		end

		local NewEntry = nil
		if #self.StaleEntries > 0 then
			NewEntry = self.StaleEntries[#self.StaleEntries].Entry
			table.remove(self.StaleEntries, #self.StaleEntries)
			NewEntry:Update(Index, self.Data[Index])
		else
			NewEntry = self.ListEntryConstructor(Index, self.Data[Index])
			NewEntry.GuiInstance.Parent = self.ScrollingFrame
		end

		NewEntry.GuiInstance.Position = EntryPosition
		NewEntry.GuiInstance.Size = EntrySize
		self.Entries[Index] = NewEntry
	end
	self.LastEntryHeight = EntryHeight
	debug.profileend()

	debug.profilebegin("VirtualScrollList.UpdateScrollingFrameContents.RemoveVisibleStaleFrames")
	for i = #self.StaleEntries, 1, -1 do
		local StaleEntry = self.StaleEntries[i]
		local StaleEntryIndex = StaleEntry.LastIndex
		if StaleEntryIndex - 1 < StartIndex or StaleEntryIndex - 1 > EndIndex then
			continue
		end
		StaleEntry.Entry:Destroy()
		table.remove(self.StaleEntries, i)
	end
	debug.profileend()
	debug.profileend()
end

function VirtualScrollList.UpdateScrollingFrameSize<T>(self: VirtualScrollList<T>): ()
	local IsHorizontal = (self.Direction == Enum.ScrollingDirection.X)
	local ScrollingEntryWidth = UDim.new(self.ScrollWidth.Scale, self.ScrollWidth.Offset)
	local ScrollingEntryHeight = UDim.new(0, #self.Data * self.EntryHeight)
	self.ScrollingFrame.CanvasSize = UDim2.new(
		IsHorizontal and ScrollingEntryHeight or ScrollingEntryWidth,
		IsHorizontal and ScrollingEntryWidth or ScrollingEntryHeight
	)
end

function VirtualScrollList.SetScrollWidth<T>(self: VirtualScrollList<T>, ScrollWidth: UDim): ()
	self.ScrollWidth = ScrollWidth

	self:UpdateScrollingFrameSize()
end

function VirtualScrollList.SetEntryHeight<T>(self: VirtualScrollList<T>, EntryHeight: number): ()
	self.EntryHeight = EntryHeight
	for _, Entry in self.StaleEntries do
		Entry.Entry:Destroy()
	end
	self.StaleEntries = {}

	self:UpdateScrollingFrameSize()
	self:UpdateScrollingFrameContents()
end

function VirtualScrollList.SetDataEntry<T>(self: VirtualScrollList<T>, Index: number, Data: T): ()
	local PreviousDataEntry = self.Data[Index]
	self.Data[Index] = Data

	local ExistingEntry = self.Entries[Index]
	if ExistingEntry then
		ExistingEntry:Update(Index, Data)
	end

	if PreviousDataEntry then
		return
	end
	self:UpdateScrollingFrameSize()
	self:UpdateScrollingFrameContents()
end

function VirtualScrollList.SetData<T>(self: VirtualScrollList<T>, Data: { T }): ()
	self.Data = Data

	for i, Entry in self.Entries do
		local ExistingData = Data[i]
		if not ExistingData then
			continue
		end
		Entry:Update(i, ExistingData)
	end

	self:UpdateScrollingFrameSize()
	self:UpdateScrollingFrameContents()
end

function VirtualScrollList.Destroy<T>(self: VirtualScrollList<T>): ()
	for _, Connection in self.EventConnections do
		Connection:Disconnect()
	end
	self.EventConnections = {}

	for _, Entry in self.Entries do
		Entry:Destroy()
	end
	self.Entries = {}
	for _, Entry in self.StaleEntries do
		Entry.Entry:Destroy()
	end
	self.StaleEntries = {}
end

return VirtualScrollList
