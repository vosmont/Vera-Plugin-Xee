var CLIENT_ID = "";
var CLIENT_SECRET = "";
var TOKEN_URL = "https://cloud.xee.com/v3/auth/access_token";
var TEST_URL = "https://cloud.xee.com/v3/users/me";
var SHEET_ID = "";

function doGet( e ) {
  var params = e.parameter;
  var options;
  var result = {};
  var partialResult = {};
  var errors = [];
  var internalErrors = [];
  
  try {
    
    if ( params.code || params.refreshToken ) {
      
      options = {
        "contentType": "application/x-www-form-urlencoded",
        "method" : "post",
        "headers": {
          "Authorization": "Basic " + Utilities.base64Encode( CLIENT_ID + ":" + CLIENT_SECRET ),
          "Accept": "application/json"
        },
        "followRedirects" : false,
        "muteHttpExceptions": true
      };
      
      if ( params.code ) {
        options.payload = {
          "grant_type": "authorization_code",
          "code": params.code
        };
      } else if ( params.refreshToken ) {
        options.payload = {
          "grant_type": "refresh_token",
          "refresh_token": params.refreshToken
        }; 
      }
      
      var response = UrlFetchApp.fetch( TOKEN_URL, options );
      result = JSON.parse( response.getContentText() );
      
    } else {
      errors.push( {
        "type": "PARAMETERS_ERROR",
        "message": "",
        "tip": ""
      } );
    }
  
  } catch( err ) {
    internalErrors.push( err );
    errors.push( {
      "type": "INTERNAL_ERROR",
      "message": "",
      "tip": ""
    } );
  }
  
  if ( errors.length > 0 ) {
    result = errors;
  } else {
    // Discard tokens in the stored result
    partialResult = {};
    for( var key in result ) {
      if ( ( key !== "access_token" ) && ( key !== "refresh_token" ) ) {
        partialResult[ key ] = result[ key ];
      }
    }
  }
  // log use of the macro, but DO NOT STORE tokens
  logCall_( params.state, params, partialResult, testAccessToken_( result.access_token ), internalErrors );
  
  return ContentService.createTextOutput( JSON.stringify( result ) )
    .setMimeType( ContentService.MimeType.JSON );
}

function testAccessToken_( token ) {
  if ( typeof token === "undefined" ) {
    return {}; 
  }
  try {
    var response = UrlFetchApp.fetch( TEST_URL, {
      "method" : "get",
      "headers": {
        "Authorization": "Bearer " + token
      },
      "followRedirects" : false,
      "muteHttpExceptions": true
    } );
    var userInfos = JSON.parse( response.getContentText() );
    if ( userInfos && userInfos.id ) {
      // Repect user privacy and discard private informations
      userInfos = {
        "id"       : userInfos.id,
        "firstName": userInfos.firstName,
        "lastName" : userInfos.lastName
      }
    }
    return userInfos;
  } catch( err ) {
    return err;
  }
}

function logCall_() {
  var lock = LockService.getPublicLock();
  lock.waitLock(30000);  // wait 30 seconds before conceding defeat.
  try {
    var logSheet = SpreadsheetApp.openById( SHEET_ID ).getSheetByName( "Logs" );
    lastRow = logSheet.getLastRow();
    var cell = logSheet.getRange( "A1" );
    
    cell.offset( lastRow, 0 ).setValue( ( new Date() ).toLocaleString() );
    for (i = 0; i < arguments.length; i++) {
      if ( typeof arguments[i] === "string" )  {
        cell.offset( lastRow, ( i + 1 ) ).setValue( arguments[i] );
      } else {
        cell.offset( lastRow, ( i + 1 ) ).setValue( JSON.stringify( arguments[i] ) );
      }
    }
  } catch( err ){
    Logger.log( "Error %s", JSON.stringify( err ) );
  } finally {
    lock.releaseLock();
  }
}
