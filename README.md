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
$ aws s3 mb s3://abc.neonaluminum.com \
  --profile neonaluminum
```

2A.  Verify the bucket is created







[[edit](https://github.com/nealalan/AWS-Email-Forwarder/edit/master/README.md)]
