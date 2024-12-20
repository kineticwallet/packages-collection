local proto = require(script.Parent.Parent.Parent.Parent.Parent.Parent.Parent.proto)

local TranslateTextRequest: proto.Message<TranslateTextRequest>
export type TranslateTextRequest = {
	path: string,
	text: string,
	source_language_code: string,
	target_language_codes: { string },
}

local TranslateTextResponse: proto.Message<TranslateTextResponse>
export type TranslateTextResponse = {
	source_language_code: string,
	translations: { [string]: string },
}

local TranslateTextResponse_TranslationsEntry: proto.Message<TranslateTextResponse_TranslationsEntry>
export type TranslateTextResponse_TranslationsEntry = {
	key: string,
	value: string,
}

TranslateTextRequest = {
	new = function()
		return {
			path = "",
			text = "",
			source_language_code = "",
			target_language_codes = {},
		}
	end,

	encode = function(self: TranslateTextRequest): buffer
		local output = buffer.create(0)
		local cursor = 0

		if self.path ~= "" then
			output, cursor = proto.writeTag(output, cursor, 1, proto.wireTypes.lengthDelimited)
			output, cursor = proto.writeString(output, cursor, self.path)
		end

		if self.text ~= "" then
			output, cursor = proto.writeTag(output, cursor, 2, proto.wireTypes.lengthDelimited)
			output, cursor = proto.writeString(output, cursor, self.text)
		end

		if self.source_language_code ~= "" then
			output, cursor = proto.writeTag(output, cursor, 3, proto.wireTypes.lengthDelimited)
			output, cursor = proto.writeString(output, cursor, self.source_language_code)
		end

		if #self.target_language_codes > 0 then
			for _, value: string in self.target_language_codes do
				output, cursor = proto.writeTag(output, cursor, 4, proto.wireTypes.lengthDelimited)
				output, cursor = proto.writeString(output, cursor, value)
			end
		end

		local shrunkBuffer = buffer.create(cursor)
		buffer.copy(shrunkBuffer, 0, output, 0, cursor)
		return shrunkBuffer
	end,

	decode = function(input: buffer): TranslateTextRequest
		local self = TranslateTextRequest.new()
		local cursor = 0

		while cursor < buffer.len(input) do
			local field, wireType
			field, wireType, cursor = proto.readTag(input, cursor)

			if wireType == proto.wireTypes.varint then
			elseif wireType == proto.wireTypes.lengthDelimited then
				if field == 1 then
					local value
					value, cursor = proto.readBuffer(input, cursor)
					self.path = buffer.tostring(value)
				elseif field == 2 then
					local value
					value, cursor = proto.readBuffer(input, cursor)
					self.text = buffer.tostring(value)
				elseif field == 3 then
					local value
					value, cursor = proto.readBuffer(input, cursor)
					self.source_language_code = buffer.tostring(value)
				elseif field == 4 then
					local value
					value, cursor = proto.readBuffer(input, cursor)
					table.insert(self.target_language_codes, buffer.tostring(value))
				end
			elseif wireType == proto.wireTypes.i32 then
			elseif wireType == proto.wireTypes.i64 then
			else
				error("Unsupported wire type: " .. wireType)
			end
		end

		return self
	end,

	jsonEncode = function(self: TranslateTextRequest): any
		local output: {
			path: string?,
			text: string?,
			sourceLanguageCode: string?,
			targetLanguageCodes: { string }?,
		} =
			{}

		if self.path ~= "" then
			output.path = self.path
		end

		if self.text ~= "" then
			output.text = self.text
		end

		if self.source_language_code ~= "" then
			output.sourceLanguageCode = self.source_language_code
		end

		if #self.target_language_codes > 0 then
			local newOutput: { string } = {}
			for _, value: string in self.target_language_codes do
				table.insert(newOutput, value)
			end
			output.targetLanguageCodes = newOutput
		end

		return output
	end,

	jsonDecode = function(input: { [string]: any }): TranslateTextRequest
		local self = TranslateTextRequest.new()

		if input.path ~= nil then
			self.path = input.path
		end

		if input.text ~= nil then
			self.text = input.text
		end

		if input.source_language_code ~= nil then
			self.source_language_code = input.source_language_code
		end

		if input.sourceLanguageCode ~= nil then
			self.source_language_code = input.sourceLanguageCode
		end

		if input.target_language_codes ~= nil then
			local newOutput: { string } = {}
			for _, value: string in input.target_language_codes do
				table.insert(newOutput, value)
			end

			self.target_language_codes = newOutput
		end

		if input.targetLanguageCodes ~= nil then
			local newOutput: { string } = {}
			for _, value: string in input.targetLanguageCodes do
				table.insert(newOutput, value)
			end

			self.target_language_codes = newOutput
		end

		return self
	end,
}

