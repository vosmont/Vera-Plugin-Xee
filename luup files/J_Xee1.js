//# sourceURL=J_Xee1.js

/**
 * This file is part of the plugin Xee.
 * https://github.com/vosmont/Vera-Plugin-Xee
 * Copyright (c) 2019 Vincent OSMONT
 * This code is released under the MIT License, see LICENSE.
 */


( function( $ ) {
	// UI7 fix
	Utils.getFullDataRequestURL = function() {
		var dataRequestURL = api.getDataRequestURL();
		if ( dataRequestURL.indexOf( "http" ) === -1 ) {
			var protocol = document.location.protocol;
			var host = document.location.hostname;
			var httpPort = document.location.port;
			var topUrl = protocol + '//' + host + ( ( httpPort != 80 && httpPort != '' ) ? ':' + httpPort : '' );
			dataRequestURL = topUrl + dataRequestURL;
		}
		/*
		if ( dataRequestURL.indexOf( "?" ) === -1 ) {
			dataRequestURL += "?";
		}
		*/
		return dataRequestURL;
	};
	// Custom CSS injection
	Utils.injectCustomCSS = function( nameSpace, css ) {
		if ( $( "#custom-css-" + nameSpace ).length === 0 ) {
			Utils.logDebug( "Injects custom CSS for " + nameSpace );
			var pluginStyle = $( '<style id="custom-css-' + nameSpace + '">' );
			pluginStyle
				.text( css )
				.appendTo( "head" );
		} else {
			Utils.logDebug( "Injection of custom CSS has already been done for " + nameSpace );
		}
	};
	Utils.performActionOnDevice = function( deviceId, service, action, actionArguments ) {
		var d = $.Deferred();
		try {
			if ( $.isPlainObject( actionArguments ) ) {
				$.each( actionArguments, function( key, value ) {
					if ( !value ) {
						delete actionArguments[ key ];
					}
				});
			}
			api.performActionOnDevice( deviceId, service, action, {
				actionArguments: actionArguments,
				onSuccess: function( response ) {
					var result;
					try {
						result = JSON.parse( response.responseText );
					} catch( err ) {
					}
					if ( !$.isPlainObject( result )
						|| !$.isPlainObject( result[ "u:" + action + "Response" ] )
						|| (
							( result[ "u:" + action + "Response" ].OK !== "OK" )
							&& ( result[ "u:" + action + "Response" ].JobID === undefined )
						)
					) {
						Utils.logError( "[Utils.performActionOnDevice] ERROR on action '" + action + "': " + response.responseText );
						d.reject();
					} else {
						d.resolve();
					}
				},
				onFailure: function( response ) {
					Utils.logError( "[Utils.performActionOnDevice] ERROR(" + response.status + "): " + response.responseText );
					d.reject();
				}
			} );
		} catch( err ) {
			Utils.logError( "[Utils.performActionOnDevice] ERROR: " + JSON.parse( err ) );
			d.reject();
		}
		return d.promise();
	};
} ) ( jQuery );


var Xee = ( function( api, $ ) {
	var _uuid = "fba503c3-b3f9-478e-a99e-26fa25cbba68";
	var XEE_SID = "urn:upnp-org:serviceId:Xee1";
	var XEE_DID = "urn:schemas-upnp-org:device:Xee:1";
	var XEE_VEHICLE_SID = "urn:upnp-org:serviceId:XeeVehicle1";
	var XEE_VEHICLE_DID = "urn:schemas-upnp-org:device:XeeVehicle:1";
	var XEE_CLIENT_ID = "72b109c6eafcf052e2fba8155656c4d6";
	var XEE_AUTH_URL = "https://api.xee.com/v4/oauth/authorize";
	var XEE_SCOPE = [ "account.read", "vehicles.read", "vehicles.locations.read", "vehicles.signals.read" ];
	var REDIRECT_URI = "https://script.google.com/macros/s/AKfycbyAIrB1IFq0GhitEUu1kH_Agy1bUlaX5CDpI7U-XtAVcJeScYLg/exec";
	var _deviceId = null;
	var _registerIsDone = false;
	var _lastUpdate = 0;

	var _terms = {
		"ExplanationAuthentification": "\
The connection to Xee Cloud is made by OAuth2 mechanism.<br/>\
When you inform your identifier/passord in the form provided by Xee (the company), you delegate your authentification to the Xee plugin (in your Vera), which then has the authorization to acces to the informations of your Xee account.<br/>\
<br/>\
As Oauth2 protocol is not implemented in the Vera, the plugin uses a third-part server :<br/>\
- This server is a Google Apps Script (code available with the plugin sources).<br/>\
- The access and refresh tokens are not stored somewhere else that in your Vera.<br/>\
- Calls to that webservice are recorded, but your privacy is respected (see sources).",
		"AuthorizationSaved": "\
The authorization tokens have been saved.<br/>\
They will be used at the next automatic refresh, or you can force the refresh by clicking on the button \"Sync\" in the \"Vehicles\" tab.",
		"ExplanationSyncingVehicles": "\
The list of the vehicules bound to your Xee account is refreshed :<br/>\
- At each restart of the luup engine.<br/>\
- When you press the button \"Sync\".<br/>\
The refresh of the list can lead to a restart of the luup engine.<br/>\
<br/>\
Signals and position of each vehicule are periodically updated. This refresh interval depends on :<br/>\
- If an error has been raised during the last update.<br/>\
- Distance from your home (TODO).<br/>\
",
		"SyncingVehicles": "\
Vehicles have been synchronized with your Xee account...<br/>\
... wait until the reload of Luup engine",
		"ExplanationMap": "\
This map shows your vehicles and the geofences.<br/>\
You can add/delete/move the geofences.",
		"NoVehicle": "\
There's no vehicle bound to your Xee account.",
		"NoError": "\
There's no error."
	};

	function _T( t ) {
		var v =_terms[ t ];
		if ( v ) {
			return v;
		}
		return t;
	}

	// Inject plugin specific CSS rules
	// http://www.utf8icons.com/
	Utils.injectCustomCSS( "xee", '\
.xee-panel { padding: 5px; }\
.xee-panel label { font-weight: normal }\
.xee-panel td { padding: 5px; }\
.xee-panel .icon { vertical-align: middle; }\
.xee-panel .icon.big { vertical-align: sub; }\
.xee-panel .icon:before { font-size: 15px; }\
.xee-panel .icon.big:before { font-size: 30px; }\
.xee-panel .icon-help:before { content: "\\2753"; }\
.xee-panel .icon-refresh:before { content: "\\267B"; }\
.xee-panel .icon-map:before { content: "\\25F1"; }\
.xee-hidden { display: none; }\
.xee-error { color:red; }\
.xee-header { margin-bottom: 15px; font-size: 1.1em; font-weight: bold; }\
.xee-explanation { margin: 5px; padding: 5px; border: 1px solid; background: #FFFF88}\
.xee-toolbar { height: 25px; text-align: right; }\
.xee-toolbar button { display: inline-block; }\
.xee-step { padding-bottom: 10px; }\
#xee-map { width: 100%; height: 600px; margin: 10px 0px; }\
#xee-authentification-params { width: 80%; }\
#xee-donate { text-align: center; width: 70%; margin: auto; }\
#xee-donate form { height: 50px; }\
	');

	// *************************************************************************************************
	// Tools
	// *************************************************************************************************

	/**
	 * Convert a unix timestamp into date
	 */
	function _convertTimestampToLocaleString( timestamp ) {
		if ( typeof( timestamp ) === "undefined" ) {
			return "";
		}
		var t = new Date( parseInt( timestamp, 10 ) * 1000 );
		var localeString = t.toLocaleString();
		return localeString;
	}
	function _convertTimestampToIsoString( timestamp ) {
		if ( typeof( timestamp ) === "undefined" ) {
			return "";
		}
		var t = new Date( parseInt( timestamp, 10 ) * 1000 );
		var isoString = t.toISOString();
		return isoString;
	}

	// *************************************************************************************************
	// Authentification
	// *************************************************************************************************

	/**
	 * Show authentification tab
	 */
	function _login() {
		var userData = api.getUserData();
		var haUrl = Utils.getFullDataRequestURL();
		var url = XEE_AUTH_URL
			+ "?client_id=" + XEE_CLIENT_ID
			+ "&response_type=code"
			+ "&scope=" + encodeURIComponent( XEE_SCOPE.join( " " ) )
			+ "&redirect_uri=" + encodeURIComponent( REDIRECT_URI )
			+ "&state=" + ( haUrl.startsWith( "https" ) ? encodeURIComponent( haUrl ) : '' );
		var win = window.open( url, "xee_authentification", "width=620, height=740" ); 
	}
	function _showAuthentification( deviceId ) {
		_deviceId = deviceId;
		try {
			var html = '<div id="xee-authentification-panel" class="xee-panel">'
				+		'<div class="xee-toolbar">'
				+			'<button type="button" class="xee-help"><span class="icon icon-help"></span>Help</button>'
				+		'</div>'
				+		'<div class="xee-explanation xee-hidden">'
				+			_T( "ExplanationAuthentification" )
				+		'</div>'
				+		'<div id="xee-authentification">';
			var haUrl = Utils.getFullDataRequestURL();
			if ( haUrl.startsWith( "https" ) ) {
				html += 	'<div class="xee-step">'
					+			'Open the <a href="#" class="xee-login">Xee authentification page</a> and use your Xee account.'
					+		'</div>'
			} else {
				// Changing from https to http is not allowed by browsers
				html +=		'<div class="xee-step">'
					+			'1/ Open the <a href="#" class="xee-login">Xee authentification page</a> and use your Xee account'
					+		'</div>'
					+		'<div class="xee-step">'
					+			'2/ Copy the result and validate'
					+			'<input type="text" id="xee-authentification-params">'
					+			'<button type="button" id="xee-authentification-set">Set</button>'
					+		'</div>';
			}
			html +=		'</div>';
			api.setCpanelContent( html );

			// Manage UI events
			$( "#xee-authentification-panel" )
				.on( "click", ".xee-help" , function() {
					$( ".xee-explanation" ).toggleClass( "xee-hidden" );
				})
				.on( "click", ".xee-login" , function() {
					_login();
					return false;
				})
				.on( "click", "#xee-authentification-set" , function() {
					_performActionSetTokens( $( "#xee-authentification-params" ).val() );
					$( "#xee-authentification" ).html( _T( "AuthorizationSaved" ) );
				});
		} catch (err) {
			Utils.logError('Error in Xee.showAuthentification(): ' + err);
		}
	}

	// *************************************************************************************************
	// Vehicles
	// *************************************************************************************************

	/**
	 * Get informations on vehicles
	 */
	function _getVehiclesAsync() {
		var d = $.Deferred();
		api.showLoadingOverlay();
		$.ajax( {
			url: Utils.getFullDataRequestURL() + "?id=lr_Xee&command=getVehicles&output_format=json#",
			dataType: "json"
		} )
		.done( function( vehicles ) {
			//console.info(vehicles);
			api.hideLoadingOverlay();
			if ( $.isArray( vehicles ) ) {
				d.resolve( vehicles );
			} else {
				Utils.logError( "No vehicle" );
				d.reject();
			}
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			api.hideLoadingOverlay();
			Utils.logError( "Get vehicles error : " + errorThrown );
			d.reject();
		} );
		return d.promise();
	}

	/**
	 * Draw and manage vehicles list
	 */
	function _drawVehiclesList() {
		if ( $( "#xee-vehicles" ).length === 0 ) {
			return;
		}
		$.when( _getVehiclesAsync() )
			.done( function( vehicles ) {
				if ( vehicles.length > 0 ) {
					var html =	'<table><tr><th>Id</th><th>Name</th><th>Last update</th></tr>';
					$.each( vehicles, function( i, vehicle ) {
						html +=	'<td>'
							+		vehicle.id
							+	'</td>'
							+	'<td>'
							+		vehicle.name
							+	'</td>'
							+	'<td>'
							+		_convertTimestampToLocaleString( vehicle.lastUpdate )
							+	'</td>'
							+ '</tr>';
					} );
					html += '</table>';
					$("#xee-vehicles").html( html );
				} else {
					$("#xee-vehicles").html( _T( "NoVehicle" ) );
				}
			} );
	}

	/**
	 * Show vehicles tab
	 */
	function _showVehicles( deviceId ) {
		_deviceId = deviceId;
		try {
			api.setCpanelContent(
					'<div id="xee-vehicles-panel" class="xee-panel">'
				+		'<div class="xee-toolbar">'
				+			'<button type="button" class="xee-help"><span class="icon icon-help"></span>Help</button>'
				+			'<button type="button" class="xee-sync"><span class="icon icon-refresh"></span>Sync</button>'
				+		'</div>'
				+		'<div class="xee-explanation xee-hidden">'
				+			_T( "ExplanationSyncingVehicles" )
				+		'</div>'
				+		'<div id="xee-vehicles">'
				+		'</div>'
				+	'</div>'
			);
			// Manage UI events
			$( "#xee-vehicles-panel" )
				.on( "click", ".xee-help" , function() {
					$( ".xee-explanation" ).toggleClass( "xee-hidden" );
				} )
				.on( "click", ".xee-sync", function() {
					$( "#xee-vehicles" ).html( _T( "SyncingVehicles" ) );
					_performActionSync();
				} );
			// Display the vehicles
			_drawVehiclesList();
		} catch ( err ) {
			Utils.logError( "Error in Xee.showVehicles(): " + err );
		}
	}

	// *************************************************************************************************
	// Map
	// *************************************************************************************************

	function _showMap( deviceId ) {
		_deviceId = deviceId;
		try {
			var isDebug = (api.getDeviceStateVariable(_deviceId, "urn:upnp-org:serviceId:Xee1", "DebugMode", {dynamic: false}) === "1");
			api.setCpanelContent(
					'<div id="xee-map-panel" class="xee-panel">'
				+		'<div class="xee-toolbar">'
				+			'<button type="button" class="xee-help"><span class="icon icon-help"></span>Help</button>'
				+			'<button type="button" class="xee-big-map"><span class="icon icon-map"></span>Big map</button>'
				+		'</div>'
				+		'<div class="xee-explanation xee-hidden">'
				+			_T( "ExplanationMap" )
				+		'</div>'
				+		'<iframe id="xee-map"src="' + Utils.getFullDataRequestURL() + '?id=lr_Xee&command=getMap' + ( isDebug ? "&debug=true": "") + '"></iframe>'
				+	'</div>'
			);
			// Manage UI events
			$( "#xee-map-panel" )
				.on( "click", ".xee-help" , function() {
					$( ".xee-explanation" ).toggleClass( "xee-hidden" );
				} )
				.on( "click", ".xee-big-map" , function() {
					var isDebug = (api.getDeviceStateVariable(_deviceId, "urn:upnp-org:serviceId:Xee1", "DebugMode", {dynamic: false}) === "1");
					var win = window.open( Utils.getFullDataRequestURL() + "?id=lr_Xee&command=getMap" + ( isDebug ? "&debug=true": ""), "_blank" );
					if ( win ) {
						win.focus();
					}
				} );
		} catch ( err ) {
			Utils.logError( "Error in Xee.showMap(): " + err );
		}
	}

	// *************************************************************************************************
	// Errors
	// *************************************************************************************************

	/**
	 * Get errors
	 */
	function _getErrorsAsync() {
		var d = $.Deferred();
		api.showLoadingOverlay();
		$.ajax( {
			url: Utils.getFullDataRequestURL() + "?id=lr_Xee&command=getErrors&output_format=json#",
			dataType: "json"
		} )
		.done( function( errors ) {
			api.hideLoadingOverlay();
			if ( $.isArray( errors ) ) {
				d.resolve( errors );
			} else {
				Utils.logError( "No errors" );
				d.reject();
			}
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			api.hideLoadingOverlay();
			Utils.logError( "Get errors error : " + errorThrown );
			d.reject();
		} );
		return d.promise();
	}

	/**
	 * Draw errors list
	 */
	function _drawErrorsList() {
		if ( $( "#xee-errors" ).length === 0 ) {
			return;
		}
		$.when( _getErrorsAsync() )
			.done( function( errors ) {
				if ( errors.length > 0 ) {
					var html = '<table><tr><th>Date</th><th>Error</th></tr>';
					$.each( errors, function( i, error ) {
						html += '<tr>'
							+		'<td>' + _convertTimestampToLocaleString( error[0] ) + '</td>'
							+		'<td>' + error[1] + '</td>'
							+	'</tr>';
					} );
					html += '</table>';
					$( "#xee-errors" ).html( html );
				} else {
					$( "#xee-errors" ).html( _T( "NoError" ) );
				}
			} );
	}

	/**
	 * Show errors tab
	 */
	function _showErrors( deviceId ) {
		_deviceId = deviceId;
		try {
			api.setCpanelContent(
					'<div id="xee-errors-panel" class="xee-panel">'
				/*+		'<div class="xee-toolbar">'
				+			'<button type="button" class="xee-help"><span class="icon icon-help"></span>Help</button>'
				+		'</div>'
				+		'<div class="xee-explanation xee-hidden">'
				+			_T( "Explanation for errors" )
				+		'</div>'*/
				+		'<div id="xee-errors">'
				+		'</div>'
				+	'</div>'
			);
			// Manage UI events
			/*$( "#xee-errors-panel" )
				.on( "click", ".xee-help" , function() {
					$( ".xee-explanation" ).toggleClass( "xee-hidden" );
				} );*/
			// Display the errors
			_drawErrorsList();
		} catch ( err ) {
			Utils.logError( "Error in Xee.showErrors(): " + err );
		}
	}

	// *************************************************************************************************
	// Vehicle (child)
	// *************************************************************************************************

	/**
	 * Show vehicle tab
	 */
	function _showVehicle( childDeviceId ) {
		try {
			api.setCpanelContent(
					'<div id="xee-vehicle">'
				+		'TODO'
				+	'</div>'
			);
		} catch (err) {
			Utils.logError('Error in Xee.showVehicle(): ' + err);
		}
	}

	// *************************************************************************************************
	// Actions
	// *************************************************************************************************

	/**
	 * Set tokens
	 */
	function _performActionSetTokens( params ) {
		Utils.logDebug( "[Xee.performActionSetTokens] Set tokens '" + params + "'" );
		return Utils.performActionOnDevice(
			_deviceId, XEE_SID, "SetTokens", {
				output_format: "json",
				newTokens: params
			}
		)
	}

	/**
	 * Synchronize with Xee Cloud
	 */
	function _performActionSync() {
		Utils.logDebug( "[Xee.performActionSync] Sync vehicles" );
		return Utils.performActionOnDevice(
			_deviceId, XEE_SID, "Sync", {
				output_format: "json"
			}
		)
	}

	// *************************************************************************************************
	// Donate
	// *************************************************************************************************

	function _showDonate( deviceId ) {
		var donateHtml = '\
<form action="https://www.paypal.com/cgi-bin/webscr" method="post" target="_blank">\
<input type="hidden" name="cmd" value="_s-xclick">\
<input type="hidden" name="encrypted" value="-----BEGIN PKCS7-----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-----END PKCS7-----\
">\
<input type="image" src="https://www.paypalobjects.com/en_US/FR/i/btn/btn_donateCC_LG.gif" border="0" name="submit" alt="PayPal - The safer, easier way to pay online!">\
<img alt="" border="0" src="https://www.paypalobjects.com/fr_FR/i/scr/pixel.gif" width="1" height="1">\
</form>';

		api.setCpanelContent(
				'<div id="xee-donate-panel" class="xee-panel">'
			+		'<div id="xee-donate">'
			+			'<span>This plugin is free but if you install and find it useful then a donation to support further development is greatly appreciated</span>'
			+			donateHtml
			+		'</div>'
			+	'</div>'
		);
	}

	// *************************************************************************************************
	// Zones
	// *************************************************************************************************

	function _getNearestZone( device ) {
		var strDistances = MultiBox.getStatus( device, "urn:upnp-org:serviceId:GeoFence1", "Distances" );
		if ( ( strDistances == null ) || ( strDistances === "" ) ) {
			return;
		}
		var strZonesIn = MultiBox.getStatus( device, "urn:upnp-org:serviceId:GeoFence1", "ZonesIn" );
		var zonesIn = strZonesIn ? strZonesIn.split( ";" ) : [];
		var distances = [];
		$.map( strDistances.split( "|" ), function( strDistance, i ) {
			var params = strDistance.split( ";" );
			if ( params.length > 1 ) {
				distances.push( [ params[0], parseInt( params[1], 10 ), ( $.inArray( params[0], zonesIn ) > -1 ? true : false ) ] );
			}
		} );
		distances.sort( function( d1, d2 ) { return ( d1[1] - d2[1] ) } );
		return distances[ 0 ];
	}

	// *************************************************************************************************
	// ALTUI
	// *************************************************************************************************

	// Device Xee in ALTUI
	function _ALTUI_drawXeeDevice( device ) {
		var version = MultiBox.getStatus( device, "urn:upnp-org:serviceId:Xee1", "PluginVersion" );
		var lastUpdate = parseInt( MultiBox.getStatus( device, "urn:upnp-org:serviceId:Xee1", "LastUpdateDate" ), 10 );
		var lastMessage = MultiBox.getStatus( device, "urn:upnp-org:serviceId:Xee1", "LastMessage" ) || "";
		var lastError = MultiBox.getStatus( device, "urn:upnp-org:serviceId:Xee1", "LastError" ) || "";
		var firstName = MultiBox.getStatus( device, "urn:upnp-org:serviceId:Xee1", "FirstName" ) || "";
		var lastName = MultiBox.getStatus( device, "urn:upnp-org:serviceId:Xee1", "LastName" ) || "";
		return '<div class="panel-content">'
			+		'<div class="small">Updated ' + $.timeago( lastUpdate * 1000 ) + '</div>'
			+		'<div class="small">v' + version + ( firstName || lastName ? ' - ' + firstName + ' ' + lastName : '' ) + ' - ' + lastMessage + '</div>'
			+		'<div>' + lastError + '</div>'
			+	'</div>';
	}

	// Device XeeVehicle in ALTUI
	function _ALTUI_drawXeeVehicleDevice( device ) {
		//var lastUpdate = parseInt( MultiBox.getStatus( device, "urn:upnp-org:serviceId:XeeVehicle1", "LastUpdateDate" ), 10 );
		var locationDate = parseInt( MultiBox.getStatus( device, "urn:upnp-org:serviceId:Location1", "LocationDate" ), 10 );
		var distance = _getNearestZone( device );
		var html = '<div class="panel-content">'
			//+		'<div>Updated ' + $.timeago( lastUpdate * 1000 ) + '</div>'
			//+		'<div>';
		if ( distance ) {
			html +=		'<div class="small">' + ( distance[2] ? '(in) ' : '(out) ' ) + distance[0] + ' @ ' + ( distance[1] > 999 ? ( distance[1] / 1000 ) + 'km' : distance[1] + 'm' ) + '</div>';
			html +=		'<div class="small">' + $.timeago( locationDate * 1000 ) + '</div>'
		}
		html +=		'</div>'
			+	'</div>';
		return html;
	}

	// *************************************************************************************************
	// Main
	// *************************************************************************************************

	/**
	 * Callback on device events
	 */
	function _onDeviceStatusChanged( deviceObjectFromLuStatus ) {
		if ( deviceObjectFromLuStatus.device_type === XEE_DID ) {
			// Update xee panel (ALTUI)
			if ( window.MultiBox ) {
				var device = MultiBox.getDeviceByAltuiID( deviceObjectFromLuStatus.altuiid );
				$( "#" + deviceObjectFromLuStatus.altuiid + " .panel-content" ).html( _ALTUI_drawXeeDevice( device ) );
			}
			// Update vehicles panel
			_drawVehiclesList();
		}
		if ( deviceObjectFromLuStatus.device_type === XEE_VEHICLE_DID ) {
			// Update xee vehicle panel (ALTUI)
			if ( window.MultiBox ) {
				var device = MultiBox.getDeviceByAltuiID( deviceObjectFromLuStatus.altuiid );
				$( "#" + deviceObjectFromLuStatus.altuiid + " .panel-content" ).html( _ALTUI_drawXeeVehicleDevice( device ) );
			}
		}
	}

	myModule = {
		uuid: _uuid,
		onDeviceStatusChanged: _onDeviceStatusChanged,
		showAuthentification: _showAuthentification,
		showVehicles: _showVehicles,
		showMap: _showMap,
		showVehicle: _showVehicle,
		showErrors: _showErrors,
		showDonate: _showDonate,
		//setTokens: _performActionSetTokens,
		setTokens: function(tokens) { console.log(tokens); },

		ALTUI_drawXeeDevice: _ALTUI_drawXeeDevice,
		ALTUI_drawXeeVehicleDevice: _ALTUI_drawXeeVehicleDevice
	};

	// Register
	if ( !_registerIsDone ) {
		api.registerEventHandler( "on_ui_deviceStatusChanged", myModule, "onDeviceStatusChanged" );
		_registerIsDone = true;
	}

	return myModule;

})( api, jQuery );


