local AUTO_SAVE_PERIOD = 300
local LOAD_REPEAT_PERIOD = 10
local FIRST_LOAD_REPEAT = 5
local SESSION_STEAL = 40
local ASSUME_DEAD = 630
local START_SESSION_TIMEOUT = 120

local CRITICAL_STATE_ERROR_COUNT = 5
local CRITICAL_STATE_ERROR_EXPIRE = 120
local CRITICAL_STATE_EXPIRE = 120

local MAX_MESSAGE_QUEUE = 1000

local Signal
do
	local FreeRunnerThread

	local function AcquireRunnerThreadAndCallEventHandler(fn, ...)
		local acquired_runner_thread = FreeRunnerThread
		FreeRunnerThread = nil
		fn(...)

		FreeRunnerThread = acquired_runner_thread
	end

	local function RunEventHandlerInFreeThread(...)
		AcquireRunnerThreadAndCallEventHandler(...)
		while true do
			AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
		end
	end

	local Connection = {}
	Connection.__index = Connection

	local SignalClass = {}
	SignalClass.__index = SignalClass

	function Connection:Disconnect()
		if self.is_connected == false then
			return
		end

		local signal = self.signal
		self.is_connected = false
		signal.listener_count -= 1

		if signal.head == self then
			signal.head = self.next
		else
			local prev = signal.head
			while prev ~= nil and prev.next ~= self do
				prev = prev.next
			end
			if prev ~= nil then
				prev.next = self.next
			end
		end
	end

	function SignalClass.New()
		local self = {
			head = nil,
			listener_count = 0,
		}
		setmetatable(self, SignalClass)

		return self
	end

	function SignalClass:Connect(listener: (...any) -> ())
		if type(listener) ~= "function" then
			error(`[{script.Name}]: \"listener\" must be a function; Received {typeof(listener)}`)
		end

		local connection = {
			listener = listener,
			signal = self,
			next = self.head,
			is_connected = true,
		}
		setmetatable(connection, Connection)

		self.head = connection
		self.listener_count += 1

		return connection
	end

	function SignalClass:GetListenerCount(): number
		return self.listener_count
	end

	function SignalClass:Fire(...)
		local item = self.head
		while item ~= nil do
			if item.is_connected == true then
				if not FreeRunnerThread then
					FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
				end
				task.spawn(FreeRunnerThread, item.listener, ...)
			end
			item = item.next
		end
	end

	function SignalClass:Wait()
		local co = coroutine.running()
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			task.spawn(co, ...)
		end)
		return coroutine.yield()
	end

	Signal = table.freeze({
		New = SignalClass.New,
	})
end

local ActiveSessionCheck = {}
local AutoSaveList = {}
local IssueQueue = {}

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local PlaceId = game.PlaceId
local JobId = game.JobId

local AutoSaveIndex = 1
local LastAutoSave = os.clock()

local LoadIndex = 0

local ActiveProfileLoadJobs = 0
local ActiveProfileSaveJobs = 0

local CriticalStateStart = 0

local IsStudio = RunService:IsStudio()
local DataStoreState: "NotReady" | "NoInternet" | "NoAccess" | "Access" = "NotReady"

local MockStore = {}
local UserMockStore = {}
local MockFlag = false

local OnError = Signal.New()
local OnOverwrite = Signal.New()

local UpdateQueue = {}

local function WaitInUpdateQueue(session_token)
	local is_first = false

	if UpdateQueue[session_token] == nil then
		is_first = true
		UpdateQueue[session_token] = {}
	end

	local queue = UpdateQueue[session_token]

	if is_first == false then
		table.insert(queue, coroutine.running())
		coroutine.yield()
	end

	return function()
		local next_co = table.remove(queue, 1)
		if next_co ~= nil then
			coroutine.resume(next_co)
		else
			UpdateQueue[session_token] = nil
		end
	end
end

local function SessionToken(store_name, profile_key, is_mock)
	local session_token = "L_"

	if is_mock == true then
		session_token = "U_"
	elseif DataStoreState ~= "Access" then
		session_token = "M_"
	end

	session_token ..= store_name .. "\0" .. profile_key

	return session_token
end

local function DeepCopyTable(t)
	local copy = {}
	for key, value in pairs(t) do
		if type(value) == "table" then
			copy[key] = DeepCopyTable(value)
		else
			copy[key] = value
		end
	end
	return copy
end

local function ReconcileTable(target, template)
	for k, v in pairs(template) do
		if type(k) == "string" then
			if target[k] == nil then
				if type(v) == "table" then
					target[k] = DeepCopyTable(v)
				else
					target[k] = v
				end
			elseif type(target[k]) == "table" and type(v) == "table" then
				ReconcileTable(target[k], v)
			end
		end
	end
end

local function RegisterError(error_message, store_name, profile_key)
	warn(`[{script.Name}]: DataStore API error (STORE:{store_name}; KEY:{profile_key}) - {tostring(error_message)}`)
	table.insert(IssueQueue, os.clock())
	OnError:Fire(tostring(error_message), store_name, profile_key)
end

local function RegisterOverwrite(store_name, profile_key)
	warn(`[{script.Name}]: Invalid profile was overwritten (STORE:{store_name}; KEY:{profile_key})`)
	OnOverwrite:Fire(store_name, profile_key)
end

local function NewMockDataStoreKeyInfo(params)
	local version_id_string = tostring(params.VersionId or 0)
	local meta_data = params.MetaData or {}
	local user_ids = params.UserIds or {}

	return {
		CreatedTime = params.CreatedTime,
		UpdatedTime = params.UpdatedTime,
		Version = string.rep("0", 16)
			.. "."
			.. string.rep("0", 10 - string.len(version_id_string))
			.. version_id_string
			.. "."
			.. string.rep("0", 16)
			.. "."
			.. "01",

		GetMetadata = function()
			return DeepCopyTable(meta_data)
		end,

		GetUserIds = function()
			return DeepCopyTable(user_ids)
		end,
	}
end

