--[[
  This file is part of the plugin Xee.
  https://github.com/vosmont/Vera-Plugin-Xee
  Copyright (c) 2016 Vincent OSMONT
  This code is released under the MIT License, see LICENSE.
--]]

module("L_Xee1", package.seeall)

local json = require("dkjson")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local url = require("socket.url")

-------------------------------------------
-- Plugin constants
-------------------------------------------

_NAME = "Xee"
_DESCRIPTION = "Add your cars in your scenes"
_VERSION = "0.1"

local XEE_CLIENT_ID = "A7V3mOLy8Qm36nncz6Hy"
local XEE_AUTH_URL = "https://cloud.xee.com/v3/auth/auth"
local XEE_API_URL  = "https://cloud.xee.com/v3"
local XEE_REDIRECT_URI = "https://script.google.com/macros/s/AKfycbwMXbU9MFju3-yq8iCNTLds5UqjejeYj4qyyQfyJb4qh5E19KIP/exec"
local XEE_MIN_POLL_INTERVAL = 30
local XEE_MIN_POLL_INTERVAL_AFTER_ERROR = 60
local XEE_MIN_POLL_INTERVAL_FAR_AWAY = 700
local XEE_MIN_INTERVAL_BETWEEN_REQUESTS = 1

------------------------------------------------------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------------------------------------------------------

-- This table defines all device variables that are used by the plugin
-- Each entry is a table of 4 elements:
-- 1) the service ID
-- 2) the variable name
-- 3) true if the variable is not updated when the value is unchanged
-- 4) variable that is used for the timestamp
local VARIABLE = {
	SWITCH_POWER = { "urn:upnp-org:serviceId:SwitchPower1", "Status", true },
	-- Communication failure
	COMM_FAILURE = { "urn:micasaverde-com:serviceId:HaDevice1", "CommFailure", false, "COMM_FAILURE_TIME" },
	COMM_FAILURE_TIME = { "urn:micasaverde-com:serviceId:HaDevice1", "CommFailureTime", true },
	-- Xee
	PLUGIN_VERSION = { "urn:upnp-org:serviceId:Xee1", "PluginVersion", true },
	DEBUG_MODE = { "urn:upnp-org:serviceId:Xee1", "DebugMode", true },
	CLIENT_ID = { "urn:upnp-org:serviceId:Xee1", "ClientId", true },
	CLIENT_SECRET = { "urn:upnp-org:serviceId:Xee1", "ClientSecret", true },
	IDENTIFIER = { "urn:upnp-org:serviceId:Xee1", "Identifier", true },
	PASSWORD = { "urn:upnp-org:serviceId:Xee1", "Password", true },
	ACCESS_TOKEN = { "urn:upnp-org:serviceId:Xee1", "AccessToken", true },
	REFRESH_TOKEN = { "urn:upnp-org:serviceId:Xee1", "RefreshToken", true },
	TOKEN_EXPIRATION_DATE = { "urn:upnp-org:serviceId:Xee1", "TokenExpirationDate", true },
	LAST_UPDATE_DATE = { "urn:upnp-org:serviceId:Xee1", "LastUpdateDate", true },
	LAST_MESSAGE = { "urn:upnp-org:serviceId:Xee1", "LastMessage", true },
	LAST_ERROR = { "urn:upnp-org:serviceId:Xee1", "LastError", true },
	POLL_SETTINGS = { "urn:upnp-org:serviceId:Xee1", "PollSettings", true },
	-- Xee car
	CAR_STATUS = { "urn:upnp-org:serviceId:XeeCar1", "Status", true },
	CAR_NAME = { "urn:upnp-org:serviceId:XeeCar1", "Name", true },
	CAR_MAKE = { "urn:upnp-org:serviceId:XeeCar1", "Make", true },
	CAR_MODEL = { "urn:upnp-org:serviceId:XeeCar1", "Model", true },
	CAR_YEAR = { "urn:upnp-org:serviceId:XeeCar1", "Year", true },
	CAR_NUMBER_PLATE = { "urn:upnp-org:serviceId:XeeCar1", "NumberPlate", true },
	CAR_DEVICE_ID = { "urn:upnp-org:serviceId:XeeCar1", "DeviceId", true },
	CAR_DBID = { "urn:upnp-org:serviceId:XeeCar1", "CardbId", true },
	CAR_CREATION_DATE = { "urn:upnp-org:serviceId:XeeCar1", "CreationDate", true },
	CAR_LAST_UPDATE_DATE = { "urn:upnp-org:serviceId:XeeCar1", "LastUpdateDate", true },
	-- Xee car location
	--[[
	CAR_LATITUDE = { "urn:upnp-org:serviceId:XeeCar1", "Latitude", true },
	CAR_LONGITUDE = { "urn:upnp-org:serviceId:XeeCar1", "Longitude", true },
	CAR_ALTITUDE = { "urn:upnp-org:serviceId:XeeCar1", "Altitude", true },
	CAR_HEADING = { "urn:upnp-org:serviceId:XeeCar1", "Heading", true },
	--]]
	CAR_LATITUDE = { "urn:upnp-org:serviceId:Location1", "Latitude", true },
	CAR_LONGITUDE = { "urn:upnp-org:serviceId:Location1", "Longitude", true },
	CAR_ALTITUDE = { "urn:upnp-org:serviceId:Location1", "Altitude", true },
	CAR_HEADING = { "urn:upnp-org:serviceId:Location1", "Heading", true },
	CAR_LOCATION_DATE = { "urn:upnp-org:serviceId:Location1", "LocationDate", true },
	-- Geofence
	GEOFENCES = { "urn:upnp-org:serviceId:GeoFence1", "Fences", true },
	CAR_DISTANCE = { "urn:upnp-org:serviceId:GeoFence1", "Distance", true },
	CAR_DISTANCES = { "urn:upnp-org:serviceId:GeoFence1", "Distances", true },
	CAR_ZONE_IN = { "urn:upnp-org:serviceId:GeoFence1", "ZoneIn", true },
	CAR_ZONE_ENTER = { "urn:upnp-org:serviceId:GeoFence1", "ZoneEnter", true },
	CAR_ZONE_EXIT = { "urn:upnp-org:serviceId:GeoFence1", "ZoneExit", true },
	-- Xee car accelerometer
	CAR_ACCELEROMETER = { "urn:upnp-org:serviceId:XeeCar1", "Accelerometer", true },
	CAR_ACCELEROMETER_DATE = { "urn:upnp-org:serviceId:XeeCar1", "AccelerometerDate", true }
	-- Xee car signals (automatic declaration)
}

