global without sharing class AccountMapController {

    // Cache for all accounts
    private static List<Account> allAccountsCache;
    
    public String postalCode { get; set; }
    public String selectedDistance { get; set; }
    public List<SelectOption> distanceOptions { get; set; }
    public transient List<Account> accounts { get; set; }
    public transient String accountsJSON { get; set; }
    private String apiKey;
    public String googleMapsApiKey { 
        get {
            return apiKey;
        }
        set {
            apiKey = value;
        }
    }
    public Integer totalAccounts { get; private set; }

    public AccountMapController() {
        initializeDistanceOptions();
        setApiKey();
        accounts = new List<Account>();
        accountsJSON = '[]';
        totalAccounts = 0;
    }

    public void setApiKey() {
        apiKey = 'AIzaSyB862RKAXAKYskd3QzSS7i9YMxxHVpCk8M';
    }

    private void initializeDistanceOptions() {
        distanceOptions = new List<SelectOption>{
            new SelectOption('10','10 miles'),
            new SelectOption('25','25 miles'),
            new SelectOption('50','50 miles'),
            new SelectOption('100','100 miles'),
            new SelectOption('250','250 miles'),
            new SelectOption('500','500 miles'),
            new SelectOption('1000','1000 miles')
        };
    }

    // Load accounts into cache
    private static void ensureAccountsCacheLoaded() {
        if (allAccountsCache == null) {
            allAccountsCache = [
                SELECT Id, Name, ShippingCity, ShippingState, ShippingStreet,
                       ShippingPostalCode, ShippingCountry, GentleCure_Website_Practice_Phone__c,
                       geopointe__Geocode__r.geopointe__Latitude__c,
                       geopointe__Geocode__r.geopointe__Longitude__c
                  FROM Account
                 WHERE geopointe__Geocode__c != null
                   AND geopointe__Geocode__r.geopointe__Latitude__c != null
                   AND geopointe__Geocode__r.geopointe__Longitude__c != null
                   AND RecordType.Name = 'Practice'
                   AND (NOT Name LIKE '%Demo%')
                   AND (NOT Name LIKE '%SkinCure Oncology%')
                   AND (NOT Name LIKE '%#2%')
                   AND (NOT Name LIKE '%#3%')
                   AND (NOT Name LIKE '%#4%')
                   AND (Status__c = 'Active' OR (Status__c = 'Pending' AND Tentative_Go_Live__c = NEXT_N_DAYS:60))
                 LIMIT 20000
            ];
        }
    }
    
    public void loadAllAccounts() {
        ensureAccountsCacheLoaded();
        accounts = allAccountsCache;
        totalAccounts = accounts.size();
        accountsJSON = JSON.serialize(createOptimizedMapData());
    }

    public void findLocationsByRadius() {
        if (String.isBlank(postalCode) || String.isBlank(selectedDistance)) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.WARNING,
                'Please enter a postal code and select a distance.'));
            return;
        }
        accounts = performRadialSearchInstance(postalCode, selectedDistance);
        accountsJSON = JSON.serialize(createOptimizedMapData());
    }

    private List<Map<String, Object>> createOptimizedMapData() {
        List<Map<String, Object>> mapData = new List<Map<String, Object>>();
        for (Account acc : accounts) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('id', acc.Id);
            // Format display name as 'City, ST' for UI
            String displayName = (String.isNotBlank(acc.ShippingCity) ? acc.ShippingCity : '') + 
                (String.isNotBlank(acc.ShippingCity) && String.isNotBlank(acc.ShippingState) ? ', ' : '') +
                (String.isNotBlank(acc.ShippingState) ? acc.ShippingState : '');
            row.put('name', displayName);

            // Only show first 5 digits of postal code since city and state are in the name
            String shortAddr = '';
            if (String.isNotBlank(acc.ShippingPostalCode)) {
                String zipCode = acc.ShippingPostalCode.trim();
                shortAddr = zipCode.length() >= 5 ? zipCode.substring(0, 5) : zipCode;
            }
            row.put('address', shortAddr);
            if (String.isNotBlank(acc.GentleCure_Website_Practice_Phone__c)) row.put('phone', acc.GentleCure_Website_Practice_Phone__c);

            // Use GeoPointe coordinates
            if (acc.geopointe__Geocode__r != null &&
                acc.geopointe__Geocode__r.geopointe__Latitude__c != null &&
                acc.geopointe__Geocode__r.geopointe__Longitude__c != null) {
                row.put('lat', acc.geopointe__Geocode__r.geopointe__Latitude__c);
                row.put('lng', acc.geopointe__Geocode__r.geopointe__Longitude__c);
                mapData.add(row); 
            }
        }
        return mapData;
    }

    // Helper methods

    private static String buildAddressString(Account acc) {
        // Only return first 5 digits of postal code since city and state are in the name
        if (String.isNotBlank(acc.ShippingPostalCode)) {
            String zipCode = acc.ShippingPostalCode.trim();
            return zipCode.length() >= 5 ? zipCode.substring(0, 5) : zipCode;
        }
        return '';
    }

    // Convert degrees to radians
    private static Decimal toRad(Decimal deg) {
        return deg * (Decimal)Math.PI / 180;
    }

    // Calculate distance between two points
    private static Decimal haversineMiles(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        Decimal R = 3958.7613; // Earth radius (miles)
        Decimal dLat = toRad(lat2 - lat1);
        Decimal dLon = toRad(lon2 - lon1);
        Decimal la1  = toRad(lat1);
        Decimal la2  = toRad(lat2);

        Decimal sinDLat = Math.sin(dLat / 2);
        Decimal sinDLon = Math.sin(dLon / 2);

        Decimal a = (sinDLat * sinDLat)
                  + (Math.cos(la1) * Math.cos(la2) * sinDLon * sinDLon);

        Decimal c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    // Remote actions

    @RemoteAction
    global static String getZipCodeCentroid(String zipCode) {
        if (String.isBlank(zipCode)) {
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error' => 'Zip code is required'
            });
        }

        // Setup API request
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://shape-api-gateway.dev.services.ascentcloud-api.io/getShapes/featureCollection');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-GEOPOINTE-API-TOKEN', '045ciO04sJmBHDZ4JGF0m4hbYG600fK8Uss2MrgRmkDUf');
        req.setHeader('x-application-name', 'geopointe');
        req.setHeader('x-user-id', '005O800000IAAS9IAP');
        req.setHeader('x-organization-id', '00DEk00000OOV8GMAX');
        
        // Build request body
        Map<String, Object> requestBody = new Map<String, Object>{
            'search' => zipCode,
            'type' => 'ZIP Code (USPS)',
            'fields' => new List<String>{'id', 'type', 'geometry'},
            'geometry' => true
        };
        
        req.setBody(JSON.serialize(requestBody));
        req.setTimeout(30000); // 30 second timeout
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            
            // Get centroid coordinates
            if (responseData.containsKey('geoShapes')) {
                Map<String, Object> geoShapes = (Map<String, Object>) responseData.get('geoShapes');
                if (geoShapes.containsKey('features')) {
                    List<Object> features = (List<Object>) geoShapes.get('features');
                    if (!features.isEmpty()) {
                        Map<String, Object> feature = (Map<String, Object>) features[0];
                        if (feature.containsKey('centroid')) {
                            Map<String, Object> centroid = (Map<String, Object>) feature.get('centroid');
                            if (centroid.containsKey('coordinates')) {
                                List<Object> coordinates = (List<Object>) centroid.get('coordinates');
                                if (coordinates.size() >= 2) {
                                    return JSON.serialize(new Map<String, Object>{
                                        'success' => true,
                                        'lng' => coordinates[0],
                                        'lat' => coordinates[1],
                                        'zip' => zipCode
                                    });
                                }
                            }
                        }
                    }
                }
            }
            
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error' => 'No centroid found for zip code: ' + zipCode
            });
        } else {
            return JSON.serialize(new Map<String, Object>{
                'success' => false,
                'error' => 'API request failed with status: ' + res.getStatusCode()
            });
        }
    }

    @RemoteAction
    global static String getAccountData(String postalCodeFilter, String distanceFilter) {
        List<Account> listToUse =
            (String.isNotBlank(postalCodeFilter) && String.isNotBlank(distanceFilter))
            ? performRadialSearch(postalCodeFilter, distanceFilter)
            : loadAllUSAccounts();

        List<Map<String, Object>> mapData = new List<Map<String, Object>>();
        for (Account acc : listToUse) {
            Map<String, Object> m = new Map<String, Object>();
            m.put('id', acc.Id);
            // Format display name as 'City, ST' for UI
            String displayName = (String.isNotBlank(acc.ShippingCity) ? acc.ShippingCity : '') + 
                (String.isNotBlank(acc.ShippingCity) && String.isNotBlank(acc.ShippingState) ? ', ' : '') +
                (String.isNotBlank(acc.ShippingState) ? acc.ShippingState : '');
            m.put('name', displayName);
            m.put('accountName', acc.Name); // Actual Salesforce account name for GTM tracking
            m.put('address', buildAddressString(acc));
            m.put('phone', acc.GentleCure_Website_Practice_Phone__c != null ? acc.GentleCure_Website_Practice_Phone__c : '');
            m.put('city', acc.ShippingCity != null ? acc.ShippingCity : '');
            m.put('state', acc.ShippingState != null ? acc.ShippingState : '');
            m.put('street', acc.ShippingStreet != null ? acc.ShippingStreet : '');
            m.put('postalCode', acc.ShippingPostalCode != null ? acc.ShippingPostalCode : '');
            m.put('country', acc.ShippingCountry != null ? acc.ShippingCountry : '');
            if (acc.geopointe__Geocode__r != null &&
                acc.geopointe__Geocode__r.geopointe__Latitude__c != null &&
                acc.geopointe__Geocode__r.geopointe__Longitude__c != null) {
                m.put('lat', acc.geopointe__Geocode__r.geopointe__Latitude__c);
                m.put('lng', acc.geopointe__Geocode__r.geopointe__Longitude__c);
            }
            mapData.add(m);
        }

        Map<String, Object> result = new Map<String, Object>{ 'accounts' => mapData, 'center' => null };

        // Center map on the searched ZIP using API-based centroid
        if (String.isNotBlank(postalCodeFilter)) {
            String centroidResponse = getZipCodeCentroid(postalCodeFilter);
            Map<String, Object> centroidData = (Map<String, Object>) JSON.deserializeUntyped(centroidResponse);
            
            if ((Boolean) centroidData.get('success')) {
                result.put('center', new Map<String, Object>{
                    'lat' => centroidData.get('lat'),
                    'lng' => centroidData.get('lng'),
                    'zip' => postalCodeFilter
                });
            }
        }
        return JSON.serialize(result);
    }

    // Filter accounts by distance using Haversine formula

    private static List<Account> performRadialSearch(String postalCode, String distanceMilesStr) {
        // Get search center coordinates
        String centroidResponse = getZipCodeCentroid(postalCode);
        Map<String, Object> centroidData = (Map<String, Object>) JSON.deserializeUntyped(centroidResponse);
        
        if (!(Boolean) centroidData.get('success')) {
            return new List<Account>();
        }
        
        Decimal lat = (Decimal) centroidData.get('lat');
        Decimal lng = (Decimal) centroidData.get('lng');
        
        if (lat == null || lng == null) {
            return new List<Account>();
        }
        
        Decimal miles = Decimal.valueOf(distanceMilesStr);

        // Use cached accounts
        ensureAccountsCacheLoaded();

        // Filter by distance
        List<Account> results = new List<Account>();
        for (Account a : allAccountsCache) {
            Decimal alat = a.geopointe__Geocode__r.geopointe__Latitude__c;
            Decimal alng = a.geopointe__Geocode__r.geopointe__Longitude__c;
            Decimal d = haversineMiles(lat, lng, alat, alng);
            if (d <= miles) results.add(a);
        }
        return results;
    }

    private static List<Account> loadAllUSAccounts() {
        // Use cached accounts
        ensureAccountsCacheLoaded();
        return allAccountsCache;
    }

    // Instance method wrapper
    private List<Account> performRadialSearchInstance(String postalCode, String distance) {
        return performRadialSearch(postalCode, distance);
    }

    public void resetSearch() {
        postalCode = '';
        selectedDistance = '';
        loadAllAccounts();
    }
    @TestVisible
		static void setAccountsCacheForTest(List<Account> records) {
    	allAccountsCache = records;
    }
}