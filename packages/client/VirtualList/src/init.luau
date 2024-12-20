local Types = require(script:WaitForChild("Types"))
local VirtualScrollList = require(script:WaitForChild("VirtualScrollList"))
local AutoScrollingVirtualScrollList = require(script:WaitForChild("AutoScrollingVirtualScrollList"))

export type ListEntry<T> = Types.ListEntry<T>
export type ListEntryConstructor<T> = Types.ListEntryConstructor<T>
export type VirtualScrollList<T> = VirtualScrollList.VirtualScrollList<T>
export type AutoScrollingVirtualScrollList<T> = AutoScrollingVirtualScrollList.AutoScrollingVirtualScrollList<T>

local VirtualList = {}

function VirtualList.CreateVirtualScrollList<T>(
	ScrollingFrame: ScrollingFrame,
	ListEntryConstructor: Types.ListEntryConstructor<T>,
	Direction: Enum.ScrollingDirection?
): VirtualScrollList<T>
	return VirtualScrollList.new(ScrollingFrame, ListEntryConstructor, Direction)
end

function VirtualList.CreateAutoScrollingVirtualScrollList<T>(
	ScrollingFrame: ScrollingFrame,
	ListEntryConstructor: Types.ListEntryConstructor<T>,
	Direction: Enum.ScrollingDirection?
): AutoScrollingVirtualScrollList<T>
	return AutoScrollingVirtualScrollList.new(ScrollingFrame, ListEntryConstructor, Direction)
end

return VirtualList