-- Device types
local DEVICE_TYPE = {
	XEE_CAR = {
		deviceType = "urn:schemas-upnp-org:device:XeeCar:1", deviceFile = "D_XeeCar1.xml"
	}
}
local function _getDeviceTypeInfos(deviceType)
	for deviceTypeName, deviceTypeInfos in pairs(DEVICE_TYPE) do
		if (deviceTypeInfos.deviceType == deviceType) then
			return deviceTypeInfos
		end
	end
end

-- Message types
local SYS_MESSAGE_TYPES = {
	BUSY    = 1,
	ERROR   = 2,
	SUCCESS = 4
}

------------------------------------------------------------------------------------------------------------------------
-- Globals
------------------------------------------------------------------------------------------------------------------------

local g_parentDeviceId      -- The device # of the parent device
local g_params = {
	nbMaxTry = 2,
	location = {}
}


-- **************************************************
-- Table functions
-- **************************************************

-- Merges (deeply) the contents of one table (t2) into another (t1)
local function table_extend (t1, t2)
	if ((t1 == nil) or (t2 == nil)) then
		return
	end
	for key, value in pairs(t2) do
		if (type(value) == "table") then
			if (type(t1[key]) == "table") then
				t1[key] = table_extend(t1[key], value)
			else
				t1[key] = table_extend({}, value)
			end
		elseif (value ~= nil) then
			t1[key] = value
		end
	end
	return t1
end

