//# sourceURL=J_Xee1_map.js

/**
 * This file is part of the plugin Xee.
 * https://github.com/vosmont/Vera-Plugin-Xee
 * Copyright (c) 2016 Vincent OSMONT
 * This code is released under the MIT License, see LICENSE.
 */

var XeeMap = ( function( $ ) {
	var _cars = {};
	var _geofences = {};
	var _zones = [];
	var _cars = {};
	var _pollInterval = 10;

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

	function _displayZoneInfos( zoneIdx ) {
		if ( zoneIdx != null ) {
			var geofence = _zones[ zoneIdx ].geofence;
			$( "#legend-zone-infos" ).html(
					'<div>Geoloc: ' + geofence.latitude + ',' + geofence.longitude + '</div>'
				+	'<div>Radius: ' + geofence.radius + 'm</div>'
			);
			$( "#legend-zone" ).val( zoneIdx );
		} else {
			$( "#legend-zone-infos" ).empty();
			$( "#legend-zone" ).val( "" );
		}
	}
	function _selectZone( zoneIdx ) {
		$.each( _zones, function( i, zone ) {
			if ( ( zoneIdx != null) && ( i === zoneIdx ) ) {
				zone.circle.setEditable( true );
			} else {
				zone.circle.setEditable( false );
			}
		} );
	}
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
				zoom: 12,
				center: center,
				mapTypeId: google.maps.MapTypeId.ROADMAP,
				streetViewControl: false,
				scaleControl : true
			});
			map.controls[ google.maps.ControlPosition.TOP_CENTER  ].push( document.getElementById( "legend-zones" ) );
			map.controls[ google.maps.ControlPosition.TOP_RIGHT ].push( document.getElementById( "legend-cars" ) );

			// Draw the zones
			if ( $.isArray( geofences ) ) {
				$( "#legend-zones" ).html(
						'<div class="legend-title">'
					+		'Zone '
					+		'<select id="legend-zone">'
					+			'<option value="">...</option>'
					+		'</select>'
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

				$.each( geofences, function( i, geofence ) {
					var zoneIdx = i
					$( "#legend-zone" ).append(
						'<option value="' + zoneIdx + '">' + ( zoneIdx + 1 ) + ". " + geofence.name + '</option>'
					);
					var circle = new google.maps.Circle({
						strokeColor: "#AAAAAA",
						strokeOpacity: 0.8,
						strokeWeight: 2,
						fillColor: '#00FF00',
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
					google.maps.event.addListener( map, "click", function( event ) {
						_selectZone();
						_displayZoneInfos();
						_displayCarInfos();
					});
					google.maps.event.addListener( circle, "click", function() {
						_selectZone( this.zoneIdx );
						_displayZoneInfos( this.zoneIdx );
					} );
					google.maps.event.addListener( circle, "radius_changed", function() {
						_zones[ this.zoneIdx ].geofence.radius = Math.ceil( circle.getRadius() );
						_displayZoneInfos( this.zoneIdx );
						_saveGeofences();
					} );
					google.maps.event.addListener( circle, "center_changed", function() {
						var position = circle.getCenter();
						_zones[ this.zoneIdx ].geofence.latitude = position.lat().toFixed(6);
						_zones[ this.zoneIdx ].geofence.longitude = position.lng().toFixed(6);
						_displayZoneInfos( this.zoneIdx );
						_saveGeofences();
					} );

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
				zone.circle.setOptions( { fillColor: "#FF0000" } );
			} else {
				zone.circle.setOptions( { fillColor: "#00FF00" } );
			}
		} );
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
	}

	// *************************************************************************************************
	// Cars
	// *************************************************************************************************

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
		$.when( _getCarsAsync() )
			.done( function( cars ) {
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
						// Test : à enlever
						google.maps.event.addListener( marker, "dragend", function() {
							var position = this.getPosition();
							$.ajax( {
								url: window.location + "id=lr_Xee&command=setCarLocation&carId=" + this.carId + "&latitude=" + position.lat().toFixed(6) + "&longitude=" + position.lng().toFixed(6) + "&output_format=json#",
								dataType: "json"
							} );
						} );
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
