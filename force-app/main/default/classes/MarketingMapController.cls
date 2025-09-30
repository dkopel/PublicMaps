global without sharing class MarketingMapController {

    public transient List<Project__c> projectRecords { get; set; }
    public transient String projectJSON { get; set; }
    public String googleMapsApiKey { get; private set; }
    public Integer totalRecords { get; private set; }

    // === Test hooks ===
    @TestVisible
    static Boolean BYPASS_RECORDTYPE_FILTER = false;

    // If provided by tests, loadAllProjectRecords() will return this list verbatim.
    // This keeps production behavior unchanged, but makes tests deterministic.
    @TestVisible
    static List<Project__c> INJECT_RECORDS = null;

    public MarketingMapController() {
        setApiKey();
        projectRecords = loadAllProjectRecords();
        totalRecords = projectRecords.size();
        projectJSON = JSON.serialize(createOptimizedMapData());
    }

    // TODO: move to Protected Custom Setting/Custom Metadata for env-specific keys
    public void setApiKey() {
        googleMapsApiKey = 'AIzaSyB862RKAXAKYskd3QzSS7i9YMxxHVpCk8M';
    }

    private List<Map<String, Object>> createOptimizedMapData() {
        List<Map<String, Object>> mapData = new List<Map<String, Object>>();
        for (Project__c record : projectRecords) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('id', record.Id);

            // Display name "City, ST" else fallback to record name
            String displayName = '';
            if (record.Account__r != null) {
                if (String.isNotBlank(record.Account__r.ShippingCity) && String.isNotBlank(record.Account__r.ShippingState)) {
                    displayName = record.Account__r.ShippingCity + ', ' + record.Account__r.ShippingState;
                }
            }
            if (String.isBlank(displayName)) {
                displayName = record.Name;
            }
            row.put('name', displayName);
            row.put('startDate', null);
            row.put('endDate', null);
            row.put('type', 'Employee Placement Project');
            row.put('placementType', record.Employee_Placement_Type__c);
            row.put('description', 'Employee placement project');

            String shortAddr = '';
            if (record.Account__r != null && String.isNotBlank(record.Account__r.ShippingCity) && String.isNotBlank(record.Account__r.ShippingState)) {
                shortAddr = record.Account__r.ShippingCity + ', ' + record.Account__r.ShippingState;
                if (String.isNotBlank(record.Account__r.ShippingPostalCode)) shortAddr += ' ' + record.Account__r.ShippingPostalCode;
            }
            row.put('address', shortAddr);
            row.put('location', shortAddr);

            if (record.Account__r != null && record.Account__r.geopointe__Geocode__r != null &&
                record.Account__r.geopointe__Geocode__r.geopointe__Latitude__c != null &&
                record.Account__r.geopointe__Geocode__r.geopointe__Longitude__c != null) {
                row.put('lat', record.Account__r.geopointe__Geocode__r.geopointe__Latitude__c);
                row.put('lng', record.Account__r.geopointe__Geocode__r.geopointe__Longitude__c);
                mapData.add(row);
            }
        }
        return mapData;
    }

    // ---------- helpers ----------
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

    // Degrees → radians
    @TestVisible
    private static Decimal toRad(Decimal deg) {
        return deg * (Decimal)Math.PI / 180;
    }

    // Haversine great-circle distance in miles
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

    // ---------- remoting ----------
    @RemoteAction
    global static String getMarketingData() {
        try {
            List<Project__c> listToUse = loadAllProjectRecords();

            List<Map<String, Object>> mapData = new List<Map<String, Object>>();
            for (Project__c record : listToUse) {
                Map<String, Object> m = new Map<String, Object>();
                m.put('id', record.Id);

                String displayName = '';
                if (record.Account__r != null) {
                    if (String.isNotBlank(record.Account__r.ShippingCity) && String.isNotBlank(record.Account__r.ShippingState)) {
                        displayName = record.Account__r.ShippingCity + ', ' + record.Account__r.ShippingState;
                    }
                }
                if (String.isBlank(displayName)) {
                    displayName = record.Name;
                }
                m.put('name', displayName);
                m.put('address', buildAddressString(record));
                m.put('startDate', null);
                m.put('endDate', null);
                m.put('type', 'Employee Placement Project');
                m.put('placementType', record.Employee_Placement_Type__c);
                m.put('description', 'Employee placement project');

                m.put('location', buildAddressString(record));

                if (record.Account__r != null && record.Account__r.geopointe__Geocode__r != null &&
                    record.Account__r.geopointe__Geocode__r.geopointe__Latitude__c != null &&
                    record.Account__r.geopointe__Geocode__r.geopointe__Longitude__c != null) {
                    m.put('lat', record.Account__r.geopointe__Geocode__r.geopointe__Latitude__c);
                    m.put('lng', record.Account__r.geopointe__Geocode__r.geopointe__Longitude__c);
                    mapData.add(m);
                }
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
            // If a test injected a list, use it verbatim.
            if (INJECT_RECORDS != null) {
                return INJECT_RECORDS;
            }

            // In test mode, use simpler WHERE clause without nested relationship filters
            // because they don't work well in Salesforce test context
            String whereCore = BYPASS_RECORDTYPE_FILTER
                ? 'Completion_Status__c = \'Pending\' AND Account__r.geopointe__Geocode__c != null'
                : 'Completion_Status__c = \'Pending\' ' +
                  'AND Account__r.geopointe__Geocode__c != null ' +
                  'AND Account__r.geopointe__Geocode__r.geopointe__Latitude__c != null ' +
                  'AND Account__r.geopointe__Geocode__r.geopointe__Longitude__c != null';

            String whereClause = BYPASS_RECORDTYPE_FILTER
                ? whereCore
                : 'RecordType.Name = \'Employee Placement Project\' AND ' + whereCore;

            String soql =
                'SELECT Id, Name, Employee_Placement_Type__c, ' +
                '       Account__r.ShippingStreet, Account__r.ShippingCity, ' +
                '       Account__r.ShippingState, Account__r.ShippingPostalCode, ' +
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
