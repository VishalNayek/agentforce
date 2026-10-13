/**
 * Agentforce action: given a customer's first name, last name, or full name,
 * resolves every policy linked to that customer (via Data Cloud Identity
 * Resolution) and returns the real per-policy payment status — no
 * bucketing, no pre-judged risk level. Apex's job here is only to fetch and
 * clearly label the facts; the agent reasons about what they mean (a single
 * missed payment isn't the same story as several, or a Delinquent status).
 */
public with sharing class AssessPaymentRiskByNameAction {

    public class PaymentRiskException extends Exception {}

    public class Response {
        @InvocableVariable(label='Customer Name' description='Full name of the matched customer, as resolved by Data Cloud Identity Resolution')
        public String customerName;

        @InvocableVariable(label='Policy Count' description='Total number of policies found for this customer')
        public Integer policyCount;

        @InvocableVariable(label='Policy Payment Statuses' description='One line per policy, already labeled: "<Policy Type>: <Payment Status>" — e.g. "Health: Missed Last Payment". Payment Status is always the real value (Current, Missed Last Payment, or Delinquent), never bucketed or guessed.')
        public List<String> policyPaymentStatuses;

        public Response() {
            policyCount = 0;
            policyPaymentStatuses = new List<String>();
        }
    }

    @InvocableMethod(label='Assess Payment Risk By Name' description='Looks up a customer by first name, last name, or full name and returns each of their policies with its real payment status, resolved through Data Cloud Identity Resolution. Use for payment risk/collections questions.')
    public static List<Response> invoke(List<String> customerNames) {
        List<Response> results = new List<Response>();
        for (String customerName : customerNames) {
            results.add(assessRisk(customerName));
        }
        return results;
    }

    @TestVisible
    private static Response assessRisk(String rawName) {
        IdentityResolutionService.CustomerIdentity identity;
        try {
            identity = IdentityResolutionService.resolveCustomer(rawName);
        } catch (IdentityResolutionService.CustomerLookupException e) {
            throw new PaymentRiskException(e.getMessage());
        }

        Response res = new Response();
        res.customerName = identity.personName;

        if (identity.sourceIds.isEmpty()) {
            return res;
        }

        String inList = IdentityResolutionService.quotedInList(identity.sourceIds);

        ConnectApi.CdpQueryInput q = new ConnectApi.CdpQueryInput();
        q.sql = 'SELECT PolicyType_c__c, PaymentStatus_c__c ' +
                'FROM Policy__dlm ' +
                'WHERE Account_c__c IN (' + inList + ') ' +
                'OR PolicyholderId__c IN (' + inList + ') ' +
                'OR PolicyholderKeyRef__c IN (' + inList + ')';
        List<ConnectApi.CdpQueryV2Row> rows = IdentityResolutionService.runQuery(q).data;

        for (ConnectApi.CdpQueryV2Row row : rows) {
            String policyType = IdentityResolutionService.safeString(row.rowData.get(0));
            String paymentStatus = IdentityResolutionService.safeString(row.rowData.get(1));
            res.policyCount++;
            res.policyPaymentStatuses.add(
                (String.isBlank(policyType) ? 'Type not specified' : policyType) + ': ' + paymentStatus
            );
        }

        return res;
    }
}