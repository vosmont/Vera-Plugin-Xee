--[[
  This file is part of the plugin Xee.
  https://github.com/vosmont/Vera-Plugin-Xee
  Copyright (c) 2019 Vincent OSMONT
  This code is released under the MIT License, see LICENSE.
--]]

module( "L_Xee1", package.seeall )

-- Load libraries
local json = require( "dkjson" )
local https = require( "ssl.https" )
local ltn12 = require( "ltn12" )
local Url = require( "socket.url" )

-- **************************************************
-- Plugin constants
-- **************************************************

_NAME = "Xee"
_DESCRIPTION = "Add your vehicles in your scenes"
_VERSION = "1.1"
_AUTHOR = "vosmont"

local XEE_API_URL  = "https://api.xee.com/v4"
local XEE_PROXY_URL = "https://script.google.com/macros/s/AKfycbyAIrB1IFq0GhitEUu1kH_Agy1bUlaX5CDpI7U-XtAVcJeScYLg/exec"
local MIN_POLL_INTERVAL = 5
local MIN_POLL_INTERVAL_AFTER_ERROR = 60
local MIN_POLL_INTERVAL_FAR_AWAY = 700
local MIN_INTERVAL_BETWEEN_REQUESTS = 1

-- **************************************************
-- Constants
-- **************************************************

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
	-- Plugin Xee
	PLUGIN_VERSION = { "urn:upnp-org:serviceId:Xee1", "PluginVersion", true },
	DEBUG_MODE = { "urn:upnp-org:serviceId:Xee1", "DebugMode", true },
	ACCESS_TOKEN = { "urn:upnp-org:serviceId:Xee1", "AccessToken", true },
	REFRESH_TOKEN = { "urn:upnp-org:serviceId:Xee1", "RefreshToken", true },
	TOKEN_EXPIRATION_DATE = { "urn:upnp-org:serviceId:Xee1", "TokenExpirationDate", true },
	LAST_UPDATE_DATE = { "urn:upnp-org:serviceId:Xee1", "LastUpdateDate", true },
	LAST_MESSAGE = { "urn:upnp-org:serviceId:Xee1", "LastMessage", true },
	LAST_ERROR = { "urn:upnp-org:serviceId:Xee1", "LastError", true },
	POLL_SETTINGS = { "urn:upnp-org:serviceId:Xee1", "PollSettings", true },
	FIRST_NAME = { "urn:upnp-org:serviceId:Xee1", "FirstName", true },
	LAST_NAME = { "urn:upnp-org:serviceId:Xee1", "LastName", true },
	-- Xee vehicle
	VEHICLE_STATUS = { "urn:upnp-org:serviceId:XeeVehicle1", "Status", true },
	VEHICLE_NAME = { "urn:upnp-org:serviceId:XeeVehicle1", "Name", true },
	VEHICLE_MAKE = { "urn:upnp-org:serviceId:XeeVehicle1", "Make", true },
	VEHICLE_MODEL = { "urn:upnp-org:serviceId:XeeVehicle1", "Model", true },
	VEHICLE_YEAR = { "urn:upnp-org:serviceId:XeeVehicle1", "Year", true },
	VEHICLE_DEVICE_ID = { "urn:upnp-org:serviceId:XeeVehicle1", "DeviceId", true },
	VEHICLE_CREATION_DATE = { "urn:upnp-org:serviceId:XeeVehicle1", "CreationDate", true },
	VEHICLE_LAST_UPDATE_DATE = { "urn:upnp-org:serviceId:XeeVehicle1", "LastUpdateDate", true },
	-- Location
	LOCATION_LATITUDE = { "urn:upnp-org:serviceId:Location1", "Latitude", true },
	LOCATION_LONGITUDE = { "urn:upnp-org:serviceId:Location1", "Longitude", true },
	LOCATION_ALTITUDE = { "urn:upnp-org:serviceId:Location1", "Altitude", true },
	LOCATION_HEADING = { "urn:upnp-org:serviceId:Location1", "Heading", true },
	LOCATION_DATE = { "urn:upnp-org:serviceId:Location1", "LocationDate", true },
	-- Geofence
	GEOFENCES = { "urn:upnp-org:serviceId:GeoFence1", "Fences", true },
	GEOFENCE_DISTANCE = { "urn:upnp-org:serviceId:GeoFence1", "Distance", true },
	GEOFENCE_DISTANCES = { "urn:upnp-org:serviceId:GeoFence1", "Distances", true },
	GEOFENCE_ZONES_IN = { "urn:upnp-org:serviceId:GeoFence1", "ZonesIn", true },
	GEOFENCE_ZONE_ENTER = { "urn:upnp-org:serviceId:GeoFence1", "ZoneEnter", true },
	GEOFENCE_ZONE_EXIT = { "urn:upnp-org:serviceId:GeoFence1", "ZoneExit", true },
	GEOFENCE_ZONE_IDS_IN = { "urn:upnp-org:serviceId:GeoFence1", "ZoneIdsIn", true },
	GEOFENCE_ZONE_ID_ENTER = { "urn:upnp-org:serviceId:GeoFence1", "ZoneIdEnter", true },
	GEOFENCE_ZONE_ID_EXIT = { "urn:upnp-org:serviceId:GeoFence1", "ZoneIdExit", true },
	-- Xee vehicle accelerometer
	VEHICLE_ACCELEROMETER = { "urn:upnp-org:serviceId:XeeVehicle1", "Accelerometer", true },
	VEHICLE_ACCELEROMETER_DATE = { "urn:upnp-org:serviceId:XeeVehicle1", "AccelerometerDate", true }
	-- Xee vehicle signals (automatic declaration)
}

-- Device types
local DEVICE_TYPE = {
	XEE_VEHICLE = {
		deviceType = "urn:schemas-upnp-org:device:XeeVehicle:1", deviceFile = "D_XeeVehicle1.xml"
	}
}
local function _getDeviceTypeInfos( deviceType )
	for deviceTypeName, deviceTypeInfos in pairs( DEVICE_TYPE ) do
		if ( deviceTypeInfos.deviceType == deviceType ) then
			return deviceTypeInfos
		end
	end
end


-- **************************************************
-- Globals
-- **************************************************

