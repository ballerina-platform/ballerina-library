import ballerina/email;
import ballerina/io;
import ballerina/os;

// Sends an HTML email via SMTP.
// Args: subject bodyFile recipients senderAddress smtpHost
// Credentials are read from EMAIL_USERNAME and EMAIL_PASSWORD env vars.
public function main(string subject, string bodyFile, string recipients, string senderAddress, string smtpHost) returns error? {
    string password = os:getEnv("EMAIL_PASSWORD");
    if password == "" {
        return error("EMAIL_PASSWORD environment variable is not set");
    }

    string htmlBody = check io:fileReadString(bodyFile);

    email:SmtpClient smtpClient = check new (smtpHost, senderAddress, password);

    email:Message message = {
        to: recipients,
        subject: subject,
        htmlBody: htmlBody
    };

    check smtpClient->sendMessage(message);
    io:println("Email sent successfully to: " + recipients);
}
