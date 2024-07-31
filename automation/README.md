# Automation Deployment
In this folder you will find three different folders:

* lambda_functions
* networking_account
* spoke_account

## How to deploy
1. After downloading the folders, don't forget to update the path of the .py files in the main.tf files of both accounts. Search for "# UPDATE TO YOUR PATH" to help you find it. Regarding the **spoke_account** folder, if you already have your own spoke providers.tf and spoke variables.tf, you won't need to use these BUT don't forget to add the Networking Account ID in your spoke variables.tf.
2. Using the terminal, locate yourself in the networking folder, access your AWS Account and initialize terraform. If any changes have been made to the code, I recommend to run some validation checks before applying the changes in your AWS account.
```
cd networking_account
(access your AWS Networking Account)
terraform init
terraform validate
terraform plan
terraform apply
```
3. Now, follow the same steps but from the service provider account (or spoke account). Locate yourself in the spoke folder, access you AWS Spoke Account and run terraform as done before.
```
cd spoke_account
(access your AWS Spoke Account)
terraform init
terraform validate
terraform plan
terraform apply
```
## What am I deploying?

### Lambda functions
This folder contains the different Python files needed for the AWS Lambda Functions used in the DNS Automation Configuration. 
* **event_curation.py** filters and obtains the necessary information from the Tag on New VPC Lattice Service event, such as the Account ID, Custom Domain Name, VPC Lattice Domain Name, service ARN and VPC Lattice Hosted Zone ID, among others. This function is invoked by an Amazon EventBridge rule that detects Tag NewService = true. You can change this rule to adapt your architecture or designing preferences. Then, the filtered information is published as a SNS Topic message. This Lambda function is located in the Spoke/Service Provider Account.
* **subscription.py** is located in the Networking Account and is invoked when a new event arrives to the Amazon EventBridge custom eventbus. This code is responsible for the SNS Topic and SQS Queue cross-account subscription (as shown in the reference architecture). The SNS Topic ARN is obtained from the event created when an EventBridge rule detects the Tag NewSNS = true. You can also change this rule to adapt your architecture or designing preferences.
* **dns_config.py** updates the Private Hosted Zone of the Networking Account with the ALIAS of the new VPC Lattice Service. This funcion is called from the SQS Queue and receives the published information such as the Custom Domain Name and VPC Lattice Domain Name to update/create the Route53 ALIAS record.

### Networking Account
The **main.tf** file is a Terraform file that will deploy the resources needed for the automation in the main Networking Account. This resources are: SQS Queue, Lambda Functions, Eventbridge Custom EventBus and EventBridge Rule, in addition to the Access Policies, Resource Associations and Resource Access Manager (RAM) configurations to share AWS Systems Manager parameters.

### Spoke Account
In this **main.tf** file, you will find resources like EventBridge Rule, Lambda Function and SNS Topic, apart from the necessary Access Policies, targets and permissions.