local g_parentDeviceId      -- The device # of the parent device
local g_params = {
	nbMaxTry = 2,
	location = {}
}

local MAP_TEMPLATE_GMAP = [[
<!DOCTYPE html>
<html>
<head>
	<meta name="viewport" content="initial-scale=1.0, user-scalable=no" />
	<link rel="stylesheet" type="text/css" href="//maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css">
	<style type="text/css">
		html { height: 100% }
		body { height: 100%; margin: 0px; padding: 0px }
		#map { height: 100% ; width:100%;}
		.legend { background: white; margin: 10px; padding: 10px;
			border: 2px solid #aaa;
			-webkit-box-shadow: rgba(0, 0, 0, 0.398438) 0px 2px 4px;
			box-shadow: rgba(0, 0, 0, 0.398438) 0px 2px 4px;
			min-width: 170px;
		}
		.legend-title { font-weight: bold; }
		.legend-content { margin-top: 5px; }
	</style>
	<script type="text/javascript" src="//ajax.googleapis.com/ajax/libs/jquery/1.12.2/jquery.min.js" ></script>
	<script type="text/javascript" src="//maps.google.com/maps/api/js?v=3.13&sensor=false"></script>
	<script type="text/javascript" src="J_Xee1_map.js"></script> 
</head>
 
<body onload="XeeMap.initialize()">
	<div id="map"></div>
	<div id="legend-zones" class="legend"></div>
	<div id="legend-vehicles" class="legend"></div>
</body>
 
</html>
]]


-- OpenStreetMap
local MAP_TEMPLATE = [[
<!DOCTYPE html>
<html>
<head>
	<meta name="viewport" content="initial-scale=1.0, user-scalable=no" />
	<link rel="stylesheet" href="https://unpkg.com/leaflet@1.4.0/dist/leaflet.css" integrity="sha512-puBpdR0798OZvTTbP4A8Ix/l+A4dHDD0DGqYW6RQ+9jxkRFclaxxQb/SJAWZfWAkuyeQUytO7+7N4QKrDh+drA==" crossorigin=""/>
	<link rel="stylesheet" type="text/css" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css">
	<style type="text/css">
		html { height: 100% }
		body { height: 100%; margin: 0px; padding: 0px }
		#map { height: 100% ; width:100%;}
		.legend { background: white; margin: 10px; padding: 10px;
			border: 2px solid #aaa;
			-webkit-box-shadow: rgba(0, 0, 0, 0.398438) 0px 2px 4px;
			box-shadow: rgba(0, 0, 0, 0.398438) 0px 2px 4px;
			min-width: 170px;
		}
		.legend-title { font-weight: bold; }
		.legend-content { margin-top: 5px; }
		
		.leaflet-label {
			background: rgb(235, 235, 235);
			background: rgba(235, 235, 235, 0.81);
			background-clip: padding-box;
			border-color: #777;
			border-color: rgba(0,0,0,0.25);
			border-radius: 4px;
			border-style: solid;
			border-width: 4px;
			color: #111;
			display: block;
			font: 12px/20px "Helvetica Neue", Arial, Helvetica, sans-serif;
			font-weight: bold;
			padding: 1px 6px;
			position: absolute;
			-webkit-user-select: none;
			   -moz-user-select: none;
				-ms-user-select: none;
					user-select: none;
			pointer-events: none;
			white-space: nowrap;
			z-index: 6;
		}

		.leaflet-label.leaflet-clickable {
			cursor: pointer;
		}

		.leaflet-label:before,
		.leaflet-label:after {
			border-top: 6px solid transparent;
			border-bottom: 6px solid transparent;
			content: none;
			position: absolute;
			top: 5px;
		}

		.leaflet-label:before {
			border-right: 6px solid black;
			border-right-color: inherit;
			left: -10px;
		}

		.leaflet-label:after {
			border-left: 6px solid black;
			border-left-color: inherit;
			right: -10px;
		}

		.leaflet-label-right:before,
		.leaflet-label-left:after {
			content: "";
		}
	</style>
	<script src="https://code.jquery.com/jquery-3.3.1.min.js" integrity="sha256-FgpCb/KJQlLNfOu91ta32o/NMZxltwRo8QtmkMRdAu8=" crossorigin="anonymous"></script>
	<script src="https://unpkg.com/leaflet@1.4.0/dist/leaflet.js" integrity="sha512-QVftwZFqvtRNi0ZyCtsznlKSWOStnDORoefr1enyq5mVL4tmKB3S/EnC3rRJcxCPavG10IcrVGSmPh6Qw5lwrg==" crossorigin=""></script>
	<script src="https://unpkg.com/leaflet-editable@1.2.0/src/Leaflet.Editable.js" integrity="sha384-pTfDiyc6TOMIl5e4Jo3XeZj7HAvuZk7XXeorhQ9YCzfxYhP6q5CVxwcyjvq/G8R8" crossorigin="anonymous"></script>
	<script type="text/javascript" src="J_Xee1_map.js"></script> 
</head>

<body onload="XeeMap.initialize( { lat: $latitude, lng: $longitude } )">
	<div id="map"></div>
</body>

</html>
]]

-- **************************************************
-- Table functions
-- **************************************************

-- Checks if a table contains the given item.
-- Returns true and the key / index of the item if found, or false if not found.
function table_contains( t, item )
	for k, v in pairs( t ) do
		if ( v == item ) then
			return true, k
		end
	end
	return false
end


-- **************************************************
-- String functions
-- **************************************************

-- Returns if a string is empty (nil or "")
function string_isEmpty( s )
	return ( ( s == nil ) or ( s == "" ) ) 
end

