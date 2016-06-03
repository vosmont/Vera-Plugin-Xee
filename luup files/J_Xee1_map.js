//# sourceURL=J_Xee1_map.js

/**
 * This file is part of the plugin Xee.
 * https://github.com/vosmont/Vera-Plugin-Xee
 * Copyright (c) 2016 Vincent OSMONT
 * This code is released under the MIT License, see LICENSE.
 */

var XeeMap = ( function( $ ) {
	var _debug = false;
	var _cars = {};
	var _geofences = {};
	var _zones = [];
	var _cars = {};
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
	function _initialize() {
		_loadGeofences();
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
				zone.circle.setEditable( true );
			} else {
				zone.circle.setEditable( false );
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
	function _loadGeofences() {
		_zones = [];
		$.ajax( {
			url: window.location.origin + window.location.pathname + "?id=lr_Xee&command=getGeofences&output_format=json#",
			dataType: "json"
		} )
		.done( function( geofences ) {
			// Create the map center on the first (main) zone
			var mainZone = $.isArray( geofences ) ? geofences[0] : null;
			var center = mainZone ? { lat: mainZone.latitude, lng: mainZone.longitude } : { lat: 66.624447, lng: 26.500353 };
			var map = new google.maps.Map( document.getElementById( "map" ), {
				zoom: 14,
				center: center,
				mapTypeId: google.maps.MapTypeId.ROADMAP,
				streetViewControl: false,
				scaleControl : true
			});
			map.controls[ google.maps.ControlPosition.RIGHT_TOP ].push( document.getElementById( "legend-zones" ) );
			map.controls[ google.maps.ControlPosition.LEFT_BOTTOM ].push( document.getElementById( "legend-cars" ) );
			// Manage UI events of the map
			google.maps.event.addListener( map, "click", function( event ) {
				if ( _isAdding ) {
					// Add a new geofence at the position of the click
					var position = event.latLng;
					var zoneIdx = _addZone( map, {
						name     : "New zone",
						latitude : position.lat(),
						longitude: position.lng(),
						radius   : 500
					} );
					_setIsModified( true );
					_setIsAdding( false );
					_selectZone( zoneIdx );
					_displayZoneInfos( zoneIdx );
				} else {
					_selectZone();
					_displayZoneInfos();
					_displayCarInfos();
				}
			});

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
			$( "#legend-zones select" ).change( function() {
				var zoneIdx = parseInt( $( this ).val(), 10 );
				var geofence = _zones[ zoneIdx ].geofence;
				map.setCenter( { lat: geofence.latitude, lng: geofence.longitude } );
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

			// Draw the cars
			_loadCars( map );
		} )
		.fail( function( jqxhr, textStatus, errorThrown ) {
			
		} );
	}

	/**
	 *
	 */
	function _updateZonesIn( cars ) {
		if ( _isModified ) {
			$.each( _zones, function( zoneIdx, zone ) {
				zone.circle.setOptions( { fillColor: "#f0ad4e" } );
			} );
		} else {
			var zonesIn = [];
			$.each( cars, function( i, car ) {
				if ( car.status.zonesIn ) {
					$.each( car.status.zonesIn.split( ";" ), function( i, zoneName ) {
						if ( $.inArray( zoneName, zonesIn ) === -1 ) {
							zonesIn.push( zoneName );
						}
					} );
				}
			} );
			$.each( _zones, function( zoneIdx, zone ) {
				if ( $.inArray( zone.geofence.name, zonesIn ) > -1 ) {
					zone.circle.setOptions( { fillColor: "#ff0000" } );
				} else {
					zone.circle.setOptions( { fillColor: "#00ff00" } );
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
		} );
		// TODO : get the result
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
		var circle = new google.maps.Circle({
			strokeColor: "#aaaaaa",
			strokeOpacity: 0.8,
			strokeWeight: 2,
			fillColor: "#f0ad4e",
			fillOpacity: 0.35,
			title: geofence.name,
			map: map,
			editable: false,
			clickable: true,
			center: { lat: geofence.latitude, lng: geofence.longitude },
			radius: geofence.radius
		});
		circle.zoneIdx = zoneIdx;
		_zones[ zoneIdx ] = {
			geofence: geofence,
			circle: circle
		};

		// Manage UI events
		google.maps.event.addListener( circle, "click", function() {
			_selectZone( this.zoneIdx );
			_displayZoneInfos( this.zoneIdx );
		} );
		google.maps.event.addListener( circle, "radius_changed", function() {
			_zones[ this.zoneIdx ].geofence.radius = Math.ceil( circle.getRadius() );
			_displayZoneInfos( this.zoneIdx );
			_setIsModified( true );
		} );
		google.maps.event.addListener( circle, "center_changed", function() {
			var position = circle.getCenter();
			_zones[ this.zoneIdx ].geofence.latitude = position.lat();
			_zones[ this.zoneIdx ].geofence.longitude = position.lng();
			_displayZoneInfos( this.zoneIdx );
			_setIsModified( true );
		} );

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
			removedZone.circle.setMap( null );
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
	// Cars
	// *************************************************************************************************

	/**
	 * Display the informations of a car, or clear
	 */
	function _displayCarInfos( carId ) {
		if ( carId != null ) {
			var car = _cars[ carId ].car;
			var location = car.status.location;
			if ( location ) {
				$( "#legend-car-infos" ).html(
					'<div>Geoloc: ' + location.latitude + ',' + location.longitude + '</div>'
				);
			} else {
				$( "#legend-car-infos" ).html(
					'<div>Geoloc: no location</div>'
				);
			}
			$( "#legend-car" ).val( carId );
		} else {
			$( "#legend-car-infos" ).empty();
			$( "#legend-car" ).val( "" );
		}
	}

	/**
	 *
	 */
	function _getCarsAsync() {
		var d = $.Deferred();
		$.ajax( {
			url: window.location.origin + window.location.pathname + "?id=lr_Xee&command=getCars&output_format=json#",
			dataType: "json"
		} )
		.done( function( cars ) {
			if ( $.isArray( cars ) ) {
				cars.sort( function( c1, c2 ) {
					return c1.id - c2.id;
				} );
				d.resolve( cars );
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
	function _updateCars() {
		$.when( _getCarsAsync() )
			.done( function( cars ) {
				$.each( cars, function( i, car ) {
					var carId = car.id;
					if ( _cars[ carId ] ) {
						_cars[ carId ].car = car;
						var location = car.status.location;
						if ( location && _cars[ carId ].marker ) {
							_cars[ carId ].marker.setPosition( { lat: location.latitude, lng: location.longitude } );
						}
					}
				} );
				_updateZonesIn( cars );
				window.setTimeout( _updateCars, _pollInterval * 1000 );
			} );
	}

	/**
	 *
	 */
	function _loadCars( map ) {
		$( "#legend-cars" ).html(
				'<div class="legend-title">'
			+		'Car '
			+		'<select id="legend-car">'
			+			'<option value="">...</option>'
			+		'</select>'
			+	'</div>'
			+	'<div id="legend-car-infos" class="legend-content"></div>'
		);
		$( "#legend-cars select" ).change( function() {
			var carId = parseInt( $( this ).val() );
			var location = _cars[ carId ].car.status.location;
			if ( location ) {
				map.setCenter( { lat: location.latitude, lng: location.longitude } );
			}
			_displayCarInfos( carId );
		} );

		$.when( _getCarsAsync() )
			.done( function( cars ) {
				$.each( cars, function( i, car ) {
					$( "#legend-car" ).append(
						'<option value="' + car.id + '">' + ( i + 1 ) + '. ' + car.name + '</option>'
					);
					var carId = car.id;
					_cars[ carId ] = { car: car };
					var location = car.status.location;
					if ( location ) {
						var marker = new google.maps.Marker( {
							position: { lat: location.latitude, lng: location.longitude },
							//icon: "http://vosmont.github.io/icons/xee_car.png",
							title: car.name,
							label: ( i + 1 ).toString(),
							draggable:true, // a enlever
							clickable: true,
							map: map
						} );
						marker.carId = carId;
						_cars[ carId ].marker = marker;

						// Manage UI events
						google.maps.event.addListener( marker, "click", function() {
							_displayCarInfos( this.carId );
						} );

						// Debug : move cars with drag event
						if ( _debug ) {
							google.maps.event.addListener( marker, "dragend", function() {
								var position = this.getPosition();
								$.ajax( {
									url: window.location + "id=lr_Xee&command=setCarLocation&carId=" + this.carId + "&latitude=" + position.lat().toFixed(6) + "&longitude=" + position.lng().toFixed(6) + "&output_format=json#",
									dataType: "json"
								} );
							} );
						}
					}
				} );
				_updateZonesIn( cars );
				window.setTimeout( _updateCars, _pollInterval * 1000 );
			} );
	}

	return {
		initialize: _initialize,
		loadGeofences: _loadGeofences,
		saveGeofences: _saveGeofences
	}

})( jQuery );
