/**
 * Shared Data Cloud Identity Resolution lookup: resolves a customer name to
 * their Unified Individual and every base-Individual source-record Id linked
 * to it, via UnifiedIndividual__dlm -> IndividualIdentityLink__dlm. Reused by
 * every "look up this customer's <X> across all source systems" action.
 */
public with sharing class IdentityResolutionService {

    public class CustomerLookupException extends Exception {}

    public class CustomerIdentity {
        public String unifiedIndividualId;
        public String personName;
        public List<String> sourceIds;
    }

  
    public static CustomerIdentity resolveCustomer(String rawName) {
        if (String.isBlank(rawName)) {
            throw new CustomerLookupException('Please provide a customer name to search for.');
        }
        String name = ansiEscape(rawName.trim());

        // Query 1: name -> Unified Individual
        ConnectApi.CdpQueryInput q1 = new ConnectApi.CdpQueryInput();
        q1.sql = 'SELECT ssot__Id__c, ssot__PersonName__c FROM UnifiedIndividual__dlm ' +
                 'WHERE UPPER(ssot__FirstName__c) = UPPER(\'' + name + '\') ' +
                 'OR UPPER(ssot__PersonName__c) = UPPER(\'' + name + '\')';
        List<ConnectApi.CdpQueryV2Row> unifiedRows = runQuery(q1).data;

        if (unifiedRows.isEmpty()) {
            throw new CustomerLookupException('No customer found matching "' + rawName + '".');
        }
        if (unifiedRows.size() > 1) {
            throw new CustomerLookupException('Multiple customers match "' + rawName + '". Please provide a more specific full name.');
        }

        CustomerIdentity identity = new CustomerIdentity();
        identity.unifiedIndividualId = safeString(unifiedRows[0].rowData.get(0));
        identity.personName = safeString(unifiedRows[0].rowData.get(1));

        // Query 2: Unified Individual -> every linked source-system Id
        ConnectApi.CdpQueryInput q2 = new ConnectApi.CdpQueryInput();
        q2.sql = 'SELECT SourceRecordId__c FROM IndividualIdentityLink__dlm ' +
                 'WHERE UnifiedRecordId__c = \'' + ansiEscape(identity.unifiedIndividualId) + '\'';
        List<ConnectApi.CdpQueryV2Row> linkRows = runQuery(q2).data;

        identity.sourceIds = new List<String>();
        for (ConnectApi.CdpQueryV2Row row : linkRows) {
            identity.sourceIds.add(safeString(row.rowData.get(0)));
        }
        return identity;
    }

    /**
     * Step 3 for phone-linked lookups (e.g. Engagement Event, which relates to
     * Contact Point Phone rather than Individual directly): given a customer's
     * linked base Individual source Ids, return every distinct phone number on
     * file for them via ssot__ContactPointPhone__dlm.
     */
    public static List<String> resolvePhoneNumbers(List<String> sourceIds) {
        List<String> phones = new List<String>();
        if (sourceIds == null || sourceIds.isEmpty()) {
            return phones;
        }
        ConnectApi.CdpQueryInput qi = new ConnectApi.CdpQueryInput();
        qi.sql = 'SELECT ssot__FormattedE164PhoneNumber__c FROM ssot__ContactPointPhone__dlm ' +
                 'WHERE ssot__PartyId__c IN (' + quotedInList(sourceIds) + ')';
        List<ConnectApi.CdpQueryV2Row> rows = runQuery(qi).data;

        Set<String> seen = new Set<String>();
        for (ConnectApi.CdpQueryV2Row row : rows) {
            String phone = safeString(row.rowData.get(0));
            if (phone != null && !seen.contains(phone)) {
                seen.add(phone);
                phones.add(phone);
            }
        }
        return phones;
    }

    public static String quotedInList(List<String> values) {
        List<String> quoted = new List<String>();
        for (String v : values) {
            quoted.add('\'' + ansiEscape(v) + '\'');
        }
        return String.join(quoted, ',');
    }

    public static ConnectApi.CdpQueryOutputV2 runQuery(ConnectApi.CdpQueryInput qi) {
        try {
            return ConnectApi.CdpQuery.queryAnsiSqlV2(qi);
        } catch (Exception e) {
            throw new CustomerLookupException('Data Cloud query failed: ' + e.getMessage());
        }
    }

    // Data Cloud's SQL engine is ANSI-style: escape a literal quote by doubling it,
    // not by backslash-escaping (that's a SOQL convention, not honored here).
    public static String ansiEscape(String s) {
        return s == null ? '' : s.replace('\'', '\'\'');
    }

    public static String safeString(Object o) {
        return (o == null) ? null : String.valueOf(o);
    }

    public static Decimal safeDecimal(Object o) {
        if (o == null) return null;
        if (o instanceof Decimal) return (Decimal) o;
        try { return Decimal.valueOf(String.valueOf(o)); } catch (Exception e) { return null; }
    }

    public static Date safeDate(Object o) {
        if (o == null) return null;
        if (o instanceof Date) return (Date) o;
        if (o instanceof Datetime) return ((Datetime) o).date();
        try {
            String s = String.valueOf(o);
            if (s.length() > 10) s = s.substring(0, 10);
            return Date.valueOf(s);
        } catch (Exception e) {
            return null;
        }
    }

    public static Datetime safeDatetime(Object o) {
        if (o == null) return null;
        if (o instanceof Datetime) return (Datetime) o;
        if (o instanceof Date) return Datetime.newInstance(((Date) o).year(), ((Date) o).month(), ((Date) o).day());
        try {
            return Datetime.valueOf(String.valueOf(o).replace(' UTC', ''));
        } catch (Exception e) {
            return null;
        }
    }
}