-- Pads string to given length with given char from right.
function string_rpad( s, length, c )
	s = tostring( s )
	length = length or 2
	c = char or " "
	return s .. c:rep( length - #s )
end

-- Splits a string based on the given separator. Returns a table.
function string_split( s, sep, convert, convertParam )
	if ( type( convert ) ~= "function" ) then
		convert = nil
	end
	if ( type( s ) ~= "string" ) then
		return {}
	end
	sep = sep or " "
	local t = {}
	for token in s:gmatch( "[^" .. sep .. "]+" ) do
		if ( convert ~= nil ) then
			token = convert( token, convertParam )
		end
		table.insert( t, token )
	end
	return t
end

function string_decodeURI( s )
	if string_isEmpty( s ) then
		return ""
	end
	local hex={}
	for i = 0, 255 do
		hex[ string.format("%0X",i) ] = string.char(i)
	end
	return ( s:gsub( '%%(%x%x)', hex ) )
end

-- **************************************************
-- Generic utilities
-- **************************************************

function log( msg, methodName, lvl )
	local lvl = lvl or 50
	if ( methodName == nil ) then
		methodName = "UNKNOWN"
	else
		methodName = "(" .. _NAME .. "::" .. tostring( methodName ) .. ")"
	end
	luup.log( string_rpad( methodName, 45 ) .. " " .. tostring( msg ), lvl )
end

local function debug() end

local function warning( msg, methodName )
	log( msg, methodName, 2 )
end

local g_errors = {}
local function error( msg, methodName )
	table.insert( g_errors, { os.time(), tostring( msg ) } )
	if ( #g_errors > 100 ) then
		table.remove( g_errors, 1 )
	end
	log( msg, methodName, 1 )
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
				return tonumber( ( luup.variable_get( variableTimestamp[1], variableTimestamp[2], deviceId ) ) )
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

	-- Get variable value (can deal with unknown variable)
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

	getUnknown = function( deviceId, serviceId, variableName )
		local variable = indexVariable[ tostring( serviceId ) .. ";" .. tostring( variableName ) ]
		if ( variable ~= nil ) then
			return Variable.get( deviceId, variable )
		else
			return luup.variable_get( serviceId, variableName, deviceId )
		end
	end,

	-- Set variable value
	set = function( deviceId, variable, value )
		deviceId = tonumber( deviceId )
		if ( deviceId == nil ) then
			error( "deviceId is nil", "Variable.set" )
			return
		elseif ( variable == nil ) then
			error( "variable is nil", "Variable.set" )
			return
		elseif ( value == nil ) then
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
			value = defaultValue
			Variable.set( deviceId, variable, value )
			timestamp = os.time()
			Variable.setTimestamp( deviceId, variable, timestamp )
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

UI = {
	show = function( message )
		debug( "Display message: " .. tostring( message ), "UI.show" )
		Variable.set( g_parentDeviceId, VARIABLE.LAST_MESSAGE, message )
	end,

	showError = function( message )
		debug( "Display message: " .. tostring( message ), "UI.showError" )
		message = '<font color="red">' .. tostring( message ) .. '</font>'
		Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, message )
	end,

	clearError = function()
		Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, "" )
	end
}


-- **************************************************
-- Xee API
-- **************************************************

-- Compute the difference in seconds between local time and UTC.
local function get_timezone()
	local now = os.time()
	local lmt = os.date( "*t", now )
	local gmt = os.date( "!*t", now )
	local zone = os.difftime( os.time( lmt ), os.time( gmt ) )
	if lmt.isdst then
		if zone > 0 then
			zone = zone + 3600
		else
			zone = zone - 3600
		end
	end
	return zone
end

local _timezone = get_timezone()

API = {
	-- Get the errors in the response
	-- [ { "type": "ERROR_TYPE", "message": "Message on the error", "tip": "How to fix the error" } ]
	getErrors = function( errors )
		if ( type( errors ) == "string" ) then
			local decodeSuccess, errorsFromJson = pcall( json.decode, errors )
			if ( decodeSuccess and errorsFromJson ) then
				errors = errorsFromJson
			else
				return { { ["type"] = "UNKNOWN_ERROR", message = errors } }
			end
		end
		if ( type( errors ) == "table" ) then
			if ( errors.error ) then
				return { { ["type"] = errors.error, message = errors.error_description or "" } }
			else
				return errors
			end
		else
			return {}
		end
	end,

	-- Check if a response has a defined error
	hasError = function( errors, errorType, errorMessage )
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

	-- Convert timestamp into Xee time
	convertTimestampToDate = function( timestamp )
		local t = os.date( "!*t", timestamp )
		return string.format( "%04d-%02d-%02dT%02d:%02d:%02dZ", t.year, t.month, t.day, t.hour, t.min, t.sec )
	end,

	-- Convert Xee time field into a timestamp
	convertDateToTimestamp = function( dateString )
		if ( ( dateString == nil ) or ( dateString == "" ) ) then
			return
		end
		local Y, m, d, H, M, S, off, offH, offM
		
		local patterns = {
			-- "2016-06-25T10:44:00Z"
			"(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)(Z)",
			-- "2016-06-25T10:44:00.788Z"
			"(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+).%d+(Z)",
			-- "2016-03-01T02:24:20.000000+02:00"
			"(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+).%d+([%+%-])(%d+)%:(%d+)"
		}
		for _, pattern in ipairs( patterns ) do
			Y, m, d, H, M, S, off, offH, offM = string.match( dateString, pattern )
			if ( Y and m and d ) then
				break
			end
		end
		if ( Y == nil ) then
			error( "Date '" .. dateString .. "' is not valid", "convertDateToTimestamp" )
			return
		end
		local timestamp = os.time( {
			year = Y, month = m, day = d,
			hour = H, min = M, sec = S
		})
		if off then
			local offset
			if ( off == "Z" ) then
				offset = _timezone
			else
				offset = offH * 60 + offM
				if ( off == "-" ) then
					offset = offset * -1
				end
			end
			timestamp = timestamp + offset
		end
		return timestamp
	end,

	-- Store given tokens
	setTokens = function( jsonParams )
		local newTokenIsSet = false
		local decodeSuccess, params = pcall( json.decode, jsonParams or "" )
		if ( decodeSuccess and params ) then
			if params.firstName then
				Variable.set( g_parentDeviceId, VARIABLE.FIRST_NAME, params.firstName )
			end
			if params.lastName then
				Variable.set( g_parentDeviceId, VARIABLE.LAST_NAME, params.lastName )
			end
			if params.access_token then
				g_params.accessToken = params.access_token
				Variable.set( g_parentDeviceId, VARIABLE.ACCESS_TOKEN, params.access_token )
				newTokenIsSet = true
			end
			if params.refresh_token then
				g_params.refreshToken = params.refresh_token
				Variable.set( g_parentDeviceId, VARIABLE.REFRESH_TOKEN, params.refresh_token )
			end
			if params.expires_in then
				g_params.tokenExpirationDate = os.time() + ( tonumber(params.expires_in) or 0 )
				Variable.set( g_parentDeviceId, VARIABLE.TOKEN_EXPIRATION_DATE, g_params.tokenExpirationDate )
			end
			if newTokenIsSet then
				log( "New authorization tokens have been set: " .. tostring( jsonParams ), "API.setTokens" )
			else
				error( "No new token in given tokens : " .. tostring( jsonParams ), "API.setTokens" )
				return false
			end
			return true
		else
			error( "Error in given tokens : " .. tostring( jsonParams ), "API.setTokens" )
			return false
		end
	end,

	-- Refresh access token (call third-party google apps script)
	refreshToken = function()
		if ( g_params.refreshToken == "" ) then
			error( "Refresh token is empty", "API.refreshToken" )
			return false
		end
		local src = XEE_PROXY_URL ..
				"?refreshToken=" .. g_params.refreshToken ..
				"&state=" .. Url.escape( tostring( luup.pk_accesspoint ) .. ":" .. tostring( luup.model or "Not a Vera" ) .. ":" .. tostring( luup.version ) .. ":" .. _VERSION )
		debug( "Call : " .. src, "API.refreshToken" )
		local responseBody = {}
		local b, code, headers = https.request( {
			url = src,
			method = "GET",
			sink = ltn12.sink.table( responseBody ),
			redirect = false
		})
		debug( "Response headers:" .. json.encode( headers ), "API.refreshToken" )

		-- Google redirection (have to be done manually because it breaks SSL)
		if ( ( b == 1 ) and ( code == 302 ) ) then
			local newLocation = headers[ "location" ]
			debug( "Call : " .. newLocation, "API.refreshToken" )
			responseBody = {}
			b, code, headers = https.request( {
				url = newLocation,
				method = "GET",
				sink = ltn12.sink.table( responseBody ),
				redirect = false
			})
			debug( "Response headers:" .. json.encode( headers ), "API.refreshToken" )
		end

		local response = table.concat( responseBody or {} )
		debug( "Response b:" .. tostring( b ) .. " - code:" .. tostring( code ) .. " - response:" .. tostring( response ), "API.refreshToken" )
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
			local res, code, headers, status = https.request({
				url = url,
				method = "GET",
				protocol = "tlsv1_2", -- Xee changed recently
				verify = "none", -- Not really good but the Vera seems to not have the root certificate
				headers = {
					["Accept"] = "application/json",
					["Authorization"] = "Bearer " .. tostring( g_params.accessToken )
				},
				sink = ltn12.sink.table( responseBody )
			})
			--debug( "Response headers:" .. json.encode( headers ), "API.request" )

			response = table.concat( responseBody or {} )
			debug( "Response: (result:" .. tostring( res ) .. "),(HTTP code:" .. tostring( code ) .. "),(status:" .. tostring( status ) .. ")", "API.request" )
			if ( res == 1 ) then
				local decodeSuccess, jsonResponse = pcall( json.decode, response )
				if not decodeSuccess then
					error( "(DECODE_ERROR) " .. tostring( jsonResponse ), "API.request" )
				else
					if ( code == 200 ) then
						if ( type( jsonResponse ) == "table" ) then
							data = jsonResponse
							debug( "Data: " .. json.encode( data ), "API.request" )
						else
							error( API.errorsToString( jsonResponse ), "API.request" )
						end
						break
					elseif ( code == 401 ) then
						if ( jsonResponse.error == "token_expired" ) then
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
							isAuthentificationError = true
						end
					elseif ( code == 403 ) then
						if API.hasError( jsonResponse, "token_expired" ) then
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
						break
					end
				end
			else
				error( "(HTTP_ERROR) code:" .. tostring( code ) .. ", response:\"" .. tostring( response ) .. "\"", "API.request" )
			end
			if ( ( data == nil ) and not isAuthentificationError and not isAuthorizationError ) then
				nbTry = nbTry + 1
				if ( nbTry <= g_params.nbMaxTry ) then
					luup.sleep( MIN_INTERVAL_BETWEEN_REQUESTS * 1000 )
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
		else
			UI.clearError()
			Variable.set( g_parentDeviceId, VARIABLE.COMM_FAILURE, "0" )
		end
		return data
	end,

	-- Get the user infos
	getUserInfos = function()
		local data = API.request( "/users/me" )
		if ( data ~= nil ) then
			return data.id, data.firstName, data.lastName
		else
			return nil
		end
	end,

	-- Get the vehicles of the user
	getVehicles = function()
		return API.request( "/users/me/vehicles" )
	end,

	-- Get the status of a vehicle
	getVehicleStatus = function( vehicleId )
		return API.request( "/vehicles/" .. tostring( vehicleId ) .. "/status" )
	end,

	-- Get the signals history of a vehicle
	getVehicleSignals = function( vehicleId, name )
		--return API.request( "/vehicles/" .. tostring( vehicleId ) .. "/signals" .. ( name and ( "?name=" .. name ) or "" ) )
		return API.request( "/vehicles/" .. tostring( vehicleId ) .. "/signals?from=" .. API.convertTimestampToDate( os.time() - 120 ) .. ( name and ( "&signals=" .. name ) or "" ) )
	end
}

-- **************************************************
-- User
-- **************************************************

User = {
	-- Synchronise with Xee Cloud
	sync = function()
		g_params.userId, g_params.userFirstName, g_params.userLastName = API.getUserInfos()
		Variable.set( g_parentDeviceId, VARIABLE.FIRST_NAME, g_params.userFirstName or "" )
		Variable.set( g_parentDeviceId, VARIABLE.LAST_NAME, g_params.userLastName or "" )
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
	tostring = function( point )
		return string.format( "%g;%g", point.latitude, point.longitude )
	end,

	getDistance = function( p1, p2 )
		local x1, x2 = tonumber( p1.longitude ), tonumber( p2.longitude )
		local y1, y2 = tonumber( p1.latitude ),  tonumber( p2.latitude )
		local z1, z2 = tonumber( p1.altitude ),  tonumber( p2.altitude )
		local dx = ( x2 - x1 ) * pi_180_earth_radius * math.cos( ( y2 + y1 ) * pi_360 )
		local dy = ( y2 - y1 ) * pi_180_earth_radius
		local dz = z1 and z2 and ( z2 - z1 ) or 0
		local distance = math.ceil( ( dx*dx + dy*dy + dz*dz ) ^ 0.5 )
		--assert (dx*dx+dy*dy+dz*dz >= 0)
		--assert ((dx*dx+dy*dy+dz*dz)^0.5 >= 0)
		--debug( string.format( "Found a distance of %dm between %s and %s", distance, Geoloc.tostring( p1 ), Geoloc.tostring( p2 ) ), "Geoloc.getDistance" )
		return distance
	end
}


