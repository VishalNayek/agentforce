/**
 * Agentforce action: given a customer's first name, last name, or full name,
 * resolves the Unified Individual and returns their recent policy engagement
 * activity (PolicyViewed, ClaimStarted, etc.) streamed in live via the
 * Ingestion API — the one action in this project that reflects genuinely
 * live/streaming data rather than a bulk-loaded snapshot.
 *
 * Query chain (one hop longer than the Policy lookup, since Engagement Event
 * relates to Contact Point Phone, not Individual, directly):
 *   name -> Unified Individual -> linked source Ids (IdentityResolutionService)
 *        -> phone number(s) (ssot__ContactPointPhone__dlm)
 *        -> engagement events (PolicyEngagment_PolicyEngagemen_E9DA__dlm)
 *
 * Results are ordered most-recent-first, so a newly-fired live event appears
 * at index 0 once Data Cloud's streaming + stream-refresh latency has passed
 * (roughly 30s-3min after it's sent).
 */
public with sharing class GetRecentActivityByNameAction {

    public class RecentActivityException extends Exception {}

    public class Response {
        @InvocableVariable(label='Customer Name' description='Full name of the matched customer, as resolved by Data Cloud Identity Resolution')
        public String customerName;

        @InvocableVariable(label='Event Count' description='Number of recent activity events found for this customer')
        public Integer eventCount;

        @InvocableVariable(label='Event Types' description='Type of each event (e.g. PolicyViewed, ClaimStarted) — index-aligned with the other event list fields, most recent first')
        public List<String> eventTypes;

        @InvocableVariable(label='Event Policy Types' description='Policy type each event relates to — index-aligned with Event Types')
        public List<String> eventPolicyTypes;

        @InvocableVariable(label='Event Channels' description='Channel the event occurred on (e.g. Mobile App, Web Portal) — index-aligned with Event Types')
        public List<String> eventChannels;

        @InvocableVariable(label='Event Timestamps' description='When each event occurred — index-aligned with Event Types, most recent first')
        public List<Datetime> eventTimestamps;

        @InvocableVariable(label='Event Details' description='Free-text details for each event, if any — index-aligned with Event Types')
        public List<String> eventDetails;

        public Response() {
            eventCount = 0;
            eventTypes = new List<String>();
            eventPolicyTypes = new List<String>();
            eventChannels = new List<String>();
            eventTimestamps = new List<Datetime>();
            eventDetails = new List<String>();
        }
    }

    @InvocableMethod(label='Get Recent Activity By Name' description='Looks up a customer by first name, last name, or full name and returns their recent policy engagement activity (views, claims, etc.), streamed live via Data Cloud Ingestion API and resolved through Identity Resolution. Use for "any recent activity" or "any updates" style questions.')
    public static List<Response> invoke(List<String> customerNames) {
        List<Response> results = new List<Response>();
        for (String customerName : customerNames) {
            results.add(getRecentActivity(customerName));
        }
        return results;
    }

    @TestVisible
    private static Response getRecentActivity(String rawName) {
        IdentityResolutionService.CustomerIdentity identity;
        try {
            identity = IdentityResolutionService.resolveCustomer(rawName);
        } catch (IdentityResolutionService.CustomerLookupException e) {
            throw new RecentActivityException(e.getMessage());
        }

        Response res = new Response();
        res.customerName = identity.personName;

        if (identity.sourceIds.isEmpty()) {
            return res;
        }

        List<String> phones = IdentityResolutionService.resolvePhoneNumbers(identity.sourceIds);
        if (phones.isEmpty()) {
            return res;
        }

        ConnectApi.CdpQueryInput q = new ConnectApi.CdpQueryInput();
        q.sql = 'SELECT EventType__c, PolicyType__c, Channel__c, EventTimestamp__c, Details__c ' +
                'FROM PolicyEngagementEvent__dlm ' +
                'WHERE CustomerIdentifier__c IN (' + IdentityResolutionService.quotedInList(phones) + ') ' +
                'ORDER BY EventTimestamp__c DESC';
        List<ConnectApi.CdpQueryV2Row> rows = IdentityResolutionService.runQuery(q).data;

        for (ConnectApi.CdpQueryV2Row row : rows) {
            List<Object> cols = row.rowData;
            res.eventTypes.add(IdentityResolutionService.safeString(cols.get(0)));
            res.eventPolicyTypes.add(IdentityResolutionService.safeString(cols.get(1)));
            res.eventChannels.add(IdentityResolutionService.safeString(cols.get(2)));
            res.eventTimestamps.add(IdentityResolutionService.safeDatetime(cols.get(3)));
            res.eventDetails.add(IdentityResolutionService.safeString(cols.get(4)));
        }
        res.eventCount = res.eventTypes.size();
        return res;
    }
}