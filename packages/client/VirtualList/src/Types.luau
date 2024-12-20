export type ListEntry<T> = {
	GuiInstance: GuiObject,
	Update: (self: ListEntry<T>, Index: number, Data: T) -> ListEntry<T>,
	Destroy: (self: ListEntry<T>) -> (),
}

export type ListEntryConstructor<T> = (InitialIndex: number, InitialData: T) -> ListEntry<T>

return true
