/**
 * @description Invocable Apex class to filter and return PDF document IDs
 *              from a list of ContentVersion IDs (filtering out Word documents)
 * @author Revenue Cloud
 * @date 2024
 */
public class RC_DocGen_ReturnPDF {

    @InvocableMethod(
        label='Return PDF Document ID'
        description='Doc Gen creates a Word and a PDF Document - this returns the PDF'
        category='Document Generation'
    )
    public static List<OutputVariable> ReturnPDFDocumentId(List<InputVariable> requests) {
        List<OutputVariable> outputs = new List<OutputVariable>();

        // Validate input
        if (requests == null || requests.isEmpty()) {
            throw new PDFFilterException('No request provided. At least one request is required.');
        }

        InputVariable input = requests[0];

        // Validate ResponseText
        if (String.isBlank(input.ResponseText)) {
            throw new PDFFilterException('ResponseText is required and cannot be blank.');
        }

        try {
            // Parse and validate ContentVersion IDs
            List<String> contentVersionIds = parseContentVersionIds(input.ResponseText);

            if (contentVersionIds.isEmpty()) {
                throw new PDFFilterException('No valid ContentVersion IDs found in ResponseText.');
            }

            // Query for PDF ContentVersions using secure binding
            List<ContentVersion> pdfVersions = [
                SELECT Id, FileType, ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
                AND FileType = 'PDF'
                LIMIT 1
            ];

            // Build output
            OutputVariable output = new OutputVariable();

            if (!pdfVersions.isEmpty()) {
                output.ContentDocumentId = pdfVersions[0].ContentDocumentId;
                output.ContentVersionId = pdfVersions[0].Id;
                output.IsSuccess = true;

                // Delete non-PDF documents (Word documents) from the same set
                deleteNonPDFDocuments(contentVersionIds);
            } else {
                // No PDF found - check if ContentVersions exist at all
                List<ContentVersion> anyVersions = [
                    SELECT Id, FileType
                    FROM ContentVersion
                    WHERE Id IN :contentVersionIds
                    LIMIT 1
                ];

                if (anyVersions.isEmpty()) {
                    throw new PDFFilterException('No ContentVersion records found for the provided IDs.');
                } else {
                    throw new PDFFilterException(
                        'No PDF documents found. Available file type: ' + anyVersions[0].FileType
                    );
                }
            }

            outputs.add(output);

        } catch (QueryException qEx) {
            throw new PDFFilterException('Error querying ContentVersion: ' + qEx.getMessage());
        } catch (Exception ex) {
            throw new PDFFilterException('Unexpected error filtering PDF: ' + ex.getMessage());
        }

        return outputs;
    }

    /**
     * @description Parses comma-separated ContentVersion IDs and validates them
     * @param responseText Comma-separated list of ContentVersion IDs
     * @return List of valid ID strings
     */
    private static List<String> parseContentVersionIds(String responseText) {
        List<String> validIds = new List<String>();

        // Split by comma and trim whitespace
        List<String> idStrings = responseText.split(',');

        for (String idString : idStrings) {
            String trimmedId = idString.trim();

            // Validate ID format (Salesforce ID validation)
            if (String.isNotBlank(trimmedId) && isValidSalesforceId(trimmedId)) {
                validIds.add(trimmedId);
            }
        }

        return validIds;
    }

    /**
     * @description Validates if a string is a valid Salesforce ID
     * @param idString The ID string to validate
     * @return True if valid Salesforce ID format
     */
    private static Boolean isValidSalesforceId(String idString) {
        try {
            // Attempt to cast to ID - throws exception if invalid
            Id testId = (Id) idString;
            return true;
        } catch (Exception ex) {
            return false;
        }
    }

    /**
     * @description Deletes non-PDF ContentVersions (Word documents) from the provided list
     * @param contentVersionIds List of ContentVersion IDs to check
     */
    private static void deleteNonPDFDocuments(List<String> contentVersionIds) {
        try {
            // Query for non-PDF ContentVersions and get their ContentDocumentIds
            List<ContentVersion> nonPdfVersions = [
                SELECT Id, FileType, ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
                AND FileType != 'PDF'
            ];

            // Collect ContentDocument IDs to delete
            Set<Id> contentDocIdsToDelete = new Set<Id>();
            for (ContentVersion cv : nonPdfVersions) {
                contentDocIdsToDelete.add(cv.ContentDocumentId);
            }

            // Delete ContentDocuments (this removes all versions)
            if (!contentDocIdsToDelete.isEmpty()) {
                delete [SELECT Id FROM ContentDocument WHERE Id IN :contentDocIdsToDelete];
            }
        } catch (DmlException dmlEx) {
            // Log deletion error but don't fail the main operation
            System.debug('Warning: Failed to delete non-PDF documents: ' + dmlEx.getMessage());
        }
    }

    // Inner classes for Invocable variables

    public class InputVariable {
        @InvocableVariable(label='Response Text (Comma-separated ContentVersion IDs)' required=true)
        public String ResponseText;
    }

    public class OutputVariable {
        @InvocableVariable(label='PDF Content Document ID' required=false)
        public Id ContentDocumentId;

        @InvocableVariable(label='PDF Content Version ID' required=false)
        public Id ContentVersionId;

        @InvocableVariable(label='Success Status' required=true)
        public Boolean IsSuccess;
    }

    /**
     * @description Custom exception for PDF filtering errors
     */
    public class PDFFilterException extends Exception {}
}