/**
 * Timeago is a jQuery plugin that makes it easy to support automatically
 * updating fuzzy timestamps (e.g. "4 minutes ago" or "about 1 day ago").
 *
 * @name timeago
 * @version 1.5.2
 * @requires jQuery v1.2.3+
 * @author Ryan McGeary
 * @license MIT License - http://www.opensource.org/licenses/mit-license.php
 *
 * For usage and examples, visit:
 * http://timeago.yarp.com/
 *
 * Copyright (c) 2008-2015, Ryan McGeary (ryan -[at]- mcgeary [*dot*] org)
 */

(function (factory) {
  if (typeof define === 'function' && define.amd) {
    // AMD. Register as an anonymous module.
    define(['jquery'], factory);
  } else if (typeof module === 'object' && typeof module.exports === 'object') {
    factory(require('jquery'));
  } else {
    // Browser globals
    factory(jQuery);
  }
}(function ($) {
  $.timeago = function(timestamp) {
    if (timestamp instanceof Date) {
      return inWords(timestamp);
    } else if (typeof timestamp === "string") {
      return inWords($.timeago.parse(timestamp));
    } else if (typeof timestamp === "number") {
      return inWords(new Date(timestamp));
    } else {
      return inWords($.timeago.datetime(timestamp));
    }
  };
  var $t = $.timeago;

  $.extend($.timeago, {
    settings: {
      refreshMillis: 60000,
      allowPast: true,
      allowFuture: false,
      localeTitle: false,
      cutoff: 0,
      autoDispose: true,
      strings: {
        prefixAgo: null,
        prefixFromNow: null,
        suffixAgo: "ago",
        suffixFromNow: "from now",
        inPast: 'any moment now',
        seconds: "less than a minute",
        minute: "about a minute",
        minutes: "%d minutes",
        hour: "about an hour",
        hours: "about %d hours",
        day: "a day",
        days: "%d days",
        month: "about a month",
        months: "%d months",
        year: "about a year",
        years: "%d years",
        wordSeparator: " ",
        numbers: []
      }
    },

    inWords: function(distanceMillis) {
      if (!this.settings.allowPast && ! this.settings.allowFuture) {
          throw 'timeago allowPast and allowFuture settings can not both be set to false.';
      }

      var $l = this.settings.strings;
      var prefix = $l.prefixAgo;
      var suffix = $l.suffixAgo;
      if (this.settings.allowFuture) {
        if (distanceMillis < 0) {
          prefix = $l.prefixFromNow;
          suffix = $l.suffixFromNow;
        }
      }

      if (!this.settings.allowPast && distanceMillis >= 0) {
        return this.settings.strings.inPast;
      }

      var seconds = Math.abs(distanceMillis) / 1000;
      var minutes = seconds / 60;
      var hours = minutes / 60;
      var days = hours / 24;
      var years = days / 365;

      function substitute(stringOrFunction, number) {
        var string = $.isFunction(stringOrFunction) ? stringOrFunction(number, distanceMillis) : stringOrFunction;
        var value = ($l.numbers && $l.numbers[number]) || number;
        return string.replace(/%d/i, value);
      }

      var words = seconds < 45 && substitute($l.seconds, Math.round(seconds)) ||
        seconds < 90 && substitute($l.minute, 1) ||
        minutes < 45 && substitute($l.minutes, Math.round(minutes)) ||
        minutes < 90 && substitute($l.hour, 1) ||
        hours < 24 && substitute($l.hours, Math.round(hours)) ||
        hours < 42 && substitute($l.day, 1) ||
        days < 30 && substitute($l.days, Math.round(days)) ||
        days < 45 && substitute($l.month, 1) ||
        days < 365 && substitute($l.months, Math.round(days / 30)) ||
        years < 1.5 && substitute($l.year, 1) ||
        substitute($l.years, Math.round(years));

      var separator = $l.wordSeparator || "";
      if ($l.wordSeparator === undefined) { separator = " "; }
      return $.trim([prefix, words, suffix].join(separator));
    },

    parse: function(iso8601) {
      var s = $.trim(iso8601);
      s = s.replace(/\.\d+/,""); // remove milliseconds
      s = s.replace(/-/,"/").replace(/-/,"/");
      s = s.replace(/T/," ").replace(/Z/," UTC");
      s = s.replace(/([\+\-]\d\d)\:?(\d\d)/," $1$2"); // -04:00 -> -0400
      s = s.replace(/([\+\-]\d\d)$/," $100"); // +09 -> +0900
      return new Date(s);
    },
    datetime: function(elem) {
      var iso8601 = $t.isTime(elem) ? $(elem).attr("datetime") : $(elem).attr("title");
      return $t.parse(iso8601);
    },
    isTime: function(elem) {
      // jQuery's `is()` doesn't play well with HTML5 in IE
      return $(elem).get(0).tagName.toLowerCase() === "time"; // $(elem).is("time");
    }
  });

  // functions that can be called via $(el).timeago('action')
  // init is default when no action is given
  // functions are called with context of a single element
  var functions = {
    init: function() {
      var refresh_el = $.proxy(refresh, this);
      refresh_el();
      var $s = $t.settings;
      if ($s.refreshMillis > 0) {
        this._timeagoInterval = setInterval(refresh_el, $s.refreshMillis);
      }
    },
    update: function(timestamp) {
      var date = (timestamp instanceof Date) ? timestamp : $t.parse(timestamp);
      $(this).data('timeago', { datetime: date });
      if ($t.settings.localeTitle) $(this).attr("title", date.toLocaleString());
      refresh.apply(this);
    },
    updateFromDOM: function() {
      $(this).data('timeago', { datetime: $t.parse( $t.isTime(this) ? $(this).attr("datetime") : $(this).attr("title") ) });
      refresh.apply(this);
    },
    dispose: function () {
      if (this._timeagoInterval) {
        window.clearInterval(this._timeagoInterval);
        this._timeagoInterval = null;
      }
    }
  };

  $.fn.timeago = function(action, options) {
    var fn = action ? functions[action] : functions.init;
    if (!fn) {
      throw new Error("Unknown function name '"+ action +"' for timeago");
    }
    // each over objects here and call the requested function
    this.each(function() {
      fn.call(this, options);
    });
    return this;
  };

  function refresh() {
    var $s = $t.settings;

    //check if it's still visible
    if ($s.autoDispose && !$.contains(document.documentElement,this)) {
      //stop if it has been removed
      $(this).timeago("dispose");
      return this;
    }

    var data = prepareData(this);

    if (!isNaN(data.datetime)) {
      if ( $s.cutoff == 0 || Math.abs(distance(data.datetime)) < $s.cutoff) {
        $(this).text(inWords(data.datetime));
      }
    }
    return this;
  }

  function prepareData(element) {
    element = $(element);
    if (!element.data("timeago")) {
      element.data("timeago", { datetime: $t.datetime(element) });
      var text = $.trim(element.text());
      if ($t.settings.localeTitle) {
        element.attr("title", element.data('timeago').datetime.toLocaleString());
      } else if (text.length > 0 && !($t.isTime(element) && element.attr("title"))) {
        element.attr("title", text);
      }
    }
    return element.data("timeago");
  }

  function inWords(date) {
    return $t.inWords(distance(date));
  }

  function distance(date) {
    return (new Date().getTime() - date.getTime());
  }

  // fix for IE6 suckage
  document.createElement("abbr");
  document.createElement("time");
}));
