//# sourceURL=J_Xee1_map.js

/**
 * This file is part of the plugin Xee.
 * https://github.com/vosmont/Vera-Plugin-Xee
 * Copyright (c) 2019 Vincent OSMONT
 * This code is released under the MIT License, see LICENSE.
 */

var XeeMap = ( function( $ ) {
	var _debug = false;
	var _vehicles = {};
	var _geofences = {};
	var _zones = [];
	var _vehicles = {};
	var _pollInterval = 10;
	var _isAdding = false;
	var _isModified = false;
	var _selectedZoneIdx;

	// *************************************************************************************************
	// Map
	// *************************************************************************************************

	/**
	 *
	 */
	function _initialize( center ) {
		// Create the map
		var map = L.map( "map", {
			center: ( center ? center : { lat: 48.8534, lng: 2.3488 } ),
			zoom: 14,
			editable: true
		});

		// Layer
		var osmLayer = L.tileLayer('http://{s}.tile.osm.org/{z}/{x}/{y}.png', { 
			attribution: '© OpenStreetMap contributors',
			maxZoom: 19
		});
		map.addLayer(osmLayer);

		// Manage UI events of the map
		map.on( "click", function( event ) {
			if ( _isAdding ) {
				// Add a new geofence at the position of the click
				var position = event.latlng;
				var zoneIdx = _addZone( map, {
					name     : "New zone",
					latitude : position.lat,
					longitude: position.lng,
					radius   : 500
				} );
				_setIsModified( true );
				_setIsAdding( false );
				_selectZone( zoneIdx );
				_displayZoneInfos( zoneIdx );
			} else {
				_selectZone();
				_displayZoneInfos();
				_displayVehicleInfos();
			}
		});

		// Zones control
		var zonesControl = L.control({ position: "topright" });
		zonesControl.onAdd = function( map ) {
			return $( '<div id="legend-zones" class="legend" />' ).get(0);
		};
		zonesControl.addTo( map );

		// Vehicles control
		var vehiclesControl = L.control({ position: "bottomleft" });
		vehiclesControl.onAdd = function( map ) {
			return $( '<div id="legend-vehicles" class="legend" />' ).get(0);
		};
		vehiclesControl.addTo( map );

		_loadGeofences( map );
		
		// Draw the vehicles
		_loadVehicles( map );
	}

	// *************************************************************************************************
	// Geofences / Zones
	// *************************************************************************************************

	/**
	 * Display the informations of a geofence, or clear
	 */
	function _displayZoneInfos( zoneIdx ) {
		if ( zoneIdx != null ) {
			var geofence = _zones[ zoneIdx ].geofence;
			$( "#legend-zone-infos" ).html(
					'<div>Geoloc: ' + geofence.latitude.toFixed( 6 ) + ',' + geofence.longitude.toFixed( 6 ) + '</div>'
				+	'<div>Radius: ' + geofence.radius + 'm</div>'
			);
			$( "#legend-zone" ).val( zoneIdx );
		} else {
			$( "#legend-zone-infos" ).empty();
			$( "#legend-zone" ).val( "" );
		}
	}

	/**
	 * Select a geofence, or deselect all
	 */
	function _selectZone( zoneIdx ) {
		_selectedZoneIdx = zoneIdx;
		_setIsAdding( false );
		$.each( _zones, function( i, zone ) {
			if ( ( zoneIdx != null) && ( i === zoneIdx ) ) {
				zone.circle.enableEdit();
			} else {
				zone.circle.disableEdit();
			}
		} );
		if ( zoneIdx != null) {
			$( "#xee-zone-edit" ).removeClass( "hide" );
			$( "#xee-zone-remove" ).removeClass( "hide" );
		} else {
			$( "#xee-zone-edit" ).addClass( "hide" );
			$( "#xee-zone-remove" ).addClass( "hide" );
		}
	}

	/**
	 *
	 */
	function _loadGeofences( map ) {
		_zones = [];
		$.ajax( {
			url: window.location.origin + window.location.pathname + "?id=lr_Xee&command=getGeofences&output_format=json#",
			dataType: "json"
		} )
		.done( function( geofences ) {
			// Center on the first (main) zone
			var mainZone = $.isArray( geofences ) ? geofences[0] : null;
			if ( mainZone ) {
				map.flyTo( { lat: mainZone.latitude, lng: mainZone.longitude } );
			}

			$( "#legend-zones" ).html(
					'<div class="legend-title">'
				+		'Zone '
				+		'<select id="legend-zone">'
				+			'<option value="">...</option>'
				+		'</select>'
				+	'</div>'
				+	'<div class="btn-group btn-group-xs pull-right" role="group" aria-label="...">'
				+		'<button type="button" id="xee-zone-save" class="btn btn-default" disabled="disabled" title="Save the modifications">'
				+			'<span class="glyphicon glyphicon-ok"></span>'
				+		'</button>'
				+		'<button type="button" id="xee-zone-add" class="btn btn-default" title="Add a geofence">'
				+			'<span class="glyphicon glyphicon-plus"></span>'
				+		'</button>'
				+		'<button type="button" id="xee-zone-edit" class="btn btn-default hide" title="Edit the selected geofence">'
				+			'<span class="glyphicon glyphicon-pencil"></span>'
				+		'</button>'
				+		'<button type="button" id="xee-zone-remove" class="btn btn-default hide" title="Remove the selected geofence">'
				+			'<span class="glyphicon glyphicon-trash"></span>'
				+		'</button>'
				+	'</div>'
				+	'<div id="legend-zone-infos" class="legend-content"></div>'
			);
			$( "#legend-zones" ).click( function( event ) {
				event.stopPropagation();
			});
			$( "#legend-zones select" ).change( function() {
				var zoneIdx = parseInt( $( this ).val(), 10 );
				var geofence = _zones[ zoneIdx ].geofence;
				map.flyTo( { lat: geofence.latitude, lng: geofence.longitude } );
				_selectZone( zoneIdx );
				_displayZoneInfos( zoneIdx );
			} );
			$( "#xee-zone-add" ).click( function() {
				_selectZone();
				_setIsAdding();
			} );
			$( "#xee-zone-edit" ).click( function() {
				_editZone( _selectedZoneIdx );
			} );
			$( "#xee-zone-remove" ).click( function() {
				_removeZone( _selectedZoneIdx );
			} );
			$( "#xee-zone-save" ).click( function() {
				_saveGeofences();
			} );

			// Draw the zones
			if ( $.isArray( geofences ) ) {
				$.each( geofences, function( i, geofence ) {
					_addZone( map, geofence, i );
				} );
			}
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			
		} );
	}

	/**
	 *
	 */
	function _updateZonesIn( vehicles ) {
		if ( _isModified ) {
			$.each( _zones, function( zoneIdx, zone ) {
				zone.circle.setStyle( { fillColor: "#f0ad4e" } );
			} );
		} else {
			var zonesIn = [];
			$.each( vehicles, function( i, vehicle ) {
				if ( vehicle.status.zonesIn ) {
					$.each( vehicle.status.zonesIn.split( ";" ), function( i, zoneName ) {
						if ( $.inArray( zoneName, zonesIn ) === -1 ) {
							zonesIn.push( zoneName );
						}
					} );
				}
			} );
			$.each( _zones, function( zoneIdx, zone ) {
				if ( $.inArray( zone.geofence.name, zonesIn ) > -1 ) {
					zone.circle.setStyle( { fillColor: "#ff0000" } );
				} else {
					zone.circle.setStyle( { fillColor: "#00ff00" } );
				}
			} );
		}
	}

	/**
	 *
	 */
	function _setIsAdding( isAdding ) {
		if ( isAdding == null ) {
			isAdding = !_isAdding;
		}
		if ( isAdding ) {
			_isAdding = true;
			$( "#xee-zone-add" )
				.addClass( "btn-warning" );
			_displayZoneInfos();
			$( "#legend-zone-infos" ).html(
				'Click on the map to create a new geofence.<br/> Don\'t forget to save.'
			);
		} else {
			_isAdding = false;
			$( "#xee-zone-add" )
				.removeClass( "btn-warning" );
			_displayZoneInfos();
		}
	}

	/**
	 *
	 */
	function _setIsModified( isModified ) {
		if ( isModified ) {
			_isModified = true;
			_updateZonesIn();
			$( "#xee-zone-save" )
				.prop( "disabled", false )
				.addClass( "btn-warning" );
		} else {
			_isModified = false;
			$( "#xee-zone-save" )
				.prop( "disabled", true )
				.removeClass( "btn-warning" );
			// The zonesIn will be updated at the next refresh
		}
	}

	/**
	 *
	 */
	function _saveGeofences() {
		var geofences = [];
		$.each( _zones, function( i, zone ) {
			geofences.push( zone.geofence );
		} );
		$.ajax( {
			url: window.location.origin + window.location.pathname + "?id=lr_Xee&command=setGeofences&newGeofences=" + encodeURIComponent( JSON.stringify( geofences ) ) + "&output_format=json#",
			dataType: "json"
		} )
		.done( function( data ) {
			console.info(data);
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			
		} );

		_setIsModified( false );
	}

	/**
	 * Add a geofence
	 */
	function _addZone( map, geofence, zoneIdx ) {
		if ( zoneIdx == null ) {
			zoneIdx = _zones.length;
		}
		$( "#legend-zone" ).append(
			'<option value="' + zoneIdx + '">' + ( zoneIdx + 1 ) + ". " + geofence.name + '</option>'
		);
		var circle = L.circle( [ geofence.latitude, geofence.longitude ], {
			radius: geofence.radius,
			color: "#aaaaaa",
			opacity: 0.8,
			weight: 2,
			fillColor: "#f0ad4e",
			fillOpacity: 0.35,
			title: geofence.name,
			interactive: true,
			editable: true
		}).addTo( map );
		circle.bindTooltip( geofence.name, {
			direction: "top",
			permanent: true
		}).openTooltip();
		circle.zoneIdx = zoneIdx;
		_zones[ zoneIdx ] = {
			geofence: geofence,
			circle: circle
		};

		// Manage UI events
		circle.on( "click", function( event ) {
			_selectZone( this.zoneIdx );
			_displayZoneInfos( this.zoneIdx );
			L.DomEvent.stopPropagation( event );
		});
		circle.on( "editable:editing", function( event ) {
			circle.closeTooltip();
		});
		circle.on( "editable:vertex:dragend", function( event ) {
			var position = this.getLatLng();
			var geofence = _zones[ this.zoneIdx ].geofence;
			geofence.latitude = position.lat;
			geofence.longitude = position.lng;
			geofence.radius = Math.ceil( this.getRadius() );
			_displayZoneInfos( this.zoneIdx );
			_setIsModified( true );
			circle.openTooltip();
		});

		return zoneIdx;
	}

	/**
	 * Edit a geofence
	 */
	function _editZone( zoneIdx ) {
		var name = _zones[ zoneIdx ].geofence.name;
		var newName = prompt( "Enter the name:", name );
		if ( newName && ( newName !== name ) ) {
			_zones[ zoneIdx ].geofence.name = newName;
			$( '#legend-zone option[value="' + zoneIdx + '"]' ).text( ( zoneIdx + 1 ) + ". " + newName );
			_setIsModified( true );
		}
	}

	/**
	 * Remove a geofence
	 */
	function _removeZone( zoneIdx ) {
		if ( window.confirm( "Are you sure to remove this geofence \"" + _zones[ zoneIdx ].geofence.name + "\"?" ) ) {
			// Remove the geofence from the map
			var removedZone = _zones.splice( zoneIdx, 1 )[ 0 ];
			removedZone.circle.remove();
			removedZone = null;
			$( '#legend-zone option[value="' + zoneIdx + '"]' ).remove();
			// Update the next geofences
			for ( var i = zoneIdx; i < _zones.length; i++ ) {
				_zones[ i ].circle.zoneIdx = i;
				$( '#legend-zone option[value="' + ( i + 1 ) + '"]' )
					.attr( "value", i )
					.text( ( i + 1 ) + ". " + _zones[ i ].geofence.name );
			}
			_setIsModified( true );
		}
	}

	// *************************************************************************************************
	// Vehicles
	// *************************************************************************************************

	/**
	 * Display the informations of a vehicle, or clear
	 */
	function _displayVehicleInfos( vehicleId ) {
		if ( vehicleId != null ) {
			var vehicle = _vehicles[ vehicleId ].vehicle;
			var location = vehicle.status.location;
			if ( location ) {
				$( "#legend-vehicle-infos" ).html(
					'<div>Geoloc: ' + location.latitude + ',' + location.longitude + '</div>'
				);
			} else {
				$( "#legend-vehicle-infos" ).html(
					'<div>Geoloc: no location</div>'
				);
			}
			$( "#legend-vehicle" ).val( vehicleId );
		} else {
			$( "#legend-vehicle-infos" ).empty();
			$( "#legend-vehicle" ).val( "" );
		}
	}

	/**
	 *
	 */
	function _getVehiclesAsync() {
		var d = $.Deferred();
		$.ajax( {
			url: window.location.origin + window.location.pathname + "?id=lr_Xee&command=getVehicles&output_format=json#",
			dataType: "json"
		} )
		.done( function( vehicles ) {
			if ( $.isArray( vehicles ) ) {
				vehicles.sort( function( c1, c2 ) {
					return c1.id - c2.id;
				} );
				d.resolve( vehicles );
			} else {
				d.reject();
			}
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			d.reject();
		} );
		return d.promise();
	}

	/**
	 *
	 */
	function _updateVehicles() {
		$.when( _getVehiclesAsync() )
			.done( function( vehicles ) {
				$.each( vehicles, function( i, vehicle ) {
					var vehicleId = vehicle.id;
					if ( _vehicles[ vehicleId ] ) {
						_vehicles[ vehicleId ].vehicle = vehicle;
						var location = vehicle.status.location;
						if ( location && _vehicles[ vehicleId ].marker ) {
							_vehicles[ vehicleId ].marker.setLatLng( { lat: location.latitude, lng: location.longitude } );
						}
					}
				} );
				_updateZonesIn( vehicles );
				window.setTimeout( _updateVehicles, _pollInterval * 1000 );
			} );
	}

	/**
	 *
	 */
	function _loadVehicles( map ) {
		$( "#legend-vehicles" ).html(
				'<div class="legend-title">'
			+		'Vehicle '
			+		'<select id="legend-vehicle">'
			+			'<option value="">...</option>'
			+		'</select>'
			+	'</div>'
			+	'<div id="legend-vehicle-infos" class="legend-content"></div>'
		);
		$( "#legend-vehicles" ).click( function( event ) {
			event.stopPropagation();
		});
		$( "#legend-vehicles select" ).change( function() {
			var vehicleId = $( this ).val();
			var location = _vehicles[ vehicleId ].vehicle.status.location;
			if ( location ) {
				map.flyTo( { lat: location.latitude, lng: location.longitude } );
			}
			_displayVehicleInfos( vehicleId );
		} );

		$.when( _getVehiclesAsync() )
			.done( function( vehicles ) {
				$.each( vehicles, function( i, vehicle ) {
					$( "#legend-vehicle" ).append(
						'<option value="' + vehicle.id + '">' + ( i + 1 ) + '. ' + vehicle.name + '</option>'
					);
					var vehicleId = vehicle.id;
					_vehicles[ vehicleId ] = { vehicle: vehicle };
					var location = vehicle.status.location;
					if ( location ) {
						var marker = L.marker( L.latLng( location.latitude, location.longitude ), {
							//icon: "http://vosmont.github.io/icons/xee_vehicle.png",
							title: ( i + 1 ).toString(),
							draggable: ( _debug && true ),
							autoPan: true
						}).addTo( map );
						marker.bindTooltip( vehicle.name, {
							direction: "top",
							permanent: true
						}).openTooltip();
						marker.vehicleId = vehicleId;
						_vehicles[ vehicleId ].marker = marker;

						// Manage UI events
						marker.on( "click", function( event ) {
							_displayVehicleInfos( this.vehicleId );
						});

						// Debug : move vehicles with drag event
						if ( _debug ) {
							marker.on( "dragend", function( event ) {
								var position = this.getLatLng();
								$.ajax( {
									url: window.location + "id=lr_Xee&command=setVehicleLocation&vehicleId=" + this.vehicleId + "&latitude=" + position.lat.toFixed(6) + "&longitude=" + position.lng.toFixed(6) + "&output_format=json#",
									dataType: "json"
								} );
							});
						}
					}
				} );
				_updateZonesIn( vehicles );
				window.setTimeout( _updateVehicles, _pollInterval * 1000 );
			} );
	}

	// Get parameters in the querystring
	function _getParameterByName( name, url ) {
		if ( !url ) {
			url = window.location.href;
		}
		name = name.replace( /[\[\]]/g, "\\$&" );
		var regex = new RegExp( "[?&]" + name + "(=([^&#]*)|&|#|$)" ),
			results = regex.exec(url);
		if ( !results ) {
			return null;
		}
		if ( !results[2] ) {
			return '';
		}
		return decodeURIComponent( results[2].replace( /\+/g, " "  ) );
	}
	_debug = ( _getParameterByName( "debug" ) === "true" );
	_pollInterval =  parseInt( _getParameterByName( "pollInterval" ), 10 ) || 10;

	return {
		initialize: _initialize,
		loadGeofences: _loadGeofences,
		saveGeofences: _saveGeofences
	}

})( jQuery );
