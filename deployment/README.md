# Guidance for VPC Lattice automated DNS configuration on AWS - Deployment

In this folder you will find three different folders:

* lambda_functions
* networking_account
* spoke_account

For detailed information about the deployment steps, check the [root README](../README.md) file.

## What am I deploying?

### lambda_functions

This [folder](./lambda_functions/) contains the different Python files needed for the AWS Lambda functions used in the Guidance Solution.

* **event_curation.py** filters and obtains the necessary information from newly created VPC Lattice service: Account ID, Custom Domain Name, VPC Lattice Domain Name and Hosted Zone ID, and service ARN. Then, the filtered information is published to an SNS topic. This Lambda function is used by the spoke Account.
* **subscription.py** creates the SNS topic subscription (from spoke Accounts) to the SQS queue located in the Networking Account. The SNS topic ARN is obtained from the event created (in the spoke Accounts) when an EventBridge rule detects a new SNS topic has been created. This Lambda function is used by the Networking Account.
* **dns_config.py** updates the Private Hosted Zone of the Networking Account with the ALIAS of the new VPC Lattice Service. This funcion is called from the SQS Queue and receives the published information such as the Custom Domain Name and VPC Lattice Domain Name to update/create the Route53 ALIAS record.

### networking_account

Resources to be created in the Networking Account. Move to the [folder](./networking_account/) for more information about the resources.

### spoke_account

Resources to be created in any Spoke Account you want to have this Guidance Solution running. Move to the [folder](./spoke_account/) for more information about the resources.