TranslateTextResponse = {
	new = function()
		return {
			source_language_code = "",
			translations = {},
		}
	end,

	encode = function(self: TranslateTextResponse): buffer
		local output = buffer.create(0)
		local cursor = 0

		if self.source_language_code ~= "" then
			output, cursor = proto.writeTag(output, cursor, 1, proto.wireTypes.lengthDelimited)
			output, cursor = proto.writeString(output, cursor, self.source_language_code)
		end

		if next(self.translations) ~= nil then
			for key: string, value: string in self.translations do
				local mapBuffer = buffer.create(0)
				local mapCursor = 0
				mapBuffer, mapCursor = proto.writeTag(mapBuffer, mapCursor, 1, proto.wireTypes.lengthDelimited)
				mapBuffer, mapCursor = proto.writeString(mapBuffer, mapCursor, key)
				mapBuffer, mapCursor = proto.writeTag(mapBuffer, mapCursor, 2, proto.wireTypes.lengthDelimited)
				mapBuffer, mapCursor = proto.writeString(mapBuffer, mapCursor, value)
				output, cursor = proto.writeTag(output, cursor, 2, proto.wireTypes.lengthDelimited)
				output, cursor = proto.writeBuffer(output, cursor, mapBuffer, mapCursor)
			end
		end

		local shrunkBuffer = buffer.create(cursor)
		buffer.copy(shrunkBuffer, 0, output, 0, cursor)
		return shrunkBuffer
	end,

	decode = function(input: buffer): TranslateTextResponse
		local self = TranslateTextResponse.new()
		local cursor = 0

		while cursor < buffer.len(input) do
			local field, wireType
			field, wireType, cursor = proto.readTag(input, cursor)

			if wireType == proto.wireTypes.varint then
			elseif wireType == proto.wireTypes.lengthDelimited then
				if field == 1 then
					local value
					value, cursor = proto.readBuffer(input, cursor)
					self.source_language_code = buffer.tostring(value)
				elseif field == 2 then
					local value
					value, cursor = proto.readBuffer(input, cursor)

					local mapEntry = TranslateTextResponse_TranslationsEntry.decode(value)

					local keyDefault = ""
					local valueDefault = ""

					self.translations[mapEntry.key or keyDefault] = mapEntry.value or valueDefault
				end
			elseif wireType == proto.wireTypes.i32 then
			elseif wireType == proto.wireTypes.i64 then
			else
				error("Unsupported wire type: " .. wireType)
			end
		end

		return self
	end,

	jsonEncode = function(self: TranslateTextResponse): any
		local output: {
			sourceLanguageCode: string?,
			translations: { [string]: string }?,
		} = {}

		if self.source_language_code ~= "" then
			output.sourceLanguageCode = self.source_language_code
		end

		if next(self.translations) ~= nil then
			local newOutput: { [string]: string } = {}
			for key: string, value: string in self.translations do
				newOutput[key] = value
			end
			output.translations = newOutput
		end

		return output
	end,

	jsonDecode = function(input: { [string]: any }): TranslateTextResponse
		local self = TranslateTextResponse.new()

		if input.source_language_code ~= nil then
			self.source_language_code = input.source_language_code
		end

		if input.sourceLanguageCode ~= nil then
			self.source_language_code = input.sourceLanguageCode
		end

		if input.translations ~= nil then
			local newOutput: { [string]: string } = {}
			for key, value in input.translations do
				newOutput[key] = value
			end

			self.translations = newOutput
		end

		return self
	end,
}

TranslateTextResponse_TranslationsEntry = {
	new = function()
		return {
			key = "",
			value = "",
		}
	end,

	encode = function(self: TranslateTextResponse_TranslationsEntry): buffer
		local output = buffer.create(0)
		local cursor = 0

		if self.key ~= "" then
			output, cursor = proto.writeTag(output, cursor, 1, proto.wireTypes.lengthDelimited)
			output, cursor = proto.writeString(output, cursor, self.key)
		end

		if self.value ~= "" then
			output, cursor = proto.writeTag(output, cursor, 2, proto.wireTypes.lengthDelimited)
			output, cursor = proto.writeString(output, cursor, self.value)
		end

		local shrunkBuffer = buffer.create(cursor)
		buffer.copy(shrunkBuffer, 0, output, 0, cursor)
		return shrunkBuffer
	end,

	decode = function(input: buffer): TranslateTextResponse_TranslationsEntry
		local self = TranslateTextResponse_TranslationsEntry.new()
		local cursor = 0

		while cursor < buffer.len(input) do
			local field, wireType
			field, wireType, cursor = proto.readTag(input, cursor)

			if wireType == proto.wireTypes.varint then
			elseif wireType == proto.wireTypes.lengthDelimited then
				if field == 1 then
					local value
					value, cursor = proto.readBuffer(input, cursor)
					self.key = buffer.tostring(value)
				elseif field == 2 then
					local value
					value, cursor = proto.readBuffer(input, cursor)
					self.value = buffer.tostring(value)
				end
			elseif wireType == proto.wireTypes.i32 then
			elseif wireType == proto.wireTypes.i64 then
			else
				error("Unsupported wire type: " .. wireType)
			end
		end

		return self
	end,

	jsonEncode = function(self: TranslateTextResponse_TranslationsEntry): any
		local output: {
			key: string?,
			value: string?,
		} = {}

		if self.key ~= "" then
			output.key = self.key
		end

		if self.value ~= "" then
			output.value = self.value
		end

		return output
	end,

	jsonDecode = function(input: { [string]: any }): TranslateTextResponse_TranslationsEntry
		local self = TranslateTextResponse_TranslationsEntry.new()

		if input.key ~= nil then
			self.key = input.key
		end

		if input.value ~= nil then
			self.value = input.value
		end

		return self
	end,
}

return {
	TranslateTextRequest = TranslateTextRequest,
	TranslateTextResponse = TranslateTextResponse,
}
