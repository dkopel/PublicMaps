global without sharing class MarketingMapController {

    public transient List<Project__c> projectRecords { get; set; }
    public transient String projectJSON { get; set; }
    public String googleMapsApiKey { get; private set; }
    public Integer totalRecords { get; private set; }

    // Test support
    @TestVisible
    static Boolean BYPASS_RECORDTYPE_FILTER = false;

    // Test data injection
    @TestVisible
    static List<Project__c> INJECT_RECORDS = null;

    public MarketingMapController() {
        setApiKey();
        projectRecords = loadAllProjectRecords();
        totalRecords = projectRecords.size();
        projectJSON = JSON.serialize(createOptimizedMapData());
    }

    public void setApiKey() {
        try {
            // Retrieve API key from custom settings
            // Using dynamic query to avoid compilation dependency on managed package
            List<SObject> settingsList = Database.query(
                'SELECT Google_Public_Map_Key__c FROM geopointe__Settings2__c LIMIT 1'
            );
            
            if (!settingsList.isEmpty() && settingsList[0].get('Google_Public_Map_Key__c') != null) {
                googleMapsApiKey = String.valueOf(settingsList[0].get('Google_Public_Map_Key__c'));
            } else {
                // No fallback - show configuration error
                googleMapsApiKey = 'CONFIGURATION_ERROR';
                System.debug('ERROR: Google Maps API key not configured in geopointe__Settings2__c.Google_Public_Map_Key__c');
            }
        } catch (Exception e) {
            // No fallback - show configuration error
            googleMapsApiKey = 'CONFIGURATION_ERROR';
            System.debug('ERROR: Failed to retrieve Google Maps API key from custom settings: ' + e.getMessage());
        }
    }

    private List<Map<String, Object>> createOptimizedMapData() {
        List<Map<String, Object>> mapData = new List<Map<String, Object>>();
        for (Project__c record : projectRecords) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('id', record.Id);

            // Determine if this position should appear on the map
            String placementType = record.Employee_Placement_Type__c;
            Boolean shouldShowOnMap = shouldPositionAppearOnMap(placementType);
            
            // Build display name based on position type
            String displayName = buildDisplayName(record, placementType);
            row.put('name', displayName);
            row.put('startDate', null);
            row.put('endDate', null);
            row.put('type', 'Employee Placement Project');
            row.put('placementType', placementType);
            row.put('description', 'Employee placement project');
            row.put('indeedLink', record.Indeed_Link__c);
            row.put('shouldShowOnMap', shouldShowOnMap);
            
            // Add postal code for info window
            String postalCode = '';
            if (record.Account__r != null && String.isNotBlank(record.Account__r.ShippingPostalCode)) {
                postalCode = record.Account__r.ShippingPostalCode;
            }
            row.put('postalCode', postalCode);

            String shortAddr = '';
            if (shouldShowOnMap && record.Account__r != null && String.isNotBlank(record.Account__r.ShippingCity) && String.isNotBlank(record.Account__r.ShippingState)) {
                shortAddr = record.Account__r.ShippingCity + ', ' + record.Account__r.ShippingState;
                if (String.isNotBlank(record.Account__r.ShippingPostalCode)) shortAddr += ' ' + record.Account__r.ShippingPostalCode;
            } else if (!shouldShowOnMap && record.Account__r != null && String.isNotBlank(record.Account__r.Senior_Director_Territory__c)) {
                // For National positions, use Senior Director Territory from Account
                shortAddr = record.Account__r.Senior_Director_Territory__c;
            }
            row.put('address', shortAddr);
            row.put('location', shortAddr);

            // Add lat/lng if available
            if (record.Account__r != null && record.Account__r.geopointe__Geocode__r != null &&
                record.Account__r.geopointe__Geocode__r.geopointe__Latitude__c != null &&
                record.Account__r.geopointe__Geocode__r.geopointe__Longitude__c != null) {
                row.put('lat', record.Account__r.geopointe__Geocode__r.geopointe__Latitude__c);
                row.put('lng', record.Account__r.geopointe__Geocode__r.geopointe__Longitude__c);
            }
            
            // Only add to map data if it should show on map and has coordinates, OR if it's a National position
            if (shouldShowOnMap && row.get('lat') != null && row.get('lng') != null) {
                mapData.add(row);
            } else if (!shouldShowOnMap) {
                // Add to map data even if not showing on map for sidebar display (National positions)
                mapData.add(row);
            }
        }
        return mapData;
    }

    // Helper methods
    private static String buildAddressString(Project__c record) {
        List<String> parts = new List<String>();
        if (record.Account__r != null) {
            if (String.isNotBlank(record.Account__r.ShippingStreet)) parts.add(record.Account__r.ShippingStreet);
            if (String.isNotBlank(record.Account__r.ShippingCity)) parts.add(record.Account__r.ShippingCity);
            if (String.isNotBlank(record.Account__r.ShippingState)) parts.add(record.Account__r.ShippingState);
            if (String.isNotBlank(record.Account__r.ShippingPostalCode)) parts.add(record.Account__r.ShippingPostalCode);
        }
        return String.join(parts, ', ');
    }
    
    // Determine if a position should appear on the map
    private static Boolean shouldPositionAppearOnMap(String placementType) {
        if (String.isBlank(placementType)) return true;
        
        // National positions don't appear on map
        return !placementType.contains('National');
    }
    
    // Build display name based on position type
    private static String buildDisplayName(Project__c record, String placementType) {
        if (String.isBlank(placementType)) {
            return record.Name;
        }
        
        // For National positions, use Senior Director Territory from Account
        if (placementType.contains('National') && record.Account__r != null && String.isNotBlank(record.Account__r.Senior_Director_Territory__c)) {
            return record.Account__r.Senior_Director_Territory__c;
        }
        
        // For other positions, use City, State format
        if (record.Account__r != null) {
            if (String.isNotBlank(record.Account__r.ShippingCity) && String.isNotBlank(record.Account__r.ShippingState)) {
                return record.Account__r.ShippingCity + ', ' + record.Account__r.ShippingState;
            }
        }
        
        return record.Name;
    }

    // Convert degrees to radians
    @TestVisible
    private static Decimal toRad(Decimal deg) {
        return deg * (Decimal)Math.PI / 180;
    }

    // Calculate distance between two points
    @TestVisible
    private static Decimal haversineMiles(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        Decimal R = 3958.7613; // miles
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
    global static String getMarketingData() {
        try {
            List<Project__c> listToUse = loadAllProjectRecords();

            List<Map<String, Object>> mapData = new List<Map<String, Object>>();
            for (Project__c record : listToUse) {
                Map<String, Object> m = new Map<String, Object>();
                m.put('id', record.Id);

                String placementType = record.Employee_Placement_Type__c;
                Boolean shouldShowOnMap = shouldPositionAppearOnMap(placementType);
                
                String displayName = buildDisplayName(record, placementType);
                m.put('name', displayName);
                m.put('startDate', null);
                m.put('endDate', null);
                m.put('type', 'Employee Placement Project');
                m.put('placementType', placementType);
                m.put('description', 'Employee placement project');
                m.put('indeedLink', record.Indeed_Link__c);
                m.put('shouldShowOnMap', shouldShowOnMap);
                
                // Add postal code for info window
                String postalCode = '';
                if (record.Account__r != null && String.isNotBlank(record.Account__r.ShippingPostalCode)) {
                    postalCode = record.Account__r.ShippingPostalCode;
                }
                m.put('postalCode', postalCode);

                String location = '';
                if (shouldShowOnMap) {
                    location = buildAddressString(record);
                } else if (record.Account__r != null && String.isNotBlank(record.Account__r.Senior_Director_Territory__c)) {
                    // For National positions, use Senior Director Territory from Account
                    location = record.Account__r.Senior_Director_Territory__c;
                }
                m.put('address', location);
                m.put('location', location);

                // Only add coordinates if it should show on map
                if (shouldShowOnMap && record.Account__r != null && record.Account__r.geopointe__Geocode__r != null &&
                    record.Account__r.geopointe__Geocode__r.geopointe__Latitude__c != null &&
                    record.Account__r.geopointe__Geocode__r.geopointe__Longitude__c != null) {
                    m.put('lat', record.Account__r.geopointe__Geocode__r.geopointe__Latitude__c);
                    m.put('lng', record.Account__r.geopointe__Geocode__r.geopointe__Longitude__c);
                }
                
                // Add to map data for sidebar display (regardless of map visibility)
                mapData.add(m);
            }

            Map<String, Object> result = new Map<String, Object>{ 'records' => mapData, 'center' => null };
            return JSON.serialize(result);
        } catch (Exception e) {
            System.debug('getMarketingData error: ' + e.getMessage());
            return '{"records": [], "center": null}';
        }
    }

    private static List<Project__c> loadAllProjectRecords() {
        try {
            // Use test data if provided
            if (INJECT_RECORDS != null) {
                return INJECT_RECORDS;
            }

            // Build WHERE clause for test vs production
            // Always check for lat/lng to ensure data quality
            String whereCore = 'Completion_Status__c = \'Pending\' ' +
                'AND Account__r.geopointe__Geocode__c != null ' +
                'AND Account__r.geopointe__Geocode__r.geopointe__Latitude__c != null ' +
                'AND Account__r.geopointe__Geocode__r.geopointe__Longitude__c != null';

            String whereClause = BYPASS_RECORDTYPE_FILTER
                ? whereCore
                : 'RecordType.Name = \'Employee Placement Project\' AND ' + whereCore;

            String soql =
                'SELECT Id, Name, Employee_Placement_Type__c, Indeed_Link__c, ' +
                '       Account__r.ShippingStreet, Account__r.ShippingCity, ' +
                '       Account__r.ShippingState, Account__r.ShippingPostalCode, ' +
                '       Account__r.Senior_Director_Territory__c, ' +
                '       Account__r.geopointe__Geocode__r.geopointe__Latitude__c, ' +
                '       Account__r.geopointe__Geocode__r.geopointe__Longitude__c ' +
                'FROM Project__c WHERE ' + whereClause + ' LIMIT 5000';

            return (List<Project__c>) Database.query(soql);
        } catch (Exception e) {
            System.debug('loadAllProjectRecords error: ' + e.getMessage());
            return new List<Project__c>();
        }
    }
}