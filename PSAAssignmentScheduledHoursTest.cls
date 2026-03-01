@isTest
public class PSAAssignmentScheduledHoursTest {

    // ─────────────────────────────────────────────
    // Helper: Find the most recent Saturday
    // ─────────────────────────────────────────────
    private static Date getLastSaturday() {
        Date today = Date.today();
        Integer dayOfWeek = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(today), 7);
        Integer daysToLastSaturday = (dayOfWeek == 6) ? 0 : dayOfWeek + 1;
        return today.addDays(-daysToLastSaturday);
    }

    // ─────────────────────────────────────────────
    // Helper: Create a minimal Assignment record
    // ─────────────────────────────────────────────
    private static pse__Assignment__c createAssignment(Date startDate, Date endDate, Decimal scheduledHours) {
        // You may need to add required fields for your org (e.g. Project, Resource)
        pse__Assignment__c assignment = new pse__Assignment__c(
            pse__Start_Date__c       = startDate,
            pse__End_Date__c         = endDate,
            pse__Scheduled_Hours__c  = scheduledHours,
            pse__Status__c           = 'Confirmed'
        );
        insert assignment;
        return assignment;
    }

    // ─────────────────────────────────────────────
    // Helper: Create Assignment Schedule records
    // ─────────────────────────────────────────────
    private static void createSchedules(Id assignmentId, Date weekStartDate, Decimal hoursPerDay, Integer numberOfWeeks) {
        List<pse__Assignment_Schedule__c> schedules = new List<pse__Assignment_Schedule__c>();
        for (Integer i = 0; i < numberOfWeeks; i++) {
            schedules.add(new pse__Assignment_Schedule__c(
                pse__Assignment__c      = assignmentId,
                pse__Date__c            = weekStartDate.addDays(i * 7),
                pse__Saturday_Hours__c  = hoursPerDay,
                pse__Sunday_Hours__c    = 0,
                pse__Monday_Hours__c    = hoursPerDay,
                pse__Tuesday_Hours__c   = hoursPerDay,
                pse__Wednesday_Hours__c = hoursPerDay,
                pse__Thursday_Hours__c  = hoursPerDay,
                pse__Friday_Hours__c    = hoursPerDay
            ));
        }
        insert schedules;
    }

    // ─────────────────────────────────────────────
    // Test 1: Assignment with schedule records
    // Expects hours to be summed from last Saturday forward
    // ─────────────────────────────────────────────
    @isTest
    static void testWithScheduleRecords() {
        Date lastSaturday = getLastSaturday();

        pse__Assignment__c assignment = createAssignment(
            lastSaturday.addDays(-14),
            lastSaturday.addDays(14),
            120
        );

        // Create 3 weeks of schedules: 1 before last Saturday, 2 from last Saturday forward
        createSchedules(assignment.Id, lastSaturday.addDays(-7), 8, 1); // past week - should NOT be included
        createSchedules(assignment.Id, lastSaturday, 8, 2);             // this week + next - SHOULD be included

        PSAAssignmentScheduledHours.Request req = new PSAAssignmentScheduledHours.Request();
        req.assignmentId = assignment.Id;

        Test.startTest();
        List<PSAAssignmentScheduledHours.Result> results = PSAAssignmentScheduledHours.getScheduledHours(
            new List<PSAAssignmentScheduledHours.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(lastSaturday, results[0].lastSaturday, 'Last Saturday date should match');

        // 2 weeks x 5 weekdays x 8 hours + 2 weeks x 1 Saturday x 8 hours = 2 * (5*8 + 8) = 96
        Decimal expectedHours = 2 * (5 * 8 + 8);
        System.assertEquals(expectedHours, results[0].scheduledHours, 'Scheduled hours should match sum of schedule records');
    }

    // ─────────────────────────────────────────────
    // Test 2: Assignment with NO schedule records (fallback proration)
    // ─────────────────────────────────────────────
    @isTest
    static void testFallbackProration() {
        Date lastSaturday = getLastSaturday();
        Date startDate = lastSaturday.addDays(-14);
        Date endDate   = lastSaturday.addDays(14);
        Decimal totalHours = 100;

        pse__Assignment__c assignment = createAssignment(startDate, endDate, totalHours);
        // No schedule records inserted

        PSAAssignmentScheduledHours.Request req = new PSAAssignmentScheduledHours.Request();
        req.assignmentId = assignment.Id;

        Test.startTest();
        List<PSAAssignmentScheduledHours.Result> results = PSAAssignmentScheduledHours.getScheduledHours(
            new List<PSAAssignmentScheduledHours.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');

        Integer totalDays     = startDate.daysBetween(endDate) + 1;
        Integer remainingDays = lastSaturday.daysBetween(endDate) + 1;
        Decimal expectedHours = (totalHours / totalDays) * remainingDays;

        System.assertEquals(expectedHours.setScale(5), results[0].scheduledHours.setScale(5),
            'Prorated hours should match');
    }

    // ─────────────────────────────────────────────
    // Test 3: Invalid / non-existent Assignment Id
    // Expects 0 hours returned gracefully
    // ─────────────────────────────────────────────
    @isTest
    static void testInvalidAssignmentId() {
        // Use a valid-format but non-existent Id
        PSAAssignmentScheduledHours.Request req = new PSAAssignmentScheduledHours.Request();
        req.assignmentId = '0HhQ00000000001AAA'; // dummy Id

        Test.startTest();
        List<PSAAssignmentScheduledHours.Result> results = PSAAssignmentScheduledHours.getScheduledHours(
            new List<PSAAssignmentScheduledHours.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(0, results[0].scheduledHours, 'Hours should be 0 for missing assignment');
    }

    // ─────────────────────────────────────────────
    // Test 4: Bulk - multiple assignments in one call
    // ─────────────────────────────────────────────
    @isTest
    static void testBulkRequests() {
        Date lastSaturday = getLastSaturday();

        List<PSAAssignmentScheduledHours.Request> requests = new List<PSAAssignmentScheduledHours.Request>();

        for (Integer i = 0; i < 5; i++) {
            pse__Assignment__c a = createAssignment(
                lastSaturday.addDays(-7),
                lastSaturday.addDays(7),
                40
            );
            PSAAssignmentScheduledHours.Request req = new PSAAssignmentScheduledHours.Request();
            req.assignmentId = a.Id;
            requests.add(req);
        }

        Test.startTest();
        List<PSAAssignmentScheduledHours.Result> results = PSAAssignmentScheduledHours.getScheduledHours(requests);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return 5 results');
        for (PSAAssignmentScheduledHours.Result res : results) {
            System.assertNotEquals(null, res.scheduledHours, 'Scheduled hours should not be null');
        }
    }

    // ─────────────────────────────────────────────
    // Test 5: Assignment ending before last Saturday
    // Expects 0 remaining hours
    // ─────────────────────────────────────────────
    @isTest
    static void testAssignmentEndedBeforeLastSaturday() {
        Date lastSaturday = getLastSaturday();

        pse__Assignment__c assignment = createAssignment(
            lastSaturday.addDays(-30),
            lastSaturday.addDays(-7), // ended a week ago
            80
        );

        PSAAssignmentScheduledHours.Request req = new PSAAssignmentScheduledHours.Request();
        req.assignmentId = assignment.Id;

        Test.startTest();
        List<PSAAssignmentScheduledHours.Result> results = PSAAssignmentScheduledHours.getScheduledHours(
            new List<PSAAssignmentScheduledHours.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(0, results[0].scheduledHours,
            'Hours should be 0 when assignment ended before last Saturday');
    }
}
