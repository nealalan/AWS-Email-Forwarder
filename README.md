# AWS Email Forwarder for almost free

## [nealalan.github.io](https://nealalan.github.io)/[AWS-Email-Forwarder](https://nealalan.github.io/AWS-Email-Forwarder)

Use Route 53, SES, S3 &amp; Lambda to implement an email forwarder via the AWS CLI. (Not via the console.)

## ASSUMPTIONS

- The [Amazon Simple Email Service (SES)](https://aws.amazon.com/ses/pricing/) free tier] allows for 62000 emails month. Inbound Data use is US$.09/1000-256kb chunks (or about 250mb). Outgoing attachments are US$0.12 per GB. (Just don’t send attachments!) 
- This setup isn’t intended to send email. We will be implementing resources and logic to *forward* any email address on abc.neonaluminum.com to a gmail account. There are ways to more granularly break the forwarding, so for example  help@xyz.neonaluminum.com would be routed to a different address than neal@xyz.neonaluminum.com and admin@xyz.neonaluminum.com could be returned to sender as undeliverable.
- You will need a domain name registered. That’s the point, really.
  - If you register through another Domain Registrar (cheaper for the first year), you will need to create a Hosted Zone in Amazon Route53.
  - Once the [Hosted Zone](https://console.aws.amazon.com/route53/home) is created, you will have Name Server records to add to your domain on the Domain Registrar site.
  - Note: Hosted zones cost US$0.50 per month. I usually have AWS credits from going to AWS hosted events, so don’t incur any cost.
- I’m using MacOS. (You can use any Linux OS. For Windows, you’ll need to lookup how to execute some commands if they don’t work for you.) My local working directory will be ~/Projects/AWS/EmailForwarder. Also, I generally backup project files in a Private Github repository. This project will automatically be stored in my Private AWS repo.
- You could setup Amazon Simple Notification Service (SNS) to notify you, I don’t need this and am opting out of the extra complexity right now.

## SECURITY
- We will be using [AWS Identity & Access Management (IAM)](https://console.aws.amazon.com/iam/home?#) to create security policies and roles.
- Per AWS Security Best Practices, you should use a separate IAM user created from the AWS Console. This user should be [setup to use the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html). 
- I will be implementing this profile using two accounts: One with my Route53 Hosted Zones and the other for everything else. Because of this, all of my commands will be executed using a `--profile` flag. Thos flag will specify to the AWS CLI which IAM Account access keys to use.

## STEPS FOR IMPLEMENTATION

1. SETUP THE DEFAULT REGION FOR SES

```bash
$ aws configure set region us-east-1 \
  --profile neonaluminum
```

2. CREATE AN S3 BUCKET 

```bash
$ aws s3 mb s3://xyz.neonaluminum.com \
  --profile neonaluminum
```

3.  VERIFY THE BUCKET IS CREATED

```bash
$ aws s3 ls \
  --profile neonaluminum
```

![S3 LS Screenshot](https://github.com/nealalan/AWS-Email-Forwarder/blob/master/images/Screen%20Shot%202020-02-03%20at%2018.07.38.jpg?raw=true)

4. CREATE A BUCKET LIFECYCLE POLICY FILE

Create a new file called **S3-lifecycle.json** to enable a 90 automatic removal for all object in the S3 bucket labeled *mail/*. 

```json
{
   "Rules": [
       {
           "Filter": {
               "Prefix": "mail/"
           },
           "Status": "Enabled",
           "Expiration": {
               "Days": 90
           },
           "ID": "Expire90"
       }
   ]
}
```

5. APPLY THE BUCKET LIFECYCLE CONFIGURATION

Using the lifecycle config, you can migrate files to less redundant, less available and less costly storage. Since we don't really care about these emails past when they are sent (almost immediately), we will store them for 90 days. If you wanted to view emails that were never forwarded because of an error (invalid or unverified *To:* address), you can see them in S3 prior to deletion.

```bash
$ aws s3api put-bucket-lifecycle-configuration  \
  --bucket xyz.neonaluminum.com  \
  --lifecycle-configuration file://S3-lifecycle.json \
  --profile neonaluminum
```

6. VERIFY THE BUCKET LIFECYCLE CONFIGURATION

```BASH
$ aws s3api get-bucket-lifecycle-configuration  \
  --bucket xyz.neonaluminum.com \
  --profile neonaluminum
```

![S3 Bucket Lifecycle Config Screenshot](https://github.com/nealalan/AWS-Email-Forwarder/blob/master/images/Screen%20Shot%202020-02-03%20at%2018.37.25.jpg?raw=true)

7. QUERY THE ACCOUNT ID

A 12-digit account number will be displayed. Save this in your notes for later use. 

```bash
$ aws sts get-caller-identity \
  --query Account \
  --output text \
  --profile neonaluminum
```

8. CREATE A BUCKET POLICY FILE

Create a new file called **S3-bucket-policy.json**. You need to change the bucket name under the **"Resource"** key and change the **"aws:Referer"** number to your ACCOUNT ID.

```json
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Sid": "AllowSESPuts",
           "Effect": "Allow",
           "Principal": {
               "Service": "ses.amazonaws.com"
           },
           "Action": "s3:PutObject",
           "Resource": "arn:aws:s3:::xyz.neonaluminum.com/*",
           "Condition": {
               "StringEquals": {
                   "aws:Referer": "020184898418"
               }
           }
       }
   ]
}

```

9. APPLY THE BUCKET POLICY

```bash
$ aws s3api put-bucket-policy \
  --bucket xyz.neonaluminum.com \
  --policy file://S3-bucket-policy.json \
  --profile neonaluminum
```

10. CREATE A NEW IAM POLICY
Create an Identity & Access Management Policy file called **IAM-policy.json**. This will specifically give access for SES to write out an S3 object for each piece of mail received and create a CloudWatch Event Log.

You will need to update the S3 bucket listed and the account ID in this file.

```json
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Effect": "Allow",
           "Action": "ses:SendRawEmail",
           "Resource": "*"
       },
       {
           "Effect": "Allow",
           "Action": [
               "s3:PutObject",
               "s3:GetObject"
           ],
           "Resource": "arn:aws:s3:::xyz.neonaluminum.com/*"
       },
       {
           "Effect": "Allow",
           "Action": [
               "logs:CreateLogStream",
               "logs:CreateLogGroup",
               "logs:PutLogEvents"
           ],
           "Resource": [
               "arn:aws:logs:us-east-1:020184898418:*",
               "arn:aws:logs:us-east-1:020184898418:log-group:/aws/lambda/SesForwarder:*"
           ]
       }
   ]
}
```

11. APPLY THE NEW IAM POLICY

```bash
$ aws iam create-policy \
  --policy-name SES-Write-S3-CloudWatchLogs-xyz \
  --policy-document file://IAM-policy.json \
  --profile neonaluminum
```

![IAM policy screenshot](https://github.com/nealalan/AWS-Email-Forwarder/blob/master/images/Screen%20Shot%202020-02-03%20at%2019.07.26.jpg?raw=true)

12. VERIFY THE POLICY

```bash
$ aws iam list-policies \
  --scope Local \
  --query 'Policies[].{Name:PolicyName,Version:DefaultVersionId,Arn:Arn}' \
  --output table \
  --profile neonaluminum
```

![IAM POLICY screenshot](https://github.com/nealalan/AWS-Email-Forwarder/blob/master/images/Screen%20Shot%202020-02-03%20at%2019.11.56.jpg?raw=true)

13. GET POLICY DETAILS

You need the policy **Arn** and **Version** to query the specificy policy. 

```bash
$ aws iam get-policy-version \
  --policy-arn arn:aws:iam::020184898418:policy/SES-Write-S3-CloudWatchLogs-xyz \
  --version-id v1 \
  --profile neonaluminum
```

I'll spare the screenshot. It should resemble the IAM-policy.json file.

14. CREATE AN IAM ROLE

Create an [IAM role](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html) file called **IAM-role.json**. This will create a trusted relationship with Lambda to allow use of the policy we created. 

```json
{
   "Version": "2012-10-17",
   "Statement": {
       "Effect": "Allow",
       "Principal": {
           "Service": "lambda.amazonaws.com"
       },
       "Action": "sts:AssumeRole"
   }
}
```

15. APPLY THE IAM ROLE FILE

```bash
aws iam create-role \
  --role-name SESMailForwarder-xyz \
  --assume-role-policy-document file://IAM-role.json \
  --profile neonaluminum

```

![IAM CREATE ROLE OUTPUT SCREENSHOT](https://github.com/nealalan/AWS-Email-Forwarder/blob/master/images/Screen%20Shot%202020-02-03%20at%2019.48.38.jpg?raw=true)


16. VERIFY THE ROLE

```bash
$ aws iam list-roles \
  --query 'Role[?starts_with(RoleName, `SES`)=='true'].{Name:RoleName,Id:RoleId,Arn:Arn}' \
  --profile neonaluminum
```

17. ATTACH POLICY TO THE ROLE

Use the **Policy ARN** from above and update the newly created **role-name** here.

```bash
$ aws iam attach-role-policy \
  --policy-arn arn:aws:iam::020184898418:policy/SES-Write-S3-CloudWatchLogs-xyz \
  --role-name SESMailForwarder-xyz \
  --profile neonaluminum
```

18. VERITY THE POLICY IS ATTACHED TO THE ROLE

```bash
$ aws iam list-attached-role-policies \
  --role-name SESMailForwarder-xyz \
  --profile neonaluminum
```

![POLICY ATTACHED TO ROLE SCREENSHOT](https://github.com/nealalan/AWS-Email-Forwarder/blob/master/images/Screen%20Shot%202020-02-03%20at%2019.58.57.jpg?raw=true)

19.




[[edit](https://github.com/nealalan/AWS-Email-Forwarder/edit/master/README.md)]