local table = table_extend({}, table) -- do not pollute original "table"
do -- Extend table
	table.extend = table_extend

	-- Checks if a table contains the given item.
	-- Returns true and the key / index of the item if found, or false if not found.
	function table.contains (t, item)
		for k, v in pairs(t) do
			if (v == item) then
				return true, k
			end
		end
		return false
	end

	-- Checks if table contains all the given items (table).
	function table.containsAll (t1, items)
		if ((type(t1) ~= "table") or (type(t2) ~= "table")) then
			return false
		end
		for _, v in pairs(items) do
			if not table.contains(t1, v) then
				return false
			end
		end
		return true
	end

	-- Appends the contents of the second table at the end of the first table
	function table.append (t1, t2, noDuplicate)
		if ((t1 == nil) or (t2 == nil)) then
			return
		end
		local table_insert = table.insert
		table.foreach(
			t2,
			function (_, v)
				if (noDuplicate and table.contains(t1, v)) then
					return
				end
				table_insert(t1, v)
			end
		)
		return t1
	end

	-- Extracts a subtable from the given table
	function table.extract (t, start, length)
		if (start < 0) then
			start = #t + start + 1
		end
		length = length or (#t - start + 1)

		local t1 = {}
		for i = start, start + length - 1 do
			t1[#t1 + 1] = t[i]
		end
		return t1
	end

	function table.concatChar (t)
		local res = ""
		for i = 1, #t do
			res = res .. string.char(t[i])
		end
		return res
	end

	-- Concatenates a table of numbers into a string with Hex separated by the given separator.
	function table.concatHex (t, sep, start, length)
		sep = sep or "-"
		start = start or 1
		if (start < 0) then
			start = #t + start + 1
		end
		length = length or (#t - start + 1)
		local s = _toHex(t[start])
		if (length > 1) then
			for i = start + 1, start + length - 1 do
				s = s .. sep .. _toHex(t[i])
			end
		end
		return s
	end

end

-- **************************************************
-- String functions
-- **************************************************

local string = table_extend({}, string) -- do not pollute original "string"
do -- Extend string
	-- Pads string to given length with given char from left.
	function string.lpad (s, length, c)
		s = tostring(s)
		length = length or 2
		c = c or " "
		return c:rep(length - #s) .. s
	end

	-- Pads string to given length with given char from right.
	function string.rpad (s, length, c)
		s = tostring(s)
		length = length or 2
		c = char or " "
		return s .. c:rep(length - #s)
	end

	-- Splits a string based on the given separator. Returns a table.
	function string.split (s, sep, convert, convertParam)
		if (type(convert) ~= "function") then
			convert = nil
		end
		if (type(s) ~= "string") then
			return {}
		end
		sep = sep or " "
		local t = {}
		for token in s:gmatch("[^" .. sep .. "]+") do
			if (convert ~= nil) then
				token = convert(token, convertParam)
			end
			table.insert(t, token)
		end
		return t
	end

	-- Formats a string into hex.
	function string.formatToHex (s, sep)
		sep = sep or "-"
		local result = ""
		if (s ~= nil) then
			for i = 1, string.len(s) do
				if (i > 1) then
					result = result .. sep
				end
				result = result .. string.format("%02X", string.byte(s, i))
			end
		end
		return result
	end
end


-- **************************************************
-- Generic utilities
-- **************************************************

function log (msg, methodName, lvl)
	local lvl = lvl or 50
	if (methodName == nil) then
		methodName = "UNKNOWN"
	else
		methodName = "(" .. _NAME .. "::" .. tostring(methodName) .. ")"
	end
	luup.log(string.rpad(methodName, 45) .. " " .. tostring(msg), lvl)
end

local function debug () end

local function warning (msg, methodName)
	log(msg, methodName, 2)
end

local g_errors = {}
local function error (msg, methodName)
	table.insert( g_errors, { os.time(), tostring(msg) } )
	if ( #g_errors > 100 ) then
		table.remove( g_errors, 1 )
	end
	log(msg, methodName, 1)
end


-- **************************************************
-- Variable management
-- **************************************************

Variable = {
	-- Get variable timestamp
	getTimestamp = function( deviceId, variable )
		if ( ( type( variable ) == "table" ) and ( type( variable[4] ) == "string" ) ) then
			local variableTimestamp = VARIABLE[ variable[4] ]
			if ( variableTimestamp ~= nil ) then
				return luup.variable_get( variableTimestamp[1], variableTimestamp[2], deviceId )
			end
		end
		return nil
	end,

	-- Set variable timestamp
	setTimestamp = function( deviceId, variable, timestamp )
		if ( variable[4] ~= nil ) then
			local variableTimestamp = VARIABLE[ variable[4] ]
			if ( variableTimestamp ~= nil ) then
				luup.variable_set( variableTimestamp[1], variableTimestamp[2], ( timestamp or os.time() ), deviceId )
			end
		end
	end,

	-- Get variable value (can deal with unknown variable TODO)
	get = function( deviceId, variable )
		deviceId = tonumber( deviceId )
		if ( deviceId == nil ) then
			error( "deviceId is nil", "Variable.get" )
			return
		elseif ( variable == nil ) then
			error( "variable is nil", "Variable.get" )
			return
		end
		local value, timestamp = luup.variable_get( variable[1], variable[2], deviceId )
		if ( value ~= "0" ) then
			local storedTimestamp = Variable.getTimestamp( deviceId, variable )
			if ( storedTimestamp ~= nil ) then
				timestamp = storedTimestamp
			end
		end
		return value, timestamp
	end,

	getUnknownVariable = function( deviceId, serviceId, variableName )
		local variable = indexVariable[tostring(serviceId) .. ";" .. tostring(variableName)]
		if (variable ~= nil) then
			return Variable.get(deviceId, variable)
		else
			return luup.variable_get(serviceId, variableName, deviceId)
		end
	end,

	-- Set variable value
	set = function( deviceId, variable, value )
		deviceId = tonumber( deviceId )
		if ( deviceId == nil ) then
			error( "deviceId is nil", "Variable.set" )
			return
		elseif (variable == nil) then
			error( "variable is nil", "Variable.set" )
			return
		elseif (value == nil) then
			error( "value is nil", "Variable.set" )
			return
		end
		if ( type( value ) == "number" ) then
			value = tostring( value )
		end
		local doChange = true
		local currentValue = luup.variable_get( variable[1], variable[2], deviceId )
		local deviceType = luup.devices[deviceId].device_type
		if ( ( currentValue == value ) and ( ( variable[3] == true ) or ( value == "0" ) ) ) then
			-- Variable is not updated when the value is unchanged
			doChange = false
		end

		if doChange then
			luup.variable_set( variable[1], variable[2], value, deviceId )
		end

		-- Updates linked variable for timestamp (just for active value)
		if ( value ~= "0" ) then
			Variable.setTimestamp( deviceId, variable, os.time() )
		end
	end,

	-- Get variable value and init if value is nil or empty
	getOrInit = function( deviceId, variable, defaultValue )
		local value, timestamp = Variable.get( deviceId, variable )
		if ( ( value == nil ) or (  value == "" ) ) then
			Variable.set( deviceId, variable, defaultValue )
			value = defaultValue
			timestamp = os.time()
		end
		return value, timestamp
	end,

	watch = function( deviceId, variable, callback )
		luup.variable_watch( callback, variable[1], variable[2], lul_device )
	end
}


-- **************************************************
-- UI messages
-- **************************************************

local g_taskHandle = -1     -- Handle for the system messages
local g_lastSysMessage = 0  -- Timestamp of the last status message

UI = {
	show = function( message )
		log( "Display message: " .. tostring( message ), "UI.show" )
		Variable.set( g_parentDeviceId, VARIABLE.LAST_MESSAGE, message )
	end,

	showError = function( message )
		message = '<div style="color:red">' .. tostring( message ) .. '</div>'
		Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, message )
	end,
	clearError = function()
		Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, "" )
	end,

	showSysMessage = function( message, mode, permanent )
		mode = mode or SYS_MESSAGE_TYPES.BUSY
		permanent = permanent or false
		log("mode: " .. mode .. ", permanent: " .. tostring( permanent ) .. ", message: " .. message, "UI.showSysMessage")

		luup.task( message, mode, "Xee", g_taskHandle )
		g_lastSysMessage = tostring( os.time() )

		if not permanent then
			-- Clear the previous system message, since it's transient.
			luup.call_delay( "UI.clearSysMessage", 30, g_lastSysMessage )
		elseif ( mode == SYS_MESSAGE_TYPES.ERROR ) then
			-- Critical error.
			--luup.set_failure( true, g_parentDeviceId )
			luup.set_failure( 1, g_parentDeviceId )
		end
	end,

	clearSysMessage = function( messageTime )
		-- 'messageTime' is nil if the function is called by the user.
		if ( ( messageTime == g_lastSysMessage ) or ( messageTime == nil ) ) then
			luup.task( "Clearing...", SYS_MESSAGE_TYPES.SUCCESS, "Xee", g_taskHandle )
		end
	end
}


-- **************************************************
-- Xee API
-- **************************************************

API = {
	-- Get the errors in the response
	-- [ { "type": "ERROR_TYPE", "message": "Message on the error", "tip": "How to fix the error" } ]
	getErrors = function( errors )
		if ( type( errors ) == "string" ) then
			local decodeSuccess, jsonErrors = pcall( json.decode, errors )
			if ( decodeSuccess and jsonErrors ) then
				errors = jsonErrors
			end
		end
		if ( type( errors ) == "table" ) then
			if ( errors.error ) then
				return { ["type"] = "UNKNOWN_ERROR", message = errors.error }
			else
				return errors
			end
		else
			return {}
		end
	end,

	-- Check if a response has a defined error
	hasError = function( errors, errorType, errorMessage )
		--print(json.encode(API.getErrors( errors )))
		for _, err in ipairs( API.getErrors( errors ) ) do
			if (
				( errorType == nil )
				or ( ( err.type == errorType ) and ( err.message == errorMessage ) )
			) then
				return true
			end
		end
		return false
	end,

	-- Convert Xee errors into string
	errorsToString = function( errors )
		local errorMessage = ""
		for i, err in ipairs( API.getErrors( errors ) ) do
			if ( i > 1 ) then
				errorMessage = errorMessage .. ", "
			end
			errorMessage = errorMessage .. "(" .. tostring( err.type ) .. ") " .. tostring( err.message )
		end
		return errorMessage
	end,

	-- Convert Xee time field into a timestamp
	convertToTimestamp = function( dateString )
		-- "2016-03-01T02:24:20.000000+00:00"
		local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+).%d+([%+%-])(%d+)%:(%d+)"
		local Y, m, d, H, M, S, off, offH, offM = string.match( dateString, pattern )
		local timestamp = os.time({
			year = Y, month = m, day = d,
			hour = H, min = M, sec = S
		})
		if offsetH then
			offset = offH * 60 + offM
			if ( off == "-" ) then
				offset = offset * -1
			end
		end
		return timestamp
	end,

	-- Store given tokens
	setTokens = function( params )
		local newTokenIsSet = false
		local decodeSuccess, jsonParams = pcall( json.decode, params or "" )
		if ( decodeSuccess and jsonParams ) then
			if jsonParams.access_token then
				g_params.accessToken = jsonParams.access_token
				Variable.set( g_parentDeviceId, VARIABLE.ACCESS_TOKEN, jsonParams.access_token )
				newTokenIsSet = true
			end
			if jsonParams.refresh_token then
				g_params.refreshToken = jsonParams.refresh_token
				Variable.set( g_parentDeviceId, VARIABLE.REFRESH_TOKEN, jsonParams.refresh_token )
			end
			if jsonParams.expires_at then
				g_params.tokenExpirationDate = jsonParams.expires_at
				Variable.set( g_parentDeviceId, VARIABLE.TOKEN_EXPIRATION_DATE, jsonParams.expires_at )
			end
			if newTokenIsSet then
				log( "New authorization tokens have been set: " .. tostring( params ), "API.setTokens" )
			else
				error( "No new token in given tokens : " .. tostring( params ), "API.setTokens" )
				return false
			end
			return true
		else
			error( "Error in given tokens : " .. tostring( jsonParams ), "API.setTokens" )
			return false
		end
	end,

	-- Just if Identifier and Password are set
	-- NOT USED
	getAccessToken = function()
		if ( ( g_params.identifier == "" ) or ( g_params.password == "" ) ) then
			error( "Identifier and/or Password is empty", "API.getAccessToken" )
			return false
		end

		local b, code, headers
		local requestBody, responseBody
		local response
		local sessionId, token, redirectUri

		-- Get the token in Xee authentification form
		local src = XEE_AUTH_URL ..
				"?client_id=" .. XEE_CLIENT_ID ..
				"&state=" .. url.escape( tostring( luup.pk_accesspoint ) .. ":" .. tostring( luup.model ) .. ":" .. tostring( luup.version ) )
		debug( "Call Xee authentification form: " .. src, "API.getAccessToken" )
		responseBody = {}
		b, code, headers = https.request({
			url = src,
			method = "GET",
			sink = ltn12.sink.table( responseBody ),
			redirect = false
		})
		response = table.concat( responseBody or {} )
		debug( "Response headers:" .. json.encode( headers ), "API.getAccessToken" )
		--debug( "Response b:" .. tostring(b) .. " - code:" .. tostring(code) .. " - response:" .. tostring(response), "API.getAccessToken" )
		if ( ( b == 1 ) and ( code == 200 ) ) then
			sessionId = headers[ "set-cookie" ]:match( "XEESessionId=([^;]-);" )
			token = response:match( 'name="login%[_token%]" value="([^"]-)"' )
			debug( "Response sessionId:\"" .. tostring(sessionId) .. "\", token:\"" .. tostring( token ) .. "\"", "API.getAccessToken")
			if ( ( sessionId == nil ) or ( token == nil ) ) then
				error( "(AUTHENTIFICATION_ERROR) Can not find sessionId or token in Xee authentification form", "API.getAccessToken" )
				return false
			end
		else
			error( "(AUTHENTIFICATION_ERROR) code:" .. tostring( code ) .. ", response:\"" .. tostring( response ) .. "\"", "API.getAccessToken" )
			return false
		end

		-- Submit Xee authentification form
		requestBody = "login%5Bidentifier%5D=" .. url.escape( tostring( g_params.identifier ) ) ..
						"&login%5Bpassword%5D=" .. url.escape( tostring( g_params.password ) ) ..
						"&login%5B_token%5D=" .. tostring( token )
		responseBody = {}
		b, code, headers = https.request({
			url = XEE_AUTH_URL,
			method = "POST",
			headers = {
				["cookie"] = "XEESessionId=" .. sessionId,
				["content-type"] = "application/x-www-form-urlencoded",
				["content-length"] = string.len( requestBody )
			},
			source = ltn12.source.string( requestBody ),
			sink = ltn12.sink.table( responseBody ),
			redirect = false
		})
		response = table.concat( responseBody or {} )
		debug( "Response headers:" .. json.encode( headers ), "API.getAccessToken")
		debug( "Response b:" .. tostring(b) .. " - code:" .. tostring(code) .. " - response:" .. tostring(response), "API.getAccessToken" )
		if ( ( b == 1 ) and ( code == 302 ) ) then
			-- Get the REDIRECT_URI (OAuth2)
			redirectUri = headers[ "location" ]
			if ( redirectUri == nil ) then
				error( "(AUTHENTIFICATION_ERROR) Can not find REDIRECT_URI", "API.getAccessToken" )
				return false
			end
		else
			error( "(AUTHENTIFICATION_ERROR) code:" .. tostring( code ) .. ", response:\"" .. tostring( response ) .. "\"", "API.getAccessToken" )
			return false
		end

		-- Call REDIRECT_URI
		debug( "Call REDIRECT_URI: " .. redirectUri, "API.getAccessToken" )
		responseBody = {}
		b, code, headers = https.request({
			url = redirectUri,
			method = "GET",
			sink = ltn12.sink.table( responseBody ),
			redirect = false
		})
		debug( "Response headers:" .. json.encode( headers ), "API.getAccessToken" )

		-- Google redirection (have to be done manually because it breaks SSL)
		if ( ( b == 1 ) and ( code == 302 ) ) then
			redirectUri = headers[ "location" ]
			debug( "Call REDIRECT_URI after Google redirection: " .. redirectUri, "API.getAccessToken" )
			responseBody = {}
			b, code, headers = https.request({
				url = redirectUri,
				method = "GET",
				sink = ltn12.sink.table( responseBody ),
				redirect = false
			})
			debug( "Response headers:" .. json.encode( headers ), "API.getAccessToken" )
		end

		response = table.concat( responseBody or {} )
		debug( "Response b:" .. tostring(b) .. " - code:" .. tostring(code) .. " - response:" .. tostring(response), "API.getAccessToken" )
		if ( ( b == 1 ) and ( code == 200 ) ) then
			-- TODO : a bug in Xee ?
			if ( response == '{"error":"invalid_request"}' ) then
				error( "(ERROR) " .. response, "API.getAccessToken" )
				return false
			end
			return API.setTokens( response )
		end

		error( API.errorsToString( response ), "API.getAccessToken" )
		return false
	end,

	-- Refresh access token (call third-party google apps script)
	refreshToken = function()
		if ( g_params.refreshToken == "" ) then
			error( "Refresh token is empty", "API.refreshToken" )
			return false
		end
		local src = XEE_REDIRECT_URI ..
				"?refreshToken=" .. g_params.refreshToken ..
				"&state=" .. url.escape( tostring( luup.pk_accesspoint ) .. ":" .. tostring( luup.model ) .. ":" .. tostring( luup.version ) )
		debug( "Call : " .. src, "API.refreshToken" )
		local responseBody = {}
		local b, code, headers = https.request({
			url = src,
			method = "GET",
			sink = ltn12.sink.table( responseBody ),
			redirect = false
		})
		debug("Response headers:" .. json.encode( headers ), "API.refreshToken")

		-- Google redirection (have to be done manually because it breaks SSL)
		if ( ( b == 1 ) and ( code == 302 ) ) then
			local newLocation = headers[ "location" ]
			debug( "Call : " .. newLocation, "API.refreshToken" )
			responseBody = {}
			b, code, headers = https.request({
				url = newLocation,
				method = "GET",
				sink = ltn12.sink.table( responseBody ),
				redirect = false
			})
			debug("Response headers:" .. json.encode( headers ), "API.refreshToken")
		end

		local response = table.concat( responseBody or {} )
		debug( "Response b:" .. tostring(b) .. " - code:" .. tostring(code) .. " - response:" .. tostring(response), "API.refreshToken" )
		if ( ( b == 1 ) and ( code == 200 ) ) then
			-- TODO : a bug in Xee ?
			if ( response == '{"error":"invalid_request"}' ) then
				error( "Error: " .. response, "API.refreshToken" )
				return false
			end
			return API.setTokens( response )
		end
		return false
	end,

	-- Call Xee
	request = function( apiPath )
		local url = XEE_API_URL .. apiPath
		debug( "Call : " .. url, "API.request" )

		--[[
		if ( ( g_params.accessToken == "" ) and g_params.identifier and g_params.password ) then
			-- Try to authentificate directly with Identifier/Password (not recommended)
			API.getAccessToken()
		end
		--]]

		if ( g_params.accessToken == "" ) then
			error( "Acces token is empty", "API.request" )
			UI.showError( "Authorization not set" )
			return nil
		end

		local data = nil
		local response
		local nbTry = 1
		local isAuthentificationError, isAuthorizationError = false, false
		local isTokenRefreshed = false
		while ( ( data == nil ) and not isAuthentificationError and not isAuthorizationError and ( nbTry <= g_params.nbMaxTry ) ) do
			-- Call Xee API (via https)
			debug( "Use access token:" .. g_params.accessToken, "API.request" )
			local responseBody = {}
			local b, code, headers = https.request({
				url = url,
				method = "GET",
				headers = {
					["Authorization"] = "Bearer " .. tostring( g_params.accessToken )
				},
				sink = ltn12.sink.table(responseBody)
			})
			debug("Response headers:" .. json.encode( headers ), "API.request")

			response = table.concat( responseBody or {} )
			debug("Response b:" .. tostring(b) .. " - code:" .. tostring(code) .. " - response:" .. tostring(response), "API.request")
			if ( b == 1 ) then
				local decodeSuccess, jsonResponse = pcall( json.decode, response )
				if not decodeSuccess then
					error( "(DECODE_ERROR) " .. tostring(jsonResponse), "API.request" )
				else
					if ( code == 200 ) then
						data = jsonResponse
						debug( "Data: " .. json.encode( data ), "API.request" )
						break
					elseif ( code == 401 ) then
						error( API.errorsToString( jsonResponse ), "API.request" )
						isAuthentificationError = true
					elseif ( code == 403 ) then
						if API.hasError( jsonResponse, "AUTHORIZATION_ERROR", "Token has expired" ) then
							if not isTokenRefreshed then
								-- Access token has expired, try to refresh
								isTokenRefreshed = API.refreshToken()
								if not isTokenRefreshed then
									error( API.errorsToString( jsonResponse ) .. " (during refresh of the access token)", "API.request" )
									isAuthentificationError = true
								else
									debug( "Acess token has been refreshed...", "API.request" )
								end
							else
								error( API.errorsToString( jsonResponse ) .. " (after refreshing access token)", "API.request" )
								isAuthentificationError = true
							end
						else
							error( API.errorsToString( jsonResponse ), "API.request" )
							isAuthorizationError = true
						end
					else
						error( API.errorsToString( jsonResponse ), "API.request" )
					end
				end
			else
				error( "(HTTP_ERROR) code:" .. tostring( code ) .. ", response:\"" .. tostring( response ) .. "\"", "API.request" )
			end
			if ( not isAuthentificationError and not isAuthorizationError ) then
				nbTry = nbTry + 1
				if ( ( data == nil ) and ( nbTry <= g_params.nbMaxTry ) ) then
					luup.sleep( XEE_MIN_INTERVAL_BETWEEN_REQUESTS * 1000 )
					debug( "Try #" .. tostring( nbTry ) .. "/" .. tostring( g_params.nbMaxTry ), "API.request"  )
				end
			end
		end

		if ( data == nil ) then
			if isAuthentificationError then
				UI.showError( "Authentification error" )
				Variable.set( g_parentDeviceId, VARIABLE.COMM_FAILURE, "2" )
				-- TODO : Change the ping interval
			elseif not isAuthorizationError then
				UI.showError( "Error" )
				Variable.set( g_parentDeviceId, VARIABLE.COMM_FAILURE, "1" )
			end
			-- For ALTUI
			luup.attr_set( "status", 2, g_parentDeviceId )
			--luup.set_failure( 1, g_parentDeviceId )
		else
			UI.clearError()
			Variable.set( g_parentDeviceId, VARIABLE.COMM_FAILURE, "0" )
			if ( luup.attr_get( "status", g_parentDeviceId ) == "2" ) then
				-- For ALTUI
				luup.attr_set( "status", -1, g_parentDeviceId )
			end
			--luup.set_failure( 0, g_parentDeviceId )
		end
		return data
	end,

	-- Get the user ID
	getUserId = function()
		local data = API.request("/users/me")
		if (data ~= nil) then
			return data.id
		else
			return nil
		end
	end,

	-- Get the cars of the user
	getCars = function()
		return API.request( "/users/me/cars" )
	end,

	-- Get the status of a car
	getCarStatus = function( carId )
		return API.request( "/cars/" .. tostring( carId ) .. "/status" )
	end
}


-- **************************************************
-- Geoloc
-- https://github.com/SierraWireless/ALEOSAF-samples/blob/master/simplegeofence/src/geoloc.lua
-- **************************************************

-- Precomputed helpers for distance
local pi_360              = math.pi/360
local pi_180_earth_radius = math.pi/180 * 6.371e6

Geoloc = {
	tostring = function (point)
		return string.format( "%g;%g", point.latitude, point.longitude )
	end,

	getDistance = function (p1, p2)
		local x1, x2 = p1.longitude, p2.longitude
		local y1, y2 = p1.latitude,  p2.latitude
		local z1, z2 = p1.altitude,  p2.altitude
		local dx  = (x2 - x1) * pi_180_earth_radius * math.cos( (y2 + y1) * pi_360 )
		local dy  = (y2 - y1) * pi_180_earth_radius
		local dz = z1 and z2 and (z2 - z1) or 0
		local distance = math.ceil( (dx*dx + dy*dy + dz*dz) ^ 0.5 )
		--assert (dx*dx+dy*dy+dz*dz >= 0)
		--assert ((dx*dx+dy*dy+dz*dz)^0.5 >= 0)
		debug( string.format("Found a distance of %dm between %s and %s", distance, Geoloc.tostring(p1), Geoloc.tostring(p2)), "Geoloc.getDistance" )
		return distance
	end
}


-- Home;50.00;0.0;1000|{{name}};{{latitude}};{{longitude}};{{radius}}
g_geoFences = {}

GeoFences = {
	init = function( strGeoFences )
		g_geoFences = {}
		for _, strGeoFence in ipairs( string.split( strGeoFences, "|" ) ) do
			local geoParams = string.split( strGeoFence, ";" )
			table.insert( g_geoFences, {
				name      = geoParams[1],
				latitude  = tonumber( geoParams[2] ),
				longitude = tonumber( geoParams[3] ),
				radius    = tonumber( geoParams[4] or 1000 ) or 1000
			} )
		end
		debug( "GeoFences : " .. json.encode( g_geoFences ), "GeoFences.init")
	end,

	update = function( deviceId )
		if ( #g_geoFences == 0 ) then
			debug( "No geofence", "GeoFences.update")
			return false
		end
		local location = {
			latitude = Variable.get( deviceId, VARIABLE.CAR_LATITUDE ),
			longitude = Variable.get( deviceId, VARIABLE.CAR_LONGITUDE )
		}
		local distances = {}
		local zonesIn = string.split( ( Variable.get( deviceId, VARIABLE.CAR_ZONE_IN ) or "" ) , ";" )
		local zonesEnter, zonesExit = {}, {}
		local somethingHasChanged = false
		for _, geoFence in ipairs( g_geoFences ) do
			local distance = Geoloc.getDistance( location, geoFence )
			local wasIn, pos = table.contains( zonesIn, geoFence.name ) 
			if ( distance <= geoFence.radius ) then
				-- Device is in the zone
				if not wasIn then
					debug( "Device #" .. tostring( deviceId ) .. " enters the zone '" ..  geoFence.name .. "'", "GeoFences.update")
					table.insert( zonesIn, geoFence.name )
					table.insert( zonesEnter, geoFence.name )
					somethingHasChanged = true
				end
			else
				-- Device is not in the zone
				if wasIn then
					debug( "Device #" .. tostring( deviceId ) .. " exits the zone '" ..  geoFence.name .. "'", "GeoFences.update")
					table.remove( zonesIn, pos )
					table.insert( zonesExit, geoFence.name )
					somethingHasChanged = true
				end
			end
			table.insert( distances, { geoFence.name, distance } )
		end
		if somethingHasChanged then
			Variable.set( deviceId, VARIABLE.CAR_ZONE_IN, table.concat( zonesIn, ";" ) )
			Variable.set( deviceId, VARIABLE.CAR_ZONE_ENTER, table.concat( zonesEnter, ";" ) )
			Variable.set( deviceId, VARIABLE.CAR_ZONE_EXIT, table.concat( zonesExit, ";" ) )
		end

		-- Update distances
		--[[
		table.sort( distances, function( d1, d2 )
			return d1[2] < d2[2]
		end )
		--]]
		local strDistances = ""
		for i, distance in ipairs( distances ) do
			if ( i > 1 ) then
				strDistances = strDistances .. "|"
			end
			strDistances = strDistances .. table.concat( distance , ";" )
		end
		Variable.set( deviceId, VARIABLE.CAR_DISTANCES, strDistances )
		-- Get the distance of the main zone (first)
		Variable.set( deviceId, VARIABLE.CAR_DISTANCE, distances[1][1] )
	end,

	getDistances = function( location )
		local distances = {}
		for _, geoFence in ipairs( g_geoFences ) do
			table.insert( distances, { geoFence.name, Geoloc.getDistance( location, geoFence ) } )
		end
		return distances
	end,

	getDistancesToString = function( location )
		local strDistances = ""
		for i, distance in ipairs( GeoFences.getDistances( location ) ) do
			if ( i > 1 ) then
				strDistances = strDistances .. "|"
			end
			strDistances = strDistances .. table.concat( distance , ";" )
		end
		return strDistances
	end
}


-- **************************************************
-- Cars
-- **************************************************

local g_cars = {}  -- The list of all our child devices
local g_indexCars = {}

Cars = {
	-- Synchronise with Xee Cloud
	sync = function()
		debug( "Sync cars", "Cars.sync" )

		local cars = API.getCars()
		if ( cars == nil ) then
			return false
		end

		-- Retrieve already created cars
		local knownCars = {}
		for deviceId, device in pairs( luup.devices ) do
			if ( device.device_num_parent == g_parentDeviceId ) then
				knownCars[ device.id ] = true
			end
		end

		-- http://wiki.micasaverde.com/index.php/Luup_Lua_extensions#Module:_luup.chdev
		local ptr = luup.chdev.start( g_parentDeviceId )

		for _, car in ipairs( cars ) do
			car.id = tostring( car.id )
			if ( knownCars[ car.id ] ) then
				-- Already known car - Keep it
				debug( "Keep car #" .. car.id, "Cars.sync" )
				luup.chdev.append( g_parentDeviceId, ptr, car.id, "", "", "", "", "", false )
			else
				debug( "Add car #" .. car.id .. " - " .. json.encode( car ), "Cars.sync" )
				local parameters = ""
				for _, param in ipairs({
					{ "COMM_FAILURE", "0" },
					{ "COMM_FAILURE_TIME", "0" },
					{ "CAR_STATUS", "1" },
					{ "CAR_NAME", car.name },
					{ "CAR_MAKE", car.make },
					{ "CAR_MODEL", car.model },
					{ "CAR_YEAR", car.year },
					{ "CAR_NUMBER_PLATE", car.numberPlate },
					{ "CAR_DEVICE_ID", car.deviceId },
					{ "CAR_DBID", car.cardbId },
					{ "CAR_CREATION_DATE", car.creationDate },
					{ "CAR_LAST_UPDATE_DATE", car.lastUpdateDate }
				}) do
					parameters = parameters .. VARIABLE[param[1]][1] .. "," .. VARIABLE[param[1]][2] .. "=" .. tostring(param[2] or "") .. "\n"
				end
				luup.chdev.append(
					g_parentDeviceId, ptr, car.id,
					car.name, "", DEVICE_TYPE.XEE_CAR.deviceFile, "",
					parameters,
					false
				)
			end
		end

		debug( "Start sync", "Cars.sync" )
		Variable.set( g_parentDeviceId, VARIABLE.LAST_UPDATE_DATE, os.time() )
		luup.chdev.sync( g_parentDeviceId, ptr )
		debug( "End sync", "Cars.sync" )

		return true
	end,

	-- Get a list with all our car devices.
	retrieve = function()
		g_cars = {}
		g_indexCars = {}
		for deviceId, device in pairs( luup.devices ) do
			if ( device.device_num_parent == g_parentDeviceId ) then
				local carId = device.id
				if ( carId == nil ) then
					debug( "Found child device #".. tostring( deviceId ) .."(".. device.description .."), but carId '" .. tostring( device.id ) .. "' is null", "Cars.retrieve" )
				else
					local car = g_indexCars[ tostring( carId ) ]
					if ( car == nil ) then
						car = {
							id = carId,
							name = device.description,
							deviceId = deviceId,
							--status = 1,
							distance = 0,
							status = {},
							nextPollDate = 0
						}
						table.insert( g_cars, car )
						g_indexCars[ tostring( carId ) ] = car
						debug( "Found car #".. tostring( carId ) .."(".. device.description ..")", "Cars.retrieve" )
					else
						warning(
							"Found car #".. tostring( carId ) .. "(".. device.description ..") but it was already registered",
							"Cars.retrieve"
						)
					end
				end
			end
		end
		if ( #g_cars == 0 ) then
			UI.show( "No car" )
		elseif ( #g_cars == 1 ) then
			UI.show( "1 car" )
		else
			UI.show( tostring( #g_cars ) .. " cars"  )
		end
		log( "Cars: " .. tostring( #g_cars ), "Cars.retrieve" )
	end,

	-- Update the informations and signals of a car
	update = function( carId )
		local car = g_indexCars[ tostring( carId ) ]
		if ( car == nil ) then
			warning( "Car #" .. tostring( carId ) .. " is unknown", "Cars.update" )
			return false
		end
		debug( "Update car #" .. carId, "Cars.update" )
		local carStatus = API.getCarStatus( carId )
		if ( carStatus ~= nil ) then
			car.lastUpdate = os.time()
			Variable.set( car.deviceId, VARIABLE.CAR_LAST_UPDATE_DATE, car.lastUpdate )
			-- Location
			if ( carStatus.location ) then
				Variable.set( car.deviceId, VARIABLE.CAR_LATITUDE, carStatus.location.latitude )
				Variable.set( car.deviceId, VARIABLE.CAR_LONGITUDE, carStatus.location.longitude )
				Variable.set( car.deviceId, VARIABLE.CAR_ALTITUDE, carStatus.location.altitude )
				Variable.set( car.deviceId, VARIABLE.CAR_HEADING, carStatus.location.heading )
				Variable.set( car.deviceId, VARIABLE.CAR_LOCATION_DATE, API.convertToTimestamp( carStatus.location.date ) )
				-- Distances from geofences (centers)
				GeoFences.update( car.deviceId )
			end
			-- TODO : accelerometer ?
			-- Signals
			if ( carStatus.signals ) then
				for _, signal in ipairs( carStatus.signals ) do
					local variableName = "Signal" .. tostring( signal.name )
					local formerValue = luup.variable_get( "urn:upnp-org:serviceId:XeeCar1", variableName, car.deviceId )
					local formerValueDate = luup.variable_get( "urn:upnp-org:serviceId:XeeCar1", variableName .. "Date", car.deviceId )
					local timestamp = API.convertToTimestamp( signal.date )
					if ( ( formerValue ~= tostring( signal.value ) ) or ( formerValueDate ~= tostring( timestamp ) ) ) then
						luup.variable_set( "urn:upnp-org:serviceId:XeeCar1", variableName, signal.value, car.deviceId )
						luup.variable_set( "urn:upnp-org:serviceId:XeeCar1", variableName .. "Date", timestamp, car.deviceId )
					end
				end
			end
			luup.set_failure( 0, car.deviceId )
			car.status = carStatus
			--car.status = 1
			return true
		else
			error( "Can not retrieve car #" .. tostring( carId ) .. "(" .. tostring( car.name ) .. ") status", "Cars.update" )
			luup.set_failure( 1, car.deviceId )
			car.status = {}
			--car.status = 0
			return false
		end
	end
}


-- **************************************************
-- Poll engine
-- **************************************************

PollEngine = {
	start = function()
		log( "Start poll", "PollEngine.start" )

		local pollInterval = g_params.pollSettings[ 1 ]

		if ( ( #g_cars > 0 ) and not ( luup.attr_get( "disabled", g_parentDeviceId ) == 1 ) ) then
			table.sort( g_cars, function( car1, car2 )
				return car1.nextPollDate < car2.nextPollDate
			end )

			-- Poll the car that need to be polled first
			if ( os.difftime( g_cars[ 1 ].nextPollDate, os.time() ) <= 0 ) then
				if Cars.update( g_cars[ 1 ].id ) then
					--if ( g_cars[ 1 ].distance > XEE_ ) then
					--else
						pollInterval = g_params.pollSettings[ 1 ]
					--end
				else
					-- Use the poll interval defined for errors
					pollInterval = g_params.pollSettings[ 2 ]
				end
				g_cars[ 1 ].nextPollDate = os.time() + pollInterval
			end

			if ( #g_cars > 1 ) then
				pollInterval = os.difftime( math.min( g_cars[ 1 ].nextPollDate, g_cars[ 2 ].nextPollDate ), os.time() )
				if ( pollInterval < XEE_MIN_INTERVAL_BETWEEN_REQUESTS ) then
					pollInterval = XEE_MIN_INTERVAL_BETWEEN_REQUESTS
				end
			end
		end

		debug( "Next poll in " .. tostring( pollInterval ) .. " seconds", "PollEngine.start" )
		luup.call_delay( "Xee.PollEngine.start", pollInterval )
	end

}

------------------------------------------------------------------------------------------------------------------------
-- Request handler
------------------------------------------------------------------------------------------------------------------------

local _handlerCommands = {
	["default"] = function( params, outputFormat )
		return "Unknown command '" .. tostring( params["command"] ) .. "'", "text/plain"
	end,

	["getCars"] = function( params, outputFormat )
		local cars = {}
		for _, car in ipairs( g_cars ) do
			table.insert( cars, car )
		end
		return tostring( json.encode( cars ) ), "application/json"
	end,

	["getErrors"] = function( params, outputFormat )
		return tostring( json.encode( g_errors ) ), "application/json"
	end
}
setmetatable(_handlerCommands,{
	__index = function( t, command, outputFormat )
		log( "No handler for command '" ..  tostring( command ) .. "'", "handlerXee")
		return _handlerCommands["default"]
	end
})

local function _handleCommand( lul_request, lul_parameters, lul_outputformat )
	local command = lul_parameters[ "command" ] or "default"
	log( "Get handler for command '" .. tostring( command ) .."'", "handleCommand" )
	return _handlerCommands[ command ]( lul_parameters, lul_outputformat )
end


-- **************************************************
-- Action implementations
-- **************************************************

function setTokens( params )
	if API.setTokens( params ) then
		g_params.userId = API.getUserId()
	end
end

function sync()
	Cars.sync()
	Cars.retrieve()
end


-- **************************************************
-- Startup
-- **************************************************

-- Init plugin instance
local function _initPluginInstance()
	log( "initPluginInstance", "init" )

	-- Update the Debug Mode
	local debugMode = ( Variable.getOrInit( g_parentDeviceId, VARIABLE.DEBUG_MODE, "0" ) == "1" ) and true or false
	if debugMode then
		log( "DebugMode is enabled", "init" )
		debug = log
	else
		log( "DebugMode is disabled", "init" )
		debug = function () end
	end

	Variable.set( g_parentDeviceId, VARIABLE.PLUGIN_VERSION, _VERSION )
	Variable.set( g_parentDeviceId, VARIABLE.LAST_MESSAGE, "" )
	Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, "" )
	--g_params.identifier = Variable.getOrInit( g_parentDeviceId, VARIABLE.IDENTIFIER, "" )
	--g_params.password = Variable.getOrInit( g_parentDeviceId, VARIABLE.PASSWORD, "" )
	g_params.accessToken = Variable.getOrInit( g_parentDeviceId, VARIABLE.ACCESS_TOKEN, "" )
	g_params.refreshToken = Variable.getOrInit( g_parentDeviceId, VARIABLE.REFRESH_TOKEN, "" )
	g_params.tokenExpirationDate = Variable.getOrInit( g_parentDeviceId, VARIABLE.TOKEN_EXPIRATION_DATE, "" )
	g_params.pollSettings = string.split( Variable.getOrInit( g_parentDeviceId, VARIABLE.POLL_SETTINGS, "60,700,700" ), ",", tonumber )
	if ( ( g_params.pollSettings[ 1 ] or 0 ) < XEE_MIN_POLL_INTERVAL ) then
		g_params.pollSettings[ 1 ] = XEE_MIN_POLL_INTERVAL
	end
	if ( ( g_params.pollSettings[ 2 ] or 0 ) < XEE_MIN_POLL_INTERVAL_AFTER_ERROR ) then
		g_params.pollSettings[ 2 ] = XEE_MIN_POLL_INTERVAL_AFTER_ERROR
	end
	if ( ( g_params.pollSettings[ 3 ] or 0 ) < XEE_MIN_POLL_INTERVAL_FAR_AWAY ) then
		g_params.pollSettings[ 3 ] = XEE_MIN_POLL_INTERVAL_FAR_AWAY
	end

	local defaultGeoFence = "Home;" .. luup.latitude .. ";" .. luup.longitude .. ";1000"
	GeoFences.init( Variable.getOrInit( g_parentDeviceId, VARIABLE.GEOFENCES, defaultGeoFence ) )

	g_params.location = {
		latitude = luup.latitude,
		longitude = luup.longitude
	}
end

-- Register with ALTUI once it is ready
local function _registerWithALTUI()
	for deviceId, device in pairs( luup.devices ) do
		if ( device.device_type == "urn:schemas-upnp-org:device:altui:1" ) then
			if luup.is_ready(deviceId) then
				log( "Register with ALTUI main device #" .. tostring( deviceId ), "registerWithALTUI" )
				luup.call_action(
					"urn:upnp-org:serviceId:altui1",
					"RegisterPlugin",
					{
						newDeviceType = "urn:schemas-upnp-org:device:Xee:1",
						newScriptFile = "J_Xee1.js",
						newDeviceDrawFunc = "Xee.ALTUI_drawXeeDevice"
					},
					deviceId
				)
				luup.call_action(
					"urn:upnp-org:serviceId:altui1",
					"RegisterPlugin",
					{
						newDeviceType = "urn:schemas-upnp-org:device:XeeCar:1",
						newScriptFile = "J_Xee1.js",
						newDeviceDrawFunc = "Xee.ALTUI_drawXeeCarDevice"
					},
					deviceId
				)
			else
				log( "ALTUI main device #" .. tostring( deviceId ) .. " is not yet ready, retry to register in 10 seconds...", "registerWithALTUI" )
				luup.call_delay( "Xee.registerWithALTUI", 10 )
			end
			break
		end
	end
end

local function _deferredStartup()
	-- Sync the cars with Xee cloud
	local result = Cars.sync()
	Cars.retrieve()

	if result then
		PollEngine.start()
	else
		luup.call_delay( "Xee.PollEngine.start", XEE_MIN_POLL_INTERVAL_AFTER_ERROR )
	end
end

function startup( lul_device )
	log( "Start plugin '" .. _NAME .. "' (v" .. _VERSION .. ")", "startup" )

	-- Get the master device
	g_parentDeviceId = lul_device

	-- Check if the device is disabled
	g_params.isDisabled = ( luup.attr_get( "disabled", g_parentDeviceId ) == 1 )
	if g_params.isDisabled then
		log( "Device #" .. tostring( g_parentDeviceId ) .. " is disabled", "startup" )
		UI.show( "disabled" )
		return false, "Device #" .. tostring( g_parentDeviceId ) .. " is disabled"
	end

	-- Get a handle for system messages
	g_taskHandle = luup.task( "Starting up...", 1, "Xee", -1 )

	-- Init
	_initPluginInstance()
	-- Watch setting changes
	Variable.watch( g_parentDeviceId, VARIABLE.DEBUG_MODE, "Xee.initPluginInstance" )
	--Variable.watch( g_parentDeviceId, VARIABLE.IDENTIFIER, "Xee.initPluginInstance" )
	--Variable.watch( g_parentDeviceId, VARIABLE.PASSWORD, "Xee.initPluginInstance" )
	Variable.watch( g_parentDeviceId, VARIABLE.POLL_SETTINGS, "Xee.initPluginInstance" )
	-- Handlers
	luup.register_handler( "Xee.handleCommand", "Xee" )
	-- Register with ALTUI
	luup.call_delay( "Xee.registerWithALTUI", 10 )

	-- Deferred startup
	luup.call_delay( "Xee.deferredStartup", 1 )

	luup.set_failure( 0, g_parentDeviceId )
	return true
end


-- Promote the functions used by Vera's luup.xxx functions to the global name space
_G["Xee.handleCommand"] = _handleCommand
_G["UI.clearSysMessage"] = UI.clearSysMessage
_G["Xee.PollEngine.start"] = PollEngine.start

_G["Xee.deferredStartup"] = _deferredStartup
_G["Xee.initPluginInstance"] = _initPluginInstance
_G["Xee.registerWithALTUI"] = _registerWithALTUI