local function MockUpdateAsync(mock_data_store, profile_store_name, key, transform_function, is_get_call)
	local profile_store = mock_data_store[profile_store_name]

	if profile_store == nil then
		profile_store = {}
		mock_data_store[profile_store_name] = profile_store
	end

	local epoch_time = math.floor(os.time() * 1000)
	local mock_entry = profile_store[key]
	local mock_entry_was_nil = false

	if mock_entry == nil then
		mock_entry_was_nil = true
		if is_get_call ~= true then
			mock_entry = {
				Data = nil,
				CreatedTime = epoch_time,
				UpdatedTime = epoch_time,
				VersionId = 0,
				UserIds = {},
				MetaData = {},
			}
			profile_store[key] = mock_entry
		end
	end

	local mock_key_info = mock_entry_was_nil == false and NewMockDataStoreKeyInfo(mock_entry) or nil

	local transform, user_ids, roblox_meta_data = transform_function(mock_entry and mock_entry.Data, mock_key_info)

	if transform == nil then
		return nil
	else
		if mock_entry ~= nil and is_get_call ~= true then
			mock_entry.Data = DeepCopyTable(transform)
			mock_entry.UserIds = DeepCopyTable(user_ids or {})
			mock_entry.MetaData = DeepCopyTable(roblox_meta_data or {})
			mock_entry.VersionId += 1
			mock_entry.UpdatedTime = epoch_time
		end

		return DeepCopyTable(transform), mock_entry ~= nil and NewMockDataStoreKeyInfo(mock_entry) or nil
	end
end

local function UpdateAsync(profile_store, profile_key, transform_params, is_user_mock, is_get_call, version)
	local loaded_data, key_info

	local next_in_queue = WaitInUpdateQueue(SessionToken(profile_store.Name, profile_key, is_user_mock))

	local success = true

	local success, error_message = pcall(function()
		local transform_function = function(latest_data)
			local missing_profile = false
			local overwritten = false
			local global_updates = { 0, {} }

			if latest_data == nil then
				missing_profile = true
			elseif type(latest_data) ~= "table" then
				missing_profile = true
				overwritten = true
			else
				if
					type(latest_data.Data) == "table"
					and type(latest_data.MetaData) == "table"
					and type(latest_data.GlobalUpdates) == "table"
				then
					latest_data.WasOverwritten = false
					global_updates = latest_data.GlobalUpdates

					if transform_params.ExistingProfileHandle ~= nil then
						transform_params.ExistingProfileHandle(latest_data)
					end
				elseif
					latest_data.Data == nil
					and latest_data.MetaData == nil
					and type(latest_data.GlobalUpdates) == "table"
				then
					latest_data.WasOverwritten = false
					global_updates = latest_data.GlobalUpdates or global_updates
					missing_profile = true
				else
					missing_profile = true
					overwritten = true
				end
			end

			if missing_profile == true then
				latest_data = {

					GlobalUpdates = global_updates,
				}
				if transform_params.MissingProfileHandle ~= nil then
					transform_params.MissingProfileHandle(latest_data)
				end
			end

			if transform_params.EditProfile ~= nil then
				transform_params.EditProfile(latest_data)
			end

			if overwritten == true then
				latest_data.WasOverwritten = true
			end

			return latest_data, latest_data.UserIds, latest_data.RobloxMetaData
		end

		if is_user_mock == true then
			loaded_data, key_info =
				MockUpdateAsync(UserMockStore, profile_store.Name, profile_key, transform_function, is_get_call)
			task.wait()
		elseif DataStoreState ~= "Access" then
			loaded_data, key_info =
				MockUpdateAsync(MockStore, profile_store.Name, profile_key, transform_function, is_get_call)
			task.wait()
		else
			if is_get_call == true then
				if version ~= nil then
					local success, error_message = pcall(function()
						loaded_data, key_info = profile_store.data_store:GetVersionAsync(profile_key, version)
					end)

					if
						success == false
						and type(error_message) == "string"
						and string.find(error_message, "not valid") ~= nil
					then
						warn(`[{script.Name}]: Passed version argument is not valid; Traceback:\n` .. debug.traceback())
					end
				else
					loaded_data, key_info = profile_store.data_store:GetAsync(profile_key)
				end

				loaded_data = transform_function(loaded_data)
			else
				loaded_data, key_info = profile_store.data_store:UpdateAsync(profile_key, transform_function)
			end
		end
	end)

	next_in_queue()

	if success == true and type(loaded_data) == "table" then
		if loaded_data.WasOverwritten == true and is_get_call ~= true then
			RegisterOverwrite(profile_store.Name, profile_key)
		end

		return loaded_data, key_info
	else
		RegisterError(error_message or "Undefined error", profile_store.Name, profile_key)

		return nil
	end
end

local function IsThisSession(session_tag)
	return session_tag[1] == PlaceId and session_tag[2] == JobId
end

local function ReadMockFlag(): boolean
	local is_mock = MockFlag
	MockFlag = false
	return is_mock
end

local function WaitForStoreReady(profile_store)
	while profile_store.is_ready == false do
		task.wait()
	end
end

local function AddProfileToAutoSave(profile)
	ActiveSessionCheck[profile.session_token] = profile

	table.insert(AutoSaveList, AutoSaveIndex, profile)

	if #AutoSaveList > 1 then
		AutoSaveIndex = AutoSaveIndex + 1
	elseif #AutoSaveList == 1 then
		LastAutoSave = os.clock()
	end
end

local function RemoveProfileFromAutoSave(profile)
	ActiveSessionCheck[profile.session_token] = nil

	local auto_save_index = table.find(AutoSaveList, profile)

	if auto_save_index ~= nil then
		table.remove(AutoSaveList, auto_save_index)
		if auto_save_index < AutoSaveIndex then
			AutoSaveIndex = AutoSaveIndex - 1
		end
		if AutoSaveList[AutoSaveIndex] == nil then
			AutoSaveIndex = 1
		end
	end
end

local function SaveProfileAsync(profile, is_ending_session, is_overwriting, last_save_reason)
	if type(profile.Data) ~= "table" then
		error(
			`[{script.Name}]: Developer code likely set "Profile.Data" to a non-table value! (STORE:{profile.ProfileStore.Name}; KEY:{profile.Key})`
		)
	end

	profile.OnSave:Fire()
	if is_ending_session == true then
		profile.OnLastSave:Fire(last_save_reason or "Manual")
	end

	if is_ending_session == true and is_overwriting ~= true then
		if profile.roblox_message_subscription ~= nil then
			profile.roblox_message_subscription:Disconnect()
		end
		RemoveProfileFromAutoSave(profile)
		profile.OnSessionEnd:Fire()
	end

	ActiveProfileSaveJobs = ActiveProfileSaveJobs + 1

	local repeat_save_flag = true
	local exp_backoff = 1

	while repeat_save_flag == true do
		if is_ending_session ~= true then
			repeat_save_flag = false
		end

		local loaded_data, key_info = UpdateAsync(profile.ProfileStore, profile.Key, {
			ExistingProfileHandle = nil,
			MissingProfileHandle = nil,
			EditProfile = function(latest_data)
				local session_owns_profile = false

				if is_overwriting ~= true then
					local active_session = latest_data.MetaData.ActiveSession
					local session_load_count = latest_data.MetaData.SessionLoadCount

					if type(active_session) == "table" then
						session_owns_profile = IsThisSession(active_session)
							and session_load_count == profile.load_index
					end
				else
					session_owns_profile = true
				end

				if session_owns_profile == true then
					local locked_updates = profile.locked_global_updates
					local active_updates = latest_data.GlobalUpdates[2]

					if next(locked_updates) ~= nil then
						local i = 1
						while i <= #active_updates do
							local update = active_updates[i]
							if locked_updates[update[1]] == true then
								table.remove(active_updates, i)
							else
								i += 1
							end
						end
					end

					latest_data.Data = profile.Data
					latest_data.RobloxMetaData = profile.RobloxMetaData
					latest_data.UserIds = profile.UserIds

					if is_overwriting ~= true then
						latest_data.MetaData.LastUpdate = os.time()

						if is_ending_session == true then
							latest_data.MetaData.ActiveSession = nil
						end
					else
						latest_data.MetaData.ActiveSession = nil
						latest_data.MetaData.ForceLoadSession = nil
					end
				end
			end,
		}, profile.is_mock)

		if loaded_data ~= nil and key_info ~= nil then
			if is_overwriting == true then
				break
			end

			repeat_save_flag = false

			local active_session = loaded_data.MetaData.ActiveSession
			local session_load_count = loaded_data.MetaData.SessionLoadCount
			local session_owns_profile = false

			if type(active_session) == "table" then
				session_owns_profile = IsThisSession(active_session) and session_load_count == profile.load_index
			end

			local force_load_session = loaded_data.MetaData.ForceLoadSession
			local force_load_pending = false
			if type(force_load_session) == "table" then
				force_load_pending = not IsThisSession(force_load_session)
			end

			local is_active = profile:IsActive()

			if force_load_pending == true and session_owns_profile == true then
				if is_active == true then
					SaveProfileAsync(profile, true, false, "External")
				end
				break
			end

			local locked_updates = profile.locked_global_updates
			local received_updates = profile.received_global_updates
			local active_updates = loaded_data.GlobalUpdates[2]

			local new_updates = {}
			local still_pending = {}

			for _, update in ipairs(active_updates) do
				if locked_updates[update[1]] == true then
					still_pending[update[1]] = true
				elseif received_updates[update[1]] ~= true then
					received_updates[update[1]] = true
					table.insert(new_updates, update)
				end
			end

			for index in pairs(locked_updates) do
				if still_pending[index] ~= true then
					locked_updates[index] = nil
				end
			end

			profile.KeyInfo = key_info
			profile.LastSavedData = loaded_data.Data
			profile.global_updates = loaded_data.GlobalUpdates and loaded_data.GlobalUpdates[2] or {}

			if session_owns_profile == true then
				if is_active == true and is_ending_session ~= true then
					for _, update in ipairs(new_updates) do
						local index = update[1]
						local update_data = update[#update]

						for _, handler in ipairs(profile.message_handlers) do
							local is_processed = false
							local processed_callback = function()
								is_processed = true
								locked_updates[index] = true
							end

							local send_update_data = DeepCopyTable(update_data)

							task.spawn(handler, send_update_data, processed_callback)

							if is_processed == true then
								break
							end
						end
					end
				end
			else
				if profile.roblox_message_subscription ~= nil then
					profile.roblox_message_subscription:Disconnect()
				end

				if is_active == true then
					RemoveProfileFromAutoSave(profile)
					profile.OnSessionEnd:Fire()
				end
			end

			profile.OnAfterSave:Fire(profile.LastSavedData)
		elseif repeat_save_flag == true then
			task.wait(exp_backoff)
			exp_backoff = math.min(if last_save_reason == "Shutdown" then 8 else 20, exp_backoff * 2)
		end
	end

	ActiveProfileSaveJobs = ActiveProfileSaveJobs - 1
end

export type JSONAcceptable = { JSONAcceptable } | { [string]: JSONAcceptable } | number | string | boolean | buffer

export type Profile<T> = {
	Data: T & JSONAcceptable,
	LastSavedData: T & JSONAcceptable,
	FirstSessionTime: number,
	SessionLoadCount: number,
	Session: { PlaceId: number, JobId: string }?,
	RobloxMetaData: JSONAcceptable,
	UserIds: { number },
	KeyInfo: DataStoreKeyInfo,
	OnSave: { Connect: (self: any, listener: () -> ()) -> { Disconnect: (self: any) -> () } },
	OnLastSave: {
		Connect: (
			self: any,
			listener: (reason: "Manual" | "External" | "Shutdown") -> ()
		) -> { Disconnect: (self: any) -> () },
	},
	OnSessionEnd: { Connect: (self: any, listener: () -> ()) -> { Disconnect: (self: any) -> () } },
	OnAfterSave: {
		Connect: (
			self: any,
			listener: (last_saved_data: T & JSONAcceptable) -> ()
		) -> { Disconnect: (self: any) -> () },
	},
	ProfileStore: JSONAcceptable,
	Key: string,

	IsActive: (self: any) -> boolean,
	Reconcile: (self: any) -> (),
	EndSession: (self: any) -> (),
	AddUserId: (self: any, user_id: number) -> (),
	RemoveUserId: (self: any, user_id: number) -> (),
	MessageHandler: (self: any, fn: (message: JSONAcceptable, processed: () -> ()) -> ()) -> (),
	Save: (self: any) -> (),
	SetAsync: (self: any) -> (),
}

export type VersionQuery<T> = {
	NextAsync: (self: any) -> Profile<T>?,
}

type ProfileStoreStandard<T> = {
	Name: string,
	StartSessionAsync: (self: any, profile_key: string, params: { Steal: boolean? }) -> Profile<T>?,
	MessageAsync: (self: any, profile_key: string, message: JSONAcceptable) -> boolean,
	GetAsync: (self: any, profile_key: string, version: string?) -> Profile<T>?,
	VersionQuery: (
		self: any,
		profile_key: string,
		sort_direction: Enum.SortDirection?,
		min_date: DateTime | number | nil,
		max_date: DateTime | number | nil
	) -> VersionQuery<T>,
	RemoveAsync: (self: any, profile_key: string) -> boolean,
}

export type ProfileStore<T> = {
	Mock: ProfileStoreStandard<T>,
} & ProfileStoreStandard<T>

type ConstantName =
	"AUTO_SAVE_PERIOD"
	| "LOAD_REPEAT_PERIOD"
	| "FIRST_LOAD_REPEAT"
	| "SESSION_STEAL"
	| "ASSUME_DEAD"
	| "START_SESSION_TIMEOUT"
	| "CRITICAL_STATE_ERROR_COUNT"
	| "CRITICAL_STATE_ERROR_EXPIRE"
	| "CRITICAL_STATE_EXPIRE"
	| "MAX_MESSAGE_QUEUE"

export type ProfileStoreModule = {
	IsClosing: boolean,
	IsCriticalState: boolean,
	OnError: {
		Connect: (
			self: any,
			listener: (message: string, store_name: string, profile_key: string) -> ()
		) -> { Disconnect: (self: any) -> () },
	},
	OnOverwrite: {
		Connect: (
			self: any,
			listener: (store_name: string, profile_key: string) -> ()
		) -> { Disconnect: (self: any) -> () },
	},
	OnCriticalToggle: {
		Connect: (self: any, listener: (is_critical: boolean) -> ()) -> { Disconnect: (self: any) -> () },
	},
	DataStoreState: "NotReady" | "NoInternet" | "NoAccess" | "Access",
	New: <T>(store_name: string, template: (T & JSONAcceptable)?) -> ProfileStore<T>,
	SetConstant: (name: ConstantName, value: number) -> (),
}

local Profile = {}
Profile.__index = Profile

function Profile.New(raw_data, key_info, profile_store, key, is_mock, session_token)
	local data = raw_data.Data or {}
	local session = raw_data.MetaData and raw_data.MetaData.ActiveSession or nil

	local global_updates = raw_data.GlobalUpdates and raw_data.GlobalUpdates[2] or {}
	local received_global_updates = {}

	for _, update in ipairs(global_updates) do
		received_global_updates[update[1]] = true
	end

	local self = {

		Data = data,
		LastSavedData = DeepCopyTable(data),

		FirstSessionTime = raw_data.MetaData and raw_data.MetaData.ProfileCreateTime or 0,
		SessionLoadCount = raw_data.MetaData and raw_data.MetaData.SessionLoadCount or 0,
		Session = session and { PlaceId = session[1], JobId = session[2] },

		RobloxMetaData = raw_data.RobloxMetaData or {},
		UserIds = raw_data.UserIds or {},
		KeyInfo = key_info,

		OnAfterSave = Signal.New(),
		OnSave = Signal.New(),
		OnLastSave = Signal.New(),
		OnSessionEnd = Signal.New(),

		ProfileStore = profile_store,
		Key = key,

		load_timestamp = os.clock(),
		is_mock = is_mock,
		session_token = session_token or "",
		load_index = raw_data.MetaData and raw_data.MetaData.SessionLoadCount or 0,
		locked_global_updates = {},
		received_global_updates = received_global_updates,
		message_handlers = {},
		global_updates = global_updates,
	}
	setmetatable(self, Profile)

	return self
end

function Profile:IsActive()
	return ActiveSessionCheck[self.session_token] == self
end

function Profile:Reconcile()
	ReconcileTable(self.Data, self.ProfileStore.template)
end

function Profile:EndSession()
	if self:IsActive() == true then
		task.spawn(SaveProfileAsync, self, true, nil, "Manual")
	end
end

function Profile:AddUserId(user_id)
	if type(user_id) ~= "number" or user_id % 1 ~= 0 then
		warn(
			`[{script.Name}]: Invalid UserId argument for :AddUserId() ({tostring(user_id)}); Traceback:\n`
				.. debug.traceback()
		)
		return
	end

	if user_id < 0 and self.is_mock ~= true and DataStoreState == "Access" then
		return
	end

	if table.find(self.UserIds, user_id) == nil then
		table.insert(self.UserIds, user_id)
	end
end

function Profile:RemoveUserId(user_id)
	if type(user_id) ~= "number" or user_id % 1 ~= 0 then
		warn(
			`[{script.Name}]: Invalid UserId argument for :RemoveUserId() ({tostring(user_id)}); Traceback:\n`
				.. debug.traceback()
		)
		return
	end

	local index = table.find(self.UserIds, user_id)

	if index ~= nil then
		table.remove(self.UserIds, index)
	end
end

function Profile:SetAsync()
	if self.view_mode ~= true then
		error(`[{script.Name}]: :SetAsync() can only be used in view mode`)
	end

	SaveProfileAsync(self, nil, true)
end

function Profile:MessageHandler(fn)
	if type(fn) ~= "function" then
		error(`[{script.Name}]: fn argument is not a function`)
	end

	if self.view_mode ~= true and self:IsActive() ~= true then
		return
	end

	local locked_updates = self.locked_global_updates
	table.insert(self.message_handlers, fn)

	for _, update in ipairs(self.global_updates) do
		local index = update[1]
		local update_data = update[#update]

		if locked_updates[index] ~= true then
			local processed_callback = function()
				locked_updates[index] = true
			end

			local send_update_data = DeepCopyTable(update_data)

			task.spawn(fn, send_update_data, processed_callback)
		end
	end
end

function Profile:Save()
	if self.view_mode == true then
		error(`[{script.Name}]: Can't save profile in view mode; Should you be calling :SetAsync() instead?`)
	end

	if self:IsActive() == false then
		warn(
			`[{script.Name}]: Attempted saving an inactive profile (STORE:{self.ProfileStore.Name}; KEY:{self.Key});`
				.. ` Traceback:\n`
				.. debug.traceback()
		)
		return
	end

	RemoveProfileFromAutoSave(self)
	AddProfileToAutoSave(self)

	task.spawn(SaveProfileAsync, self)
end

local ProfileStore: ProfileStoreModule = {

	IsClosing = false,
	IsCriticalState = false,
	OnError = OnError,
	OnOverwrite = OnOverwrite,
	OnCriticalToggle = Signal.New(),
	DataStoreState = "NotReady",
}
ProfileStore.__index = ProfileStore

function ProfileStore.SetConstant(name, value)
	if type(value) ~= "number" then
		error(`[{script.Name}]: Invalid value type`)
	end

	if name == "AUTO_SAVE_PERIOD" then
		AUTO_SAVE_PERIOD = value
	elseif name == "LOAD_REPEAT_PERIOD" then
		LOAD_REPEAT_PERIOD = value
	elseif name == "FIRST_LOAD_REPEAT" then
		FIRST_LOAD_REPEAT = value
	elseif name == "SESSION_STEAL" then
		SESSION_STEAL = value
	elseif name == "ASSUME_DEAD" then
		ASSUME_DEAD = value
	elseif name == "START_SESSION_TIMEOUT" then
		START_SESSION_TIMEOUT = value
	elseif name == "CRITICAL_STATE_ERROR_COUNT" then
		CRITICAL_STATE_ERROR_COUNT = value
	elseif name == "CRITICAL_STATE_ERROR_EXPIRE" then
		CRITICAL_STATE_ERROR_EXPIRE = value
	elseif name == "CRITICAL_STATE_EXPIRE" then
		CRITICAL_STATE_EXPIRE = value
	elseif name == "MAX_MESSAGE_QUEUE" then
		MAX_MESSAGE_QUEUE = value
	else
		error(`[{script.Name}]: Invalid constant name was provided`)
	end
end

function ProfileStore.Test()
	return {
		ActiveSessionCheck = ActiveSessionCheck,
		AutoSaveList = AutoSaveList,
		ActiveProfileLoadJobs = ActiveProfileLoadJobs,
		ActiveProfileSaveJobs = ActiveProfileSaveJobs,
		MockStore = MockStore,
		UserMockStore = UserMockStore,
		UpdateQueue = UpdateQueue,
	}
end

function ProfileStore.New(store_name, template)
	template = template or {}

	if type(store_name) ~= "string" then
		error(`[{script.Name}]: Invalid or missing "store_name"`)
	elseif string.len(store_name) == 0 then
		error(`[{script.Name}]: store_name cannot be an empty string`)
	elseif string.len(store_name) > 50 then
		error(`[{script.Name}]: store_name is too long`)
	end

	if type(template) ~= "table" then
		error(`[{script.Name}]: Invalid template argument`)
	end

	local self
	self = {

		Mock = {

			Name = store_name,

			StartSessionAsync = function(_, profile_key)
				MockFlag = true
				return self:StartSessionAsync(profile_key)
			end,
			MessageAsync = function(_, profile_key, message)
				MockFlag = true
				return self:MessageAsync(profile_key, message)
			end,
			GetAsync = function(_, profile_key, version)
				MockFlag = true
				return self:GetAsync(profile_key, version)
			end,
			VersionQuery = function(_, profile_key, sort_direction, min_date, max_date)
				MockFlag = true
				return self:VersionQuery(profile_key, sort_direction, min_date, max_date)
			end,
			RemoveAsync = function(_, profile_key)
				MockFlag = true
				return self:RemoveAsync(profile_key)
			end,
		},

		Name = store_name,

		template = template,
		data_store = nil,
		load_jobs = {},
		mock_load_jobs = {},
		is_ready = true,
	}
	setmetatable(self, ProfileStore)

	local options = Instance.new("DataStoreOptions")
	options:SetExperimentalFeatures({ v2 = true })

	if DataStoreState == "NotReady" then
		self.is_ready = false

		task.spawn(function()
			repeat
				task.wait()
			until DataStoreState ~= "NotReady"

			if DataStoreState == "Access" then
				self.data_store = DataStoreService:GetDataStore(store_name, nil, options)
			end

			self.is_ready = true
		end)
	elseif DataStoreState == "Access" then
		self.data_store = DataStoreService:GetDataStore(store_name, nil, options)
	end

	return self
end

function ProfileStore:StartSessionAsync(profile_key, params)
	local is_mock = ReadMockFlag()

	if type(profile_key) ~= "string" then
		error(`[{script.Name}]: profile_key must be a string`)
	elseif string.len(profile_key) == 0 then
		error(`[{script.Name}]: Invalid profile_key`)
	elseif string.len(profile_key) > 50 then
		error(`[{script.Name}]: profile_key is too long`)
	end

	if params ~= nil and type(params) ~= "table" then
		error(`[{script.Name}]: Invalid params`)
	end

	params = params or {}

	if ProfileStore.IsClosing == true then
		return nil
	end

	WaitForStoreReady(self)

	local session_token = SessionToken(self.Name, profile_key, is_mock)

	if ActiveSessionCheck[session_token] ~= nil then
		error(`[{script.Name}]: Profile (STORE:{self.Name}; KEY:{profile_key}) is already loaded in this session`)
	end

	ActiveProfileLoadJobs = ActiveProfileLoadJobs + 1

	local is_user_cancel = false

	local function cancel_condition()
		if is_user_cancel == false then
			if params.Cancel ~= nil then
				is_user_cancel = params.Cancel() == true
			end
			return is_user_cancel
		end
		return true
	end

	local user_steal = params.Steal == true

	local force_load_steps = 0
	local request_force_load = true
	local steal_session = false

	local start = os.clock()
	local exp_backoff = 1

	while ProfileStore.IsClosing == false and cancel_condition() == false do
		LoadIndex += 1
		local load_id = LoadIndex
		local profile_load_jobs = is_mock == true and self.mock_load_jobs or self.load_jobs
		local profile_load_job = profile_load_jobs[profile_key]

		local loaded_data, key_info
		local unique_session_id = HttpService:GenerateGUID(false)

		if profile_load_job ~= nil then
			profile_load_job[1] = load_id
			while profile_load_job[2] == nil do
				task.wait()
			end
			if profile_load_job[1] == load_id then
				loaded_data, key_info = table.unpack(profile_load_job[2])
				profile_load_jobs[profile_key] = nil
			else
				ActiveProfileLoadJobs = ActiveProfileLoadJobs - 1
				return nil
			end
		else
			profile_load_job = { load_id, nil }
			profile_load_jobs[profile_key] = profile_load_job

			profile_load_job[2] = table.pack(UpdateAsync(self, profile_key, {
				ExistingProfileHandle = function(latest_data)
					if ProfileStore.IsClosing == true or cancel_condition() == true then
						return
					end

					local active_session = latest_data.MetaData.ActiveSession
					local force_load_session = latest_data.MetaData.ForceLoadSession

					if active_session == nil then
						latest_data.MetaData.ActiveSession = { PlaceId, JobId, unique_session_id }
						latest_data.MetaData.ForceLoadSession = nil
					elseif type(active_session) == "table" then
						if IsThisSession(active_session) == false then
							local last_update = latest_data.MetaData.LastUpdate
							if last_update ~= nil then
								if os.time() - last_update > ASSUME_DEAD then
									latest_data.MetaData.ActiveSession = { PlaceId, JobId, unique_session_id }
									latest_data.MetaData.ForceLoadSession = nil
									return
								end
							end
							if steal_session == true or user_steal == true then
								local force_load_interrupted = if force_load_session ~= nil
									then not IsThisSession(force_load_session)
									else true
								if force_load_interrupted == false or user_steal == true then
									latest_data.MetaData.ActiveSession = { PlaceId, JobId, unique_session_id }
									latest_data.MetaData.ForceLoadSession = nil
								end
							elseif request_force_load == true then
								latest_data.MetaData.ForceLoadSession = { PlaceId, JobId }
							end
						else
							latest_data.MetaData.ForceLoadSession = nil
						end
					end
				end,
				MissingProfileHandle = function(latest_data)
					local is_cancel = ProfileStore.IsClosing == true or cancel_condition() == true

					latest_data.Data = DeepCopyTable(self.template)
					latest_data.MetaData = {
						ProfileCreateTime = os.time(),
						SessionLoadCount = 0,
						ActiveSession = if is_cancel == false then { PlaceId, JobId, unique_session_id } else nil,
						ForceLoadSession = nil,
						MetaTags = {},
					}
				end,
				EditProfile = function(latest_data)
					if ProfileStore.IsClosing == true or cancel_condition() == true then
						return
					end

					local active_session = latest_data.MetaData.ActiveSession
					if active_session ~= nil and IsThisSession(active_session) == true then
						latest_data.MetaData.SessionLoadCount = latest_data.MetaData.SessionLoadCount + 1
						latest_data.MetaData.LastUpdate = os.time()
					end
				end,
			}, is_mock))
			if profile_load_job[1] == load_id then
				loaded_data, key_info = table.unpack(profile_load_job[2])
				profile_load_jobs[profile_key] = nil
			else
				ActiveProfileLoadJobs = ActiveProfileLoadJobs - 1
				return nil
			end
		end

		if loaded_data ~= nil and key_info ~= nil then
			local active_session = loaded_data.MetaData.ActiveSession
			if type(active_session) == "table" then
				if IsThisSession(active_session) == true then
					local profile = Profile.New(loaded_data, key_info, self, profile_key, is_mock, session_token)
					AddProfileToAutoSave(profile)

					if is_mock ~= true and DataStoreState == "Access" then
						local last_roblox_message = 0

						profile.roblox_message_subscription = MessagingService:SubscribeAsync(
							"PS_" .. unique_session_id,
							function(message)
								if
									type(message.Data) == "table"
									and message.Data.LoadCount == profile.SessionLoadCount
								then
									if os.clock() - last_roblox_message > 6 then
										last_roblox_message = os.clock()
										if profile:IsActive() == true then
											if message.Data.EndSession == true then
												SaveProfileAsync(profile, true, false, "External")
											else
												profile:Save()
											end
										end
									end
								end
							end
						)
					end

					if ProfileStore.IsClosing == true or cancel_condition() == true then
						SaveProfileAsync(profile, true)
						profile = nil
					end

					ActiveProfileLoadJobs = ActiveProfileLoadJobs - 1
					return profile
				else
					if ProfileStore.IsClosing == true or cancel_condition() == true then
						ActiveProfileLoadJobs = ActiveProfileLoadJobs - 1
						return nil
					end

					local force_load_session = loaded_data.MetaData.ForceLoadSession
					local force_load_interrupted = if force_load_session ~= nil
						then not IsThisSession(force_load_session)
						else true

					if force_load_interrupted == false then
						if request_force_load == false then
							force_load_steps = force_load_steps + 1
							if force_load_steps >= math.ceil(SESSION_STEAL / LOAD_REPEAT_PERIOD) then
								steal_session = true
							end
						end

						if type(active_session[3]) == "string" then
							local session_load_count = loaded_data.MetaData.SessionLoadCount or 0
							MessagingService:PublishAsync(
								"PS_" .. active_session[3],
								{ LoadCount = session_load_count, EndSession = true }
							)
						end

						local wait_until = os.clock()
							+ if request_force_load == true then FIRST_LOAD_REPEAT else LOAD_REPEAT_PERIOD
						repeat
							task.wait()
						until os.clock() >= wait_until or ProfileStore.IsClosing == true
					else
						ActiveProfileLoadJobs = ActiveProfileLoadJobs - 1
						return nil
					end

					request_force_load = false
				end
			else
				ActiveProfileLoadJobs = ActiveProfileLoadJobs - 1
				return nil
			end
		else
			local default_timeout = false

			if params.Cancel == nil then
				default_timeout = os.clock() - start >= START_SESSION_TIMEOUT
			end

			if default_timeout == true or ProfileStore.IsClosing == true or cancel_condition() == true then
				ActiveProfileLoadJobs = ActiveProfileLoadJobs - 1
				return nil
			end

			task.wait(exp_backoff)
			exp_backoff = math.min(20, exp_backoff * 2)
		end
	end

	ActiveProfileLoadJobs = ActiveProfileLoadJobs - 1
	return nil
end

function ProfileStore:MessageAsync(profile_key, message)
	local is_mock = ReadMockFlag()

	if type(profile_key) ~= "string" then
		error(`[{script.Name}]: profile_key must be a string`)
	elseif string.len(profile_key) == 0 then
		error(`[{script.Name}]: Invalid profile_key`)
	elseif string.len(profile_key) > 50 then
		error(`[{script.Name}]: profile_key is too long`)
	end

	if type(message) ~= "table" then
		error(`[{script.Name}]: message must be a table`)
	end

	if ProfileStore.IsClosing == true then
		return false
	end

	WaitForStoreReady(self)

	local exp_backoff = 1

	while ProfileStore.IsClosing == false do
		local loaded_data = UpdateAsync(self, profile_key, {
			ExistingProfileHandle = nil,
			MissingProfileHandle = nil,
			EditProfile = function(latest_data)
				local global_updates = latest_data.GlobalUpdates
				local update_list = global_updates[2]

				global_updates[1] += 1
				table.insert(update_list, { global_updates[1], message })

				while #update_list > MAX_MESSAGE_QUEUE do
					table.remove(update_list, 1)
				end
			end,
		}, is_mock)

		if loaded_data ~= nil then
			local session_token = SessionToken(self.Name, profile_key, is_mock)

			local profile = ActiveSessionCheck[session_token]

			if profile ~= nil then
				profile:Save()
			else
				local meta_data = loaded_data.MetaData or {}
				local active_session = meta_data.ActiveSession
				local session_load_count = meta_data.SessionLoadCount or 0

				if type(active_session) == "table" and type(active_session[3]) == "string" then
					MessagingService:PublishAsync("PS_" .. active_session[3], { LoadCount = session_load_count })
				end
			end

			return true
		else
			task.wait(exp_backoff)
			exp_backoff = math.min(20, exp_backoff * 2)
		end
	end

	return false
end

function ProfileStore:GetAsync(profile_key, version)
	local is_mock = ReadMockFlag()

	if type(profile_key) ~= "string" then
		error(`[{script.Name}]: profile_key must be a string`)
	elseif string.len(profile_key) == 0 then
		error(`[{script.Name}]: Invalid profile_key`)
	elseif string.len(profile_key) > 50 then
		error(`[{script.Name}]: profile_key is too long`)
	end

	if ProfileStore.IsClosing == true then
		return nil
	end

	WaitForStoreReady(self)

	if version ~= nil and (is_mock or DataStoreState ~= "Access") then
		return nil
	end

	local exp_backoff = 1

	while ProfileStore.IsClosing == false do
		local loaded_data, key_info = UpdateAsync(self, profile_key, {
			ExistingProfileHandle = nil,
			MissingProfileHandle = function(latest_data)
				latest_data.Data = DeepCopyTable(self.template)
				latest_data.MetaData = {
					ProfileCreateTime = os.time(),
					SessionLoadCount = 0,
					ActiveSession = nil,
					ForceLoadSession = nil,
					MetaTags = {},
				}
			end,
			EditProfile = nil,
		}, is_mock, true, version)

		if loaded_data ~= nil then
			if key_info == nil then
				return nil
			end

			local profile = Profile.New(loaded_data, key_info, self, profile_key, is_mock)
			profile.view_mode = true

			return profile
		else
			task.wait(exp_backoff)
			exp_backoff = math.min(20, exp_backoff * 2)
		end
	end

	return nil
end

function ProfileStore:RemoveAsync(profile_key)
	local is_mock = ReadMockFlag()

	if type(profile_key) ~= "string" or string.len(profile_key) == 0 then
		error(`[{script.Name}]: Invalid profile_key`)
	end

	if ProfileStore.IsClosing == true then
		return false
	end

	WaitForStoreReady(self)

	local wipe_status = false

	local next_in_queue = WaitInUpdateQueue(SessionToken(self.Name, profile_key, is_mock))

	if is_mock == true then
		local mock_data_store = UserMockStore[self.Name]

		if mock_data_store ~= nil then
			mock_data_store[profile_key] = nil
			if next(mock_data_store) == nil then
				UserMockStore[self.Name] = nil
			end
		end

		wipe_status = true
		task.wait()
	elseif DataStoreState ~= "Access" then
		local mock_data_store = MockStore[self.Name]

		if mock_data_store ~= nil then
			mock_data_store[profile_key] = nil
			if next(mock_data_store) == nil then
				MockStore[self.Name] = nil
			end
		end

		wipe_status = true
		task.wait()
	else
		wipe_status = pcall(function()
			self.data_store:RemoveAsync(profile_key)
		end)
	end

	next_in_queue()

	return wipe_status
end

local ProfileVersionQuery = {}
ProfileVersionQuery.__index = ProfileVersionQuery

function ProfileVersionQuery.New(profile_store, profile_key, sort_direction, min_date, max_date, is_mock)
	local self = {
		profile_store = profile_store,
		profile_key = profile_key,
		sort_direction = sort_direction,
		min_date = min_date,
		max_date = max_date,

		query_pages = nil,
		query_index = 0,
		query_failure = false,

		is_query_yielded = false,
		query_queue = {},

		is_mock = is_mock,
	}
	setmetatable(self, ProfileVersionQuery)

	return self
end

function MoveVersionQueryQueue(self)
	while #self.query_queue > 0 do
		local queue_entry = table.remove(self.query_queue, 1)

		task.spawn(queue_entry)

		if self.is_query_yielded == true then
			break
		end
	end
end

local VersionQueryNextAsyncStackingFlag = false
local WarnAboutVersionQueryOnce = false

function ProfileVersionQuery:NextAsync()
	local is_stacking = VersionQueryNextAsyncStackingFlag == true
	VersionQueryNextAsyncStackingFlag = false

	WaitForStoreReady(self.profile_store)

	if ProfileStore.IsClosing == true then
		return nil
	end

	if self.is_mock == true or DataStoreState ~= "Access" then
		if IsStudio == true and WarnAboutVersionQueryOnce == false then
			WarnAboutVersionQueryOnce = true
			warn(`[{script.Name}]: :VersionQuery() is not supported in mock mode!`)
		end
		return nil
	end

	local profile
	local is_finished = false

	local function query_job()
		if self.query_failure == true then
			is_finished = true
			return
		end

		if self.query_pages == nil then
			self.is_query_yielded = true

			task.spawn(function()
				VersionQueryNextAsyncStackingFlag = true
				profile = self:NextAsync()
				is_finished = true
			end)

			local list_success, error_message = pcall(function()
				self.query_pages = self.profile_store.data_store:ListVersionsAsync(
					self.profile_key,
					self.sort_direction,
					self.min_date,
					self.max_date
				)
				self.query_index = 0
			end)

			if list_success == false or self.query_pages == nil then
				warn(`[{script.Name}]: Version query fail - {tostring(error_message)}`)
				self.query_failure = true
			end

			self.is_query_yielded = false

			MoveVersionQueryQueue(self)

			return
		end

		local current_page = self.query_pages:GetCurrentPage()
		local next_item = current_page[self.query_index + 1]

		if self.query_pages.IsFinished == true and next_item == nil then
			is_finished = true
			return
		end

		if next_item == nil then
			self.is_query_yielded = true
			task.spawn(function()
				VersionQueryNextAsyncStackingFlag = true
				profile = self:NextAsync()
				is_finished = true
			end)

			local success, error_message = pcall(function()
				self.query_pages:AdvanceToNextPageAsync()
				self.query_index = 0
			end)

			if success == false or #self.query_pages:GetCurrentPage() == 0 then
				self.query_failure = true
			end

			self.is_query_yielded = false
			MoveVersionQueryQueue(self)

			return
		end

		self.query_index += 1
		profile = self.profile_store:GetAsync(self.profile_key, next_item.Version)
		is_finished = true
	end

	if self.is_query_yielded == false then
		query_job()
	else
		if is_stacking == true then
			table.insert(self.query_queue, 1, query_job)
		else
			table.insert(self.query_queue, query_job)
		end
	end

	while is_finished == false do
		task.wait()
	end

	return profile
end

function ProfileStore:VersionQuery(profile_key, sort_direction, min_date, max_date)
	local is_mock = ReadMockFlag()

	if type(profile_key) ~= "string" or string.len(profile_key) == 0 then
		error(`[{script.Name}]: Invalid profile_key`)
	end

	if
		sort_direction ~= nil
		and (typeof(sort_direction) ~= "EnumItem" or sort_direction.EnumType ~= Enum.SortDirection)
	then
		error(`[{script.Name}]: Invalid sort_direction ({tostring(sort_direction)})`)
	end

	if min_date ~= nil and typeof(min_date) ~= "DateTime" and typeof(min_date) ~= "number" then
		error(`[{script.Name}]: Invalid min_date ({tostring(min_date)})`)
	end

	if max_date ~= nil and typeof(max_date) ~= "DateTime" and typeof(max_date) ~= "number" then
		error(`[{script.Name}]: Invalid max_date ({tostring(max_date)})`)
	end

	min_date = typeof(min_date) == "DateTime" and min_date.UnixTimestampMillis or min_date
	max_date = typeof(max_date) == "DateTime" and max_date.UnixTimestampMillis or max_date

	return ProfileVersionQuery.New(self, profile_key, sort_direction, min_date, max_date, is_mock)
end

if IsStudio == true then
	task.spawn(function()
		local new_state = "NoAccess"

		local status, message = pcall(function()
			DataStoreService:GetDataStore("____PS"):SetAsync("____PS", os.time())
		end)

		local no_internet_access = status == false and string.find(message, "ConnectFail", 1, true) ~= nil

		if no_internet_access == true then
			warn(`[{script.Name}]: No internet access - check your network connection`)
		end

		if
			status == false
			and (
				string.find(message, "403", 1, true) ~= nil
				or string.find(message, "must publish", 1, true) ~= nil
				or no_internet_access == true
			)
		then
			new_state = if no_internet_access == true then "NoInternet" else "NoAccess"
			print(`[{script.Name}]: Roblox API services unavailable - data will not be saved`)
		else
			new_state = "Access"
			print(`[{script.Name}]: Roblox API services available - data will be saved`)
		end

		DataStoreState = new_state
		ProfileStore.DataStoreState = new_state
	end)
else
	DataStoreState = "Access"
	ProfileStore.DataStoreState = "Access"
end

RunService.Heartbeat:Connect(function()
	local auto_save_list_length = #AutoSaveList
	if auto_save_list_length > 0 then
		local auto_save_index_speed = AUTO_SAVE_PERIOD / auto_save_list_length
		local os_clock = os.clock()
		while os_clock - LastAutoSave > auto_save_index_speed do
			LastAutoSave = LastAutoSave + auto_save_index_speed
			local profile = AutoSaveList[AutoSaveIndex]
			if os_clock - profile.load_timestamp < AUTO_SAVE_PERIOD / 2 then
				profile = nil
				for _ = 1, auto_save_list_length - 1 do
					AutoSaveIndex = AutoSaveIndex + 1
					if AutoSaveIndex > auto_save_list_length then
						AutoSaveIndex = 1
					end
					profile = AutoSaveList[AutoSaveIndex]
					if os_clock - profile.load_timestamp >= AUTO_SAVE_PERIOD / 2 then
						break
					else
						profile = nil
					end
				end
			end

			AutoSaveIndex = AutoSaveIndex + 1
			if AutoSaveIndex > auto_save_list_length then
				AutoSaveIndex = 1
			end

			if profile ~= nil then
				task.spawn(SaveProfileAsync, profile)
			end
		end
	end

	if ProfileStore.IsCriticalState == false then
		if #IssueQueue >= CRITICAL_STATE_ERROR_COUNT then
			ProfileStore.IsCriticalState = true
			ProfileStore.OnCriticalToggle:Fire(true)
			CriticalStateStart = os.clock()
			warn(`[{script.Name}]: Entered critical state`)
		end
	else
		if #IssueQueue >= CRITICAL_STATE_ERROR_COUNT then
			CriticalStateStart = os.clock()
		elseif os.clock() - CriticalStateStart > CRITICAL_STATE_EXPIRE then
			ProfileStore.IsCriticalState = false
			ProfileStore.OnCriticalToggle:Fire(false)
			warn(`[{script.Name}]: Critical state ended`)
		end
	end

	while true do
		local issue_time = IssueQueue[1]
		if issue_time == nil then
			break
		elseif os.clock() - issue_time > CRITICAL_STATE_ERROR_EXPIRE then
			table.remove(IssueQueue, 1)
		else
			break
		end
	end
end)

task.spawn(function()
	while DataStoreState == "NotReady" do
		task.wait()
	end

	if DataStoreState ~= "Access" then
		game:BindToClose(function()
			ProfileStore.IsClosing = true
			task.wait()
		end)

		return
	end

	game:BindToClose(function()
		ProfileStore.IsClosing = true

		local on_close_save_job_count = 0
		local active_profiles = {}
		for index, profile in ipairs(AutoSaveList) do
			active_profiles[index] = profile
		end

		for _, profile in ipairs(active_profiles) do
			if profile:IsActive() == true then
				on_close_save_job_count = on_close_save_job_count + 1
				task.spawn(function()
					SaveProfileAsync(profile, true, nil, "Shutdown")
					on_close_save_job_count = on_close_save_job_count - 1
				end)
			end
		end

		while on_close_save_job_count > 0 or ActiveProfileLoadJobs > 0 or ActiveProfileSaveJobs > 0 do
			task.wait()
		end

		return
	end)
end)

return ProfileStore