-- Home;50.00;0.0;1000|{{name}};{{latitude}};{{longitude}};{{radius}}
g_geofences = {}

Geofences = {
	get = function( mainDeviceId )
		local strGeofences = Variable.get( mainDeviceId, VARIABLE.GEOFENCES )
		g_geofences = {}
		for _, strGeofence in ipairs( string_split( strGeofences, "|" ) ) do
			local geoParams = string_split( strGeofence, ";" )
			table.insert( g_geofences, {
				name      = geoParams[1],
				latitude  = tonumber( geoParams[2] ),
				longitude = tonumber( geoParams[3] ),
				radius    = tonumber( geoParams[4] or 1000 ) or 1000
			} )
		end
		debug( "Geofences : " .. json.encode( g_geofences ), "Geofences.load")
	end,

	set = function( mainDeviceId, geofences )
		if ( type( geofences ) ~= "table" ) then
			return false, "geofences are empty"
		end
		local strGeofences = ""
		local isOk, strError = true, nil
		for i, geofence in ipairs( geofences ) do
			if ( i > 1 ) then
				strGeofences = strGeofences .. "|"
			end
			if ( geofence.name and geofence.latitude and geofence.longitude and geofence.radius ) then
				strGeofences = strGeofences ..
							tostring( geofence.name ) ..
						";" .. tostring( geofence.latitude ) ..
						";" .. tostring( geofence.longitude ) ..
						";" .. tostring( geofence.radius )
			else
				isOk = false
				strError = "Geofence format error"
				break
			end
		end
		if isOk then
			Variable.set( mainDeviceId, VARIABLE.GEOFENCES, strGeofences )
			Geofences.get( mainDeviceId )
		end
		return isOk, strError
	end,

	update = function( deviceId )
		if ( #g_geofences == 0 ) then
			debug( "No geofence", "Geofences.update")
			return false
		end
		local location = {
			latitude = Variable.get( deviceId, VARIABLE.LOCATION_LATITUDE ),
			longitude = Variable.get( deviceId, VARIABLE.LOCATION_LONGITUDE )
		}
		local distances = {}
		local zoneIdsIn = string_split( ( Variable.getOrInit( deviceId, VARIABLE.GEOFENCE_ZONE_IDS_IN, "" ) or "" ) , ";", tonumber )
		local zoneIdsEnter, zoneIdsExit = {}, {}
		local somethingHasChanged = false
		for zoneId, geofence in ipairs( g_geofences ) do
			local distance = Geoloc.getDistance( location, geofence )
			local wasIn, posIn = table_contains( zoneIdsIn, zoneId )
			if ( distance <= geofence.radius ) then
				-- Device is in the zone
				if not wasIn then
					debug( "Device #" .. tostring( deviceId ) .. " enters the zone #" .. zoneId .. " '" ..  geofence.name .. "'", "Geofences.update")
					table.insert( zoneIdsIn, zoneId )
					table.insert( zoneIdsEnter, zoneId )
					somethingHasChanged = true
				end
			else
				-- Device is not in the zone
				if wasIn then
					debug( "Device #" .. tostring( deviceId ) .. " exits the zone #" .. zoneId .. " '" ..  geofence.name .. "'", "Geofences.update")
					table.remove( zoneIdsIn, posIn )
					table.insert( zoneIdsExit, zoneId )
					somethingHasChanged = true
				end
			end
			table.insert( distances, { geofence.name, distance } )
		end
		
		debug( "Device #" .. tostring( deviceId ) .. " zoneIdsIn #" .. table.concat( zoneIdsIn, ";" ), "Geofences.update")
		debug( "Device #" .. tostring( deviceId ) .. " zoneIdsExit #" .. table.concat( zoneIdsExit, ";" ), "Geofences.update")
		
		if somethingHasChanged then
			table.sort( zoneIdsIn )
			Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_IDS_IN, table.concat( zoneIdsIn, ";" ) )
			local zonesIn = {}
			for _, zoneId in ipairs( zoneIdsIn ) do
				table.insert( zonesIn, g_geofences[zoneId].name )
			end
			Variable.set( deviceId, VARIABLE.GEOFENCE_ZONES_IN, table.concat( zonesIn, ";" ) )

			if ( #zoneIdsEnter > 0 ) then
				table.sort( zoneIdsEnter )
				Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_ID_ENTER, zoneIdsEnter[ 1 ] )
				Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_ENTER, g_geofences[ zoneIdsEnter[ 1 ] ].name )
				debug( "Device #" .. tostring( deviceId ) .. " enters zone " .. g_geofences[ zoneIdsEnter[ 1 ] ].name, "Geofences.update")
			else
				Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_ID_ENTER, "" )
				Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_ENTER, "" )
			end

			if ( #zoneIdsExit > 0 ) then
				table.sort( zoneIdsExit )
				Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_ID_EXIT, zoneIdsExit[ 1 ] )
				Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_EXIT, g_geofences[ zoneIdsExit[ 1 ] ].name )
				debug( "Device #" .. tostring( deviceId ) .. " exists zone " .. g_geofences[ zoneIdsExit[ 1 ] ].name, "Geofences.update")
			else
				Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_ID_EXIT, "" )
				Variable.set( deviceId, VARIABLE.GEOFENCE_ZONE_EXIT, "" )
			end

			-- Pulse
			--luup.sleep( 200 )
			
			
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
		Variable.set( deviceId, VARIABLE.GEOFENCE_DISTANCES, strDistances )
		-- Get the distance of the main zone (first)
		Variable.set( deviceId, VARIABLE.GEOFENCE_DISTANCE, distances[1][2] )
	end,

	getDistances = function( location )
		local distances = {}
		for _, geofence in ipairs( g_geofences ) do
			table.insert( distances, { geofence.name, Geoloc.getDistance( location, geofence ) } )
		end
		return distances
	end,

	getDistancesToString = function( location )
		local strDistances = ""
		for i, distance in ipairs( Geofences.getDistances( location ) ) do
			if ( i > 1 ) then
				strDistances = strDistances .. "|"
			end
			strDistances = strDistances .. table.concat( distance , ";" )
		end
		return strDistances
	end
}


