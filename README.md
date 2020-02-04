# AWS Email Forwarder for almost free

## [nealalan.github.io](https://nealalan.github.io)/[AWS-Email-Forwarder](https://nealalan.github.io/AWS-Email-Forwarder)

Use Route 53, SES, S3 &amp; Lambda to implement an email forwarder via the AWS CLI. (Not via the console.)

My use case is I simply want to forward any email to my domain name to my gmail account. Using the G Suit has a US$4-5/mo cost that I have no reason to incur.

I originally received the motivation to work on this from the [aws-lambda-ses-forwarder](https://github.com/arithmetric/aws-lambda-ses-forwarder) repo, but I found myself wanting a greater understanding of how all the pieces worked and integrated. I particularly wanted to understand the resource access and security.

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

Using the `--query` flag, we can narrow down the results to only roles starting with *SES* and format the output into a table containing the RoleName and Role Arn. This is much more readable than JSON.

```bash
$ aws iam list-roles \
  --query 'Roles[?starts_with(RoleName,`SES`) == `true`].{RoleName:RoleName,Arn:Arn}' \
  --output table \
  --profile neonaluminum
```

Your output will only list one, unless you already have roles starting with *SES*.

![ROLE SCREENSHOT](https://github.com/nealalan/AWS-Email-Forwarder/blob/master/images/Screen%20Shot%202020-02-03%20at%2021.23.16.jpg?raw=true)

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

19. PULL THE CODE USED IN THE LAMBDA FUNCTION

Pull down the pre-written Javascript function that we will modify add to a new Lambda function.

```bash
$ curl https://raw.githubusercontent.com/arithmetric/aws-lambda-ses-forwarder/master/index.js > aws-lambda-ses-forwarder.js
```

20. EDIT THE JAVASCRIPT CODE

Make the following changes:

  - **fromEmail**: noreply@example.com changed to noreply@xyz.neonaluminum.com
  - **subjectPrefix**: from “” to “FWD: ” (I do this so I know this email was forwarded to me)
  - **emailBucket**: s3-bucket-name to xyz.neonaluminum.com
  - **emailKeyPrefix**: "emailsPrefix/" to “email/”
  - **forwardMapping**: There are a bunch of entries and you only need to change or apply what applies to you. Only email from the registered domain name will be processed by the Lambda function. Therefore, I changed: 
  	"@example.com": [ "example.john@example.com" ] 
	  TO
	  “@xyz.neonaluminum.com”: [ “neonaluminum0@gmail.com” ]
  - **Save** the JavaScript function
  - **Archive the function** into a ZIP file 
  ```
  $ zip aws-lambda-ses-forwarder.zip aws-lambda-ses-forwarder.js
  ```

21. CREATE THE LAMBDA FUNCTION ON AWS

Use the following data for the command flags:

  - Function name: The **default region** you used in STEP 1 and what you call the function **SESForwarder-xyz**. 
  - Runtime environment: We will use nodejs12.x. The [runtime list](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) may change in the future.
  - Handler: the **JS file name** we archived plus **.handler**. 
  - **Role Arn**: from STEP 16.

```bash
$ aws lambda create-function \
  --function-name arn:aws:lambda:us-east-1:020184898418:function:SESForwarder-xyz \
  --runtime nodejs12.x \
  --zip-file fileb://aws-lambda-ses-forwarder.zip \
  --handler aws-lambda-ses-forwarder.handler \
  --role arn:aws:iam::020184898418:role/SESMailForwarder-xyz \
  --profile neonaluminum
```

You should see **"Successful"** at the bottom of the output.

![LAMBDA FUNCTION CREATION SCREENSHOT](https://github.com/nealalan/AWS-Email-Forwarder/blob/master/images/Screen%20Shot%202020-02-03%20at%2021.34.15.jpg?raw=true)

MAKING THE LAMBDA FUNCTION EXECUTE - We have two ways this can happen. 
- S3 Events can be setup to execute the Lambda function upon a new object creation or
- SES can be setup to place the email into an S3 bucket and then call the Lambda function. **We will us this method.**

22. QUERY THE ROUTE 53 HOSTED DONE ARN

```
$ aws route53 list-hosted-zoned-by-name \
  --dns-name neonaluminum.com \
  --query 'HostedZones[].{Id:Id,Name:Name,Recs:ResourceRecordSetCount}' \
  --output table \
  --profile update-dns
  ```
  
OPTIONAL: If you don't know the Hosted Zone, you can get all:
  ```bash
  $ aws route53 list-hosted-zones \
    --query 'HostedZones[].{Id:Id,Name:Name,Recs:ResourceRecordSetCount}' \
    --output table \
    --profile update-dns
  ```








[[edit](https://github.com/nealalan/AWS-Email-Forwarder/edit/master/README.md)]
