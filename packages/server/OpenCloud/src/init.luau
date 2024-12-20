local module = {}

module.proto = {}

local base64 = require(script.proto.base64)
module.proto.encode = base64.encode
module.proto.decode = base64.decode

local wktJson = require(script.proto.wktJson)
export type proto_WellKnownType = wktJson.WellKnownType
module.proto.Duration = wktJson.Duration
module.proto.Timestamp = wktJson.Timestamp
module.proto.BoolValue = wktJson.BoolValue
module.proto.BytesValue = wktJson.BytesValue
module.proto.DoubleValue = wktJson.DoubleValue
module.proto.FloatValue = wktJson.FloatValue
module.proto.Int32Value = wktJson.Int32Value
module.proto.Int64Value = wktJson.Int64Value
module.proto.UInt32Value = wktJson.UInt32Value
module.proto.UInt64Value = wktJson.UInt64Value
module.proto.StringValue = wktJson.StringValue
module.proto.NullValue = wktJson.NullValue
module.proto.ListValue = wktJson.ListValue
module.proto.Struct = wktJson.Struct
module.proto.Value = wktJson.Value
module.proto.Struct = wktJson.Struct
module.proto.ListValue = wktJson.ListValue

local translate_text__custom_method =
	require(script.roblox.open_cloud.cloud.v2.custom_methods.universe.translate_text__custom_method)
export type TranslateTextRequest = translate_text__custom_method.TranslateTextRequest
export type TranslateTextResponse = translate_text__custom_method.TranslateTextResponse
export type TranslateTextResponse_TranslationsEntry = translate_text__custom_method.TranslateTextResponse_TranslationsEntry
module.TranslateTextRequest = translate_text__custom_method.TranslateTextRequest
module.TranslateTextResponse = translate_text__custom_method.TranslateTextResponse

local proto = require(script.proto)
export type proto_Message = proto.Message
export type proto_Enum = proto.Enum
module.proto.readVarInt = proto.readVarInt
module.proto.readFloat = proto.readFloat
module.proto.readDouble = proto.readDouble
module.proto.readFixed32 = proto.readFixed32
module.proto.readSignedFixed32 = proto.readSignedFixed32
module.proto.readFixed64 = proto.readFixed64
module.proto.readSignedFixed64 = proto.readSignedFixed64
module.proto.readTag = proto.readTag
module.proto.readBuffer = proto.readBuffer
module.proto.wireTypes = proto.wireTypes
module.proto.writeVarInt = proto.writeVarInt
module.proto.writeFloat = proto.writeFloat
module.proto.writeDouble = proto.writeDouble
module.proto.writeFixed32 = proto.writeFixed32
module.proto.writeSignedFixed32 = proto.writeSignedFixed32
module.proto.writeFixed64 = proto.writeFixed64
module.proto.writeSignedFixed64 = proto.writeSignedFixed64
module.proto.writeTag = proto.writeTag
module.proto.writeBuffer = proto.writeBuffer
module.proto.writeString = proto.writeString
module.proto.decodeZigZag = proto.decodeZigZag
module.proto.encodeZigZag = proto.encodeZigZag
module.proto.limitInt32 = proto.limitInt32
module.proto.json = proto.json

local OpenCloudService = game:GetService("OpenCloudService")
local HttpService = game:GetService("HttpService")

export type Result<T> = {
	ResponseCode: number?,
	Response: T?,
	Error: Error?,
}

module.ResponseCode = {
	[100] = "Continue",
	[101] = "Switching Protocols",
	[200] = "OK",
	[201] = "Created",
	[202] = "Accepted",
	[203] = "Non-Authoritative Information",
	[204] = "No Content",
	[205] = "Reset Content",
	[206] = "Partial Content",
	[300] = "Multiple Choices",
	[301] = "Moved Permanently",
	[302] = "Found",
	[303] = "See Other",
	[304] = "Not Modified",
	[307] = "Temporary Redirect",
	[308] = "Permanent Redirect",
	[400] = "Bad Request",
	[401] = "Unauthorized",
	[402] = "Payment Required",
	[403] = "Forbidden",
	[404] = "Not Found",
	[405] = "Method Not Allowed",
	[406] = "Not Acceptable",
	[407] = "Proxy Authentication Required",
	[408] = "Request Timeout",
	[409] = "Conflict",
	[410] = "Gone",
	[411] = "Length Required",
	[412] = "Precondition Failed",
	[413] = "Payload Too Large",
	[414] = "URI Too Long",
	[415] = "Unsupported Media Type",
	[416] = "Range Not Satisfiable",
	[417] = "Expectation Failed",
	[421] = "Misdirected Request",
	[422] = "Unprocessable Content",
	[426] = "Upgrade Required",
	[428] = "Precondition Required",
	[429] = "Too Many Requests",
	[431] = "Request Header Fields Too Large",
	[500] = "Internal Server Error",
	[501] = "Not Implemented",
	[502] = "Bad Gateway",
	[503] = "Service Unavailable",
	[504] = "Gateway Timeout",
	[505] = "HTTP Version Not Supported",
	[511] = "Network Authentication Required",
}

export type Error = {
	code: string?,
	message: string?,
	details: { Any }?,
}

export type CallOptions = {
	MaxRetries: number?,
	RetryDelaySeconds: number?,
	RetryDelayMultiplier: number?,
}

function ExecuteOpenCloudRequest<Input, Output>(
	version: string,
	methodName: string,
	request: Input,
	requestProtoMessage: proto_Message<Input>,
	responseProtoMessage: proto_Message<Output>,
	options: CallOptions?,
	callback: ((Result<Output>) -> nil)?
): Result<Output>?
	local notLoadedStr = "Open Cloud not loaded."

	local maxRetries = 5
	local retryDelaySeconds = 0.5
	local retryDelayMultiplier = 1.3

	if options ~= nil and options.MaxRetries ~= nil then
		maxRetries = options.MaxRetries
	end

	if options ~= nil and options.RetryDelaySeconds ~= nil then
		retryDelaySeconds = options.RetryDelaySeconds
	end

	if options ~= nil and options.retryDelayMultiplier ~= nil then
		retryDelayMultiplier = options.RetryDelayMultiplier
	end

	local success
	local response

	local retryCount = 0

	while retryCount < maxRetries do
		success, response = pcall(function()
			return OpenCloudService:InvokeAsync(version, methodName, requestProtoMessage.jsonEncode(request))
		end)

		if not success and response == notLoadedStr then
			wait(retryDelaySeconds * retryDelayMultiplier ^ retryCount)
			retryCount += 1
		else
			break
		end
	end

	local result

	if not success or typeof(response) == "string" then
		result = {
			["Response"] = nil,
			["ResponseCode"] = 500,
			["Error"] = {
				["code"] = "UNEXPECTED_ERROR",
				["message"] = response,
			},
		}
	elseif response["StatusCode"] == 200 then
		result = {
			["Response"] = responseProtoMessage.jsonDecode(HttpService:JSONDecode(response["Body"])),
			["ResponseCode"] = 200,
			["Error"] = nil,
		}
	else
		print(response["Body"])

		local success, bodyJson = pcall(function()
			return HttpService:JSONDecode(response["Body"])
		end)

		if not success then
			bodyJson = {
				["code"] = "UNEXPECTED_ERROR",
				["message"] = response["Body"],
			}
		end

		result = {
			["Response"] = nil,
			["ResponseCode"] = response["StatusCode"],
			["Error"] = bodyJson,
		}
	end

	if callback ~= nil then
		callback(result)
	else
		return result
	end
end

function module:TranslateText(
	request: TranslateTextRequest,
	options: CallOptions?,
	callback: ((Result<TranslateTextResponse>) -> nil)?
): Result<TranslateTextResponse>?
	return ExecuteOpenCloudRequest(
		"v2",
		"TranslateText",
		request,
		module.TranslateTextRequest,
		module.TranslateTextResponse,
		options,
		callback
	)
end

function module:UniversePath(universe: string): string
	return `universes/{universe}`
end

export type UniversePath = {
	Universe: string,
}

function module:ParseUniversePath(universePath: string): UniversePath
	local pattern = "^universes/([^/]+)$"

	local universe = string.match(universePath, pattern)

	return {
		Universe = universe,
	}
end

return module