-- **************************************************
-- Vehicles
-- **************************************************

local g_vehicles = {}  -- The list of all our child devices
local g_indexVehicles = {}

Vehicles = {
	-- Synchronise with Xee Cloud
	sync = function()
		debug( "Sync vehicles", "Vehicles.sync" )

		local vehicles = API.getVehicles()
		if ( type( vehicles ) ~= "table" ) then
			return false
		end

		-- Retrieve already created vehicles
		local knownVehicles = {}
		for deviceId, device in pairs( luup.devices ) do
			if ( device.device_num_parent == g_parentDeviceId ) then
				knownVehicles[ tostring( device.id ) ] = true
			end
		end

		-- http://wiki.micasaverde.com/index.php/Luup_Lua_extensions#Module:_luup.chdev
		local ptr = luup.chdev.start( g_parentDeviceId )

		for _, vehicle in ipairs( vehicles ) do
			local vehicleId = tostring( vehicle.id )
			if ( knownVehicles[ vehicleId ] ) then
				-- Already known vehicle - Keep it
				debug( "Keep vehicle #" .. vehicleId, "Vehicles.sync" )
				luup.chdev.append( g_parentDeviceId, ptr, vehicleId, "", "", "", "", "", false )
			else
				debug( "Add vehicle #" .. vehicleId .. " - " .. json.encode( vehicle ), "Vehicles.sync" )
				local parameters = ""
				for _, param in ipairs( {
					{ "COMM_FAILURE", "0" },
					{ "COMM_FAILURE_TIME", "0" },
					{ "VEHICLE_STATUS", "1" },
					{ "VEHICLE_NAME", vehicle.name },
					{ "VEHICLE_MAKE", vehicle.make },
					{ "VEHICLE_MODEL", vehicle.model },
					{ "VEHICLE_DEVICE_ID", vehicle.device.id },
					{ "VEHICLE_CREATION_DATE", API.convertDateToTimestamp( vehicle.createdAt ) },
					{ "VEHICLE_LAST_UPDATE_DATE", API.convertDateToTimestamp( vehicle.updatedAt ) }
				} ) do
					parameters = parameters .. VARIABLE[param[1]][1] .. "," .. VARIABLE[param[1]][2] .. "=" .. tostring( param[2] or "" ) .. "\n"
				end
				luup.chdev.append(
					g_parentDeviceId, ptr, vehicleId,
					vehicle.name, "", DEVICE_TYPE.XEE_VEHICLE.deviceFile, "",
					parameters,
					false
				)
			end
		end

		debug( "Start sync", "Vehicles.sync" )
		Variable.set( g_parentDeviceId, VARIABLE.LAST_UPDATE_DATE, os.time() )
		luup.chdev.sync( g_parentDeviceId, ptr )
		debug( "End sync", "Vehicles.sync" )

		return true
	end,

	-- Get a list with all our vehicle devices.
	retrieve = function()
		g_vehicles = {}
		g_indexVehicles = {}
		for deviceId, device in pairs( luup.devices ) do
			if ( device.device_num_parent == g_parentDeviceId ) then
				local vehicleId = tostring( device.id or "" )
				if ( vehicleId == "" ) then
					debug( "Found child device #".. tostring( deviceId ) .."(".. device.description .."), but vehicleId '" .. tostring( device.id ) .. "' is empty", "Vehicles.retrieve" )
				else
					local vehicle = g_indexVehicles[ vehicleId ]
					if ( vehicle == nil ) then
						vehicle = {
							id = vehicleId,
							name = device.description,
							deviceId = deviceId,
							status = {},
							lastUpdate = 0,
							nextPollDate = 0
						}
						table.insert( g_vehicles, vehicle )
						g_indexVehicles[ vehicleId ] = vehicle
						debug( "Found vehicle #".. vehicleId .."(".. device.description ..")", "Vehicles.retrieve" )
					else
						warning( "Found vehicle #".. vehicleId .. "(".. device.description ..") but it was already registered", "Vehicles.retrieve" )
					end
				end
			end
		end
		if ( #g_vehicles == 0 ) then
			UI.show( "No vehicle" )
		elseif ( #g_vehicles == 1 ) then
			UI.show( "1 vehicle" )
		else
			UI.show( tostring( #g_vehicles ) .. " vehicles"  )
		end
		log( "Vehicles: " .. tostring( #g_vehicles ), "Vehicles.retrieve" )
	end,

	-- Update the informations and signals of a vehicle
	update = function( vehicleId )
		local vehicleId = tostring( vehicleId )
		local vehicle = g_indexVehicles[ vehicleId ]
		if ( vehicle == nil ) then
			warning( "Vehicle #" .. vehicleId .. " is unknown", "Vehicles.update" )
			return false
		end
		debug( "Update vehicle #" .. vehicleId .. "(" .. vehicle.name .. ")", "Vehicles.update" )
		local vehicleStatus = API.getVehicleStatus( vehicleId )
		if ( vehicleStatus ~= nil ) then

			-- Location
			if ( vehicleStatus.location ) then
				Variable.set( vehicle.deviceId, VARIABLE.LOCATION_LATITUDE, vehicleStatus.location.latitude )
				Variable.set( vehicle.deviceId, VARIABLE.LOCATION_LONGITUDE, vehicleStatus.location.longitude )
				Variable.set( vehicle.deviceId, VARIABLE.LOCATION_ALTITUDE, vehicleStatus.location.altitude )
				Variable.set( vehicle.deviceId, VARIABLE.LOCATION_HEADING, vehicleStatus.location.heading )
				Variable.set( vehicle.deviceId, VARIABLE.LOCATION_DATE, API.convertDateToTimestamp( vehicleStatus.location.date ) )
			end

			-- TODO : accelerometer ?

			-- Signals
			if ( vehicleStatus.signals ) then
				local lastUpdate = tonumber(( Variable.get( g_parentDeviceId, VARIABLE.LAST_UPDATE_DATE ) )) or 0
				for _, signal in ipairs( vehicleStatus.signals ) do
					local variableName = "Signal" .. tostring( signal.name )
					local formerValue = luup.variable_get( "urn:upnp-org:serviceId:XeeVehicle1", variableName, vehicle.deviceId ) or ""
					local formerValueDate = luup.variable_get( "urn:upnp-org:serviceId:XeeVehicle1", variableName .. "Date", vehicle.deviceId )
					local timestamp = API.convertDateToTimestamp( signal.date ) or 0
					local hasValueChanged, hasDateChanged = ( formerValue ~= tostring( signal.value ) ), ( formerValueDate ~= tostring( timestamp ) )
					local hasToPulse = false
					if ( hasValueChanged or hasDateChanged ) then
						if ( ( timestamp > lastUpdate ) and string.match( signal.name, ".*Sts$" ) and not hasValueChanged and ( formerValue == "0" ) ) then
							-- Status signal has changed during two poll
							hasValueChanged = true
							signal.value = "1"
							hasToPulse = true
						end
						if ( ( signal.name == "HeadLightSts" ) and hasValueChanged and ( tostring(signal.value) == "1" ) ) then
							-- Check if it is headlight flash
							debug( json.encode(API.getVehicleSignals( vehicleId, "HeadLightSts" )), "Vehicles.update" )
							--debug( json.encode(API.getVehicleSignals( vehicleId )), "Vehicles.update" )

						end
						if hasValueChanged then
							luup.variable_set( "urn:upnp-org:serviceId:XeeVehicle1", variableName, signal.value, vehicle.deviceId )
						end
						if hasDateChanged then
							luup.variable_set( "urn:upnp-org:serviceId:XeeVehicle1", variableName .. "Date", timestamp, vehicle.deviceId )
						end
						if hasToPulse then
							debug( "Pulse signal " ..  signal.name .. " for vehicle #" .. vehicleId, "Vehicles.update" )
							luup.variable_set( "urn:upnp-org:serviceId:XeeVehicle1", variableName, "0", vehicle.deviceId )
						end
					end
				end
			end

			-- Geofences
			if ( vehicleStatus.location ) then
				Geofences.update( vehicle.deviceId )
				vehicleStatus.zonesIn = Variable.get( vehicle.deviceId, VARIABLE.GEOFENCE_ZONES_IN )
			end

			vehicle.lastUpdate = os.time()
			Variable.set( vehicle.deviceId, VARIABLE.VEHICLE_LAST_UPDATE_DATE, vehicle.lastUpdate )
			Variable.set( vehicle.deviceId, VARIABLE.COMM_FAILURE, "0" )
			vehicle.status = vehicleStatus
			return true
		else
			error( "Can not retrieve vehicle #" .. vehicleId .. "(" .. tostring( vehicle.name ) .. ") status", "Vehicles.update" )
			Variable.set( vehicle.deviceId, VARIABLE.COMM_FAILURE, "1" )
			vehicle.status = {}
			return false
		end
	end
}


-- **************************************************
-- Poll engine
-- **************************************************

PollEngine = {
	poll = function()
		log( "Start poll", "PollEngine.poll" )

		local pollInterval = g_params.pollSettings[ 1 ]

		if ( ( #g_vehicles > 0 ) and not ( luup.attr_get( "disabled", g_parentDeviceId ) == 1 ) ) then
			table.sort( g_vehicles, function( vehicle1, vehicle2 )
				return vehicle1.nextPollDate < vehicle2.nextPollDate
			end )

			-- Poll the vehicle that need to be polled first
			if ( os.difftime( g_vehicles[ 1 ].nextPollDate, os.time() ) <= 0 ) then
				if Vehicles.update( g_vehicles[ 1 ].id ) then
					--if ( g_vehicles[ 1 ].distance > XEE_ ) then
					--else
						pollInterval = g_params.pollSettings[ 1 ]
					--end
				else
					-- Use the poll interval defined for errors
					pollInterval = g_params.pollSettings[ 2 ]
				end
				g_vehicles[ 1 ].nextPollDate = os.time() + pollInterval
			end

			if ( #g_vehicles > 1 ) then
				pollInterval = os.difftime( math.min( g_vehicles[ 1 ].nextPollDate, g_vehicles[ 2 ].nextPollDate ), os.time() )
				if ( pollInterval < MIN_INTERVAL_BETWEEN_REQUESTS ) then
					pollInterval = MIN_INTERVAL_BETWEEN_REQUESTS
				end
			end
		end

		debug( "Next poll in " .. tostring( pollInterval ) .. " seconds", "PollEngine.poll" )
		luup.call_delay( "Xee.PollEngine.poll", pollInterval )
	end
}


-- **************************************************
-- HTTP request handler
-- **************************************************

local _handlerCommands = {
	["default"] = function( params, outputFormat )
		return "Unknown command '" .. tostring( params["command"] ) .. "'", "text/plain"
	end,

	["getVehicles"] = function( params, outputFormat )
		return tostring( json.encode( g_vehicles ) ), "application/json"
	end,

	-- DEBUG
	["setVehicleLocation"] = function( params, outputFormat )
		local vehicle = g_indexVehicles[ tostring( params["vehicleId"] ) ]
		vehicle.status.location.latitude = tonumber( params["latitude"] )
		Variable.set( vehicle.deviceId, VARIABLE.LOCATION_LATITUDE, vehicle.status.location.latitude )
		vehicle.status.location.longitude = tonumber( params["longitude"] )
		Variable.set( vehicle.deviceId, VARIABLE.LOCATION_LONGITUDE, vehicle.status.location.longitude )
		Geofences.update( vehicle.deviceId )
		vehicle.status.zonesIn = Variable.get( vehicle.deviceId, VARIABLE.GEOFENCE_ZONES_IN )
		return tostring( json.encode( { result = true } ) ), "application/json"
	end,

	["getGeofences"] = function( params, outputFormat )
		return tostring( json.encode( g_geofences ) ), "application/json"
	end,

	["setGeofences"] = function( params, outputFormat )
		local isOk, strError = true, nil
		local jsonGeofences = Url.unescape( params["newGeofences"] or "" )
		local decodeSuccess, geofences, _, jsonError = pcall( json.decode, jsonGeofences )
		if ( decodeSuccess and geofences ) then
			isOk, strError = Geofences.set( g_parentDeviceId, geofences )
		else
			isOk, strError = false, "JSON error: " .. tostring( jsonError )
		end
		if isOk then
			for _, vehicle in ipairs( g_vehicles ) do
				vehicle.status.zonesIn = ""
			end
		end
		return tostring( json.encode( { result = isOk, ["error"] = strError } ) ), "application/json"
	end,

	["getMap"] = function( params, outputFormat )
		local template = tostring( MAP_TEMPLATE )
		template = string.gsub( template, "%$latitude", tostring(luup.latitude) )
		template = string.gsub( template, "%$longitude", tostring(luup.longitude) )
		return template, "text/html"
	end,

	["getErrors"] = function( params, outputFormat )
		return tostring( json.encode( g_errors ) ), "application/json"
	end,

	["setTokens"] = function( params, outputFormat )
		if params.result then
			local result = string_decodeURI( params.result )
			local strError = API.errorsToString( result )
			if not string_isEmpty( strError ) then
				return "There's a problem:<br/>" .. strError, "text/html"
			else
				API.setTokens( result )
				return "The authorization tokens have been saved in your Home Automation System.<br/>They will be used at the next automatic refresh, or you can force the refresh by clicking on the button \"Sync\" in the \"Vehicles\" tab.<br/><br/>You can close this window.", "text/html"
			end
		else
			return "Nothing has been done. You can close this window.", "text/html"
		end
	end
}
setmetatable( _handlerCommands,{
	__index = function( t, command, outputFormat )
		log( "No handler for command '" ..  tostring( command ) .. "'", "handlerXee")
		return _handlerCommands["default"]
	end
} )

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
		User.sync()
	end
end

function sync()
	Vehicles.sync()
	Vehicles.retrieve()
end


-- **************************************************
-- Startup
-- **************************************************

-- Init plugin instance
local function _initPluginInstance()
	log( "Init", "initPluginInstance" )

	-- Update the Debug Mode
	local debugMode = ( Variable.getOrInit( g_parentDeviceId, VARIABLE.DEBUG_MODE, "0" ) == "1" ) and true or false
	if debugMode then
		log( "DebugMode is enabled", "init" )
		debug = log
	else
		log( "DebugMode is disabled", "init" )
		debug = function() end
	end

	Variable.set( g_parentDeviceId, VARIABLE.PLUGIN_VERSION, _VERSION )
	Variable.set( g_parentDeviceId, VARIABLE.LAST_MESSAGE, "" )
	Variable.set( g_parentDeviceId, VARIABLE.LAST_ERROR, "" )
	Variable.getOrInit( g_parentDeviceId, VARIABLE.FIRST_NAME, "" )
	Variable.getOrInit( g_parentDeviceId, VARIABLE.LAST_NAME, "" )
	-- Get plugin params
	g_params.accessToken = Variable.getOrInit( g_parentDeviceId, VARIABLE.ACCESS_TOKEN, "" )
	g_params.refreshToken = Variable.getOrInit( g_parentDeviceId, VARIABLE.REFRESH_TOKEN, "" )
	g_params.tokenExpirationDate = Variable.getOrInit( g_parentDeviceId, VARIABLE.TOKEN_EXPIRATION_DATE, "" )
	g_params.pollSettings = string_split( Variable.getOrInit( g_parentDeviceId, VARIABLE.POLL_SETTINGS, "60,700,700" ), ",", tonumber )
	if ( ( g_params.pollSettings[ 1 ] or 0 ) < MIN_POLL_INTERVAL ) then
		g_params.pollSettings[ 1 ] = MIN_POLL_INTERVAL
	end
	if ( ( g_params.pollSettings[ 2 ] or 0 ) < MIN_POLL_INTERVAL_AFTER_ERROR ) then
		g_params.pollSettings[ 2 ] = MIN_POLL_INTERVAL_AFTER_ERROR
	end
	if ( ( g_params.pollSettings[ 3 ] or 0 ) < MIN_POLL_INTERVAL_FAR_AWAY ) then
		g_params.pollSettings[ 3 ] = MIN_POLL_INTERVAL_FAR_AWAY
	end

	-- Geofences
	local defaultGeoFence = "Home;" .. luup.latitude .. ";" .. luup.longitude .. ";1000"
	Variable.getOrInit( g_parentDeviceId, VARIABLE.GEOFENCES, defaultGeoFence )
	Geofences.get( g_parentDeviceId )

	-- Vera location
	g_params.location = {
		latitude = luup.latitude,
		longitude = luup.longitude
	}
end

-- Register with ALTUI once it is ready
local function _registerWithALTUI()
	for deviceId, device in pairs( luup.devices ) do
		if ( device.device_type == "urn:schemas-upnp-org:device:altui:1" ) then
			if luup.is_ready( deviceId ) then
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
						newDeviceType = "urn:schemas-upnp-org:device:XeeVehicle:1",
						newScriptFile = "J_Xee1.js",
						newDeviceDrawFunc = "Xee.ALTUI_drawXeeVehicleDevice"
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
	-- Sync with Xee cloud
	User.sync()
	local result = Vehicles.sync()
	Vehicles.retrieve()

	if result then
		PollEngine.poll()
	else
		luup.call_delay( "Xee.PollEngine.poll", MIN_POLL_INTERVAL_AFTER_ERROR )
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

	-- Init
	_initPluginInstance()
	-- Watch setting changes
	Variable.watch( g_parentDeviceId, VARIABLE.DEBUG_MODE, "Xee.initPluginInstance" )
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
_G["Xee.PollEngine.poll"] = PollEngine.poll

_G["Xee.deferredStartup"] = _deferredStartup
_G["Xee.initPluginInstance"] = _initPluginInstance
_G["Xee.registerWithALTUI"] = _registerWithALTUI
