public class PSAAssignmentScheduledHours {

    public class Request {
        @InvocableVariable(label='Assignment Id' required=true)
        public Id assignmentId;
    }

    public class Result {
        @InvocableVariable(label='Scheduled Hours From Last Saturday')
        public Decimal scheduledHours;

        @InvocableVariable(label='Last Saturday Date')
        public Date lastSaturday;
    }

    @InvocableMethod(label='Get Scheduled Hours From Last Saturday' 
                     description='Calculates scheduled hours on an Assignment from last Saturday forward')
    public static List<Result> getScheduledHours(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result res = new Result();

            // Step 1: Find last Saturday
            Date today = Date.today();
            Integer dayOfWeek = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(today), 7);
            // dayOfWeek: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
            Integer daysToLastSaturday = (dayOfWeek == 6) ? 0 : dayOfWeek + 1;
            Date lastSaturday = today.addDays(-daysToLastSaturday);
            res.lastSaturday = lastSaturday;

            // Step 2: Query the Assignment
            List<pse__Assignment__c> assignments = [
                SELECT Id,
                       pse__Start_Date__c,
                       pse__End_Date__c,
                       pse__Scheduled_Hours__c,
                       pse__Schedule__c,
                       (SELECT Id,
                               pse__Date__c,
                               pse__Monday_Hours__c,
                               pse__Tuesday_Hours__c,
                               pse__Wednesday_Hours__c,
                               pse__Thursday_Hours__c,
                               pse__Friday_Hours__c,
                               pse__Saturday_Hours__c,
                               pse__Sunday_Hours__c
                        FROM pse__Assignment_Schedules__r
                        WHERE pse__Date__c >= :lastSaturday
                        ORDER BY pse__Date__c ASC)
                FROM pse__Assignment__c
                WHERE Id = :req.assignmentId
            ];

            if (assignments.isEmpty()) {
                res.scheduledHours = 0;
                results.add(res);
                continue;
            }

            pse__Assignment__c assignment = assignments[0];
            Decimal totalHours = 0;

            // Step 3: If Assignment Schedules exist, sum hours from last Saturday forward
            if (!assignment.pse__Assignment_Schedules__r.isEmpty()) {
                for (pse__Assignment_Schedule__c schedule : assignment.pse__Assignment_Schedules__r) {
                    totalHours += nvl(schedule.pse__Saturday_Hours__c);
                    totalHours += nvl(schedule.pse__Sunday_Hours__c);
                    totalHours += nvl(schedule.pse__Monday_Hours__c);
                    totalHours += nvl(schedule.pse__Tuesday_Hours__c);
                    totalHours += nvl(schedule.pse__Wednesday_Hours__c);
                    totalHours += nvl(schedule.pse__Thursday_Hours__c);
                    totalHours += nvl(schedule.pse__Friday_Hours__c);
                }
            } else {
                // Fallback: use daily rate from total scheduled hours if no schedules exist
                Date startDate = assignment.pse__Start_Date__c;
                Date endDate = assignment.pse__End_Date__c;
                Decimal totalScheduledHours = nvl(assignment.pse__Scheduled_Hours__c);

                if (startDate != null && endDate != null && totalScheduledHours > 0) {
                    Integer totalDays = startDate.daysBetween(endDate) + 1;
                    Integer remainingDays = lastSaturday.daysBetween(endDate) + 1;

                    if (remainingDays > 0 && totalDays > 0) {
                        totalHours = (totalScheduledHours / totalDays) * remainingDays;
                    }
                }
            }

            res.scheduledHours = totalHours;
            results.add(res);
        }

        return results;
    }

    // Null-safe helper
    private static Decimal nvl(Decimal val) {
        return val == null ? 0 : val;
    }
}
