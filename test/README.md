# Guidance for VPC Lattice automated DNS configuration on AWS - Test environment

In this folder you can find code building the VPC Lattice and Amazon Route 53 resources needed to test this Guidance Solution. The code is divided in different subfolders, depending the AWS Account type to build the resources (we are supposing a multi-Account environment):

* consumer_account
* networking_account
* provider_account

## How to deploy this test code?

The test code assumes all the AWS Accounts are in the same AWS Organization - all the resources are shared using AWS RAM to the AWS Organization. If that's not the case, change the corresponding RAM resources in the *networking_account* folder to share with the corresponding AWS Accounts.

1. **Networking Account** Deploy the VPC Lattice service network and Route 53 resources (Profile & Private Hosted Zone). You will need to provide as variables the AWS Region to deploy the resources and the Private Hosted Zone name.

```
cd test/networking_account
terraform apply
```

2. **Networking Account** Deploy the Guidance Solution automation for the networking Account. You will need to provide as variables the AWS Region to deploy the resources and the Private Hosted Zone ID (created in Step 1).

```
cd deployment/networking_account
terraform apply
```

3. **Consumer Account** Deploy the consumer application and associate the VPC Lattice service network and Route 53 Profile to the VPC. You will need to provide as variables the AWS Region to deploy the resources and the networking Account ID.

```
cd test/consumer_account
terraform apply
```

4. **Provider Account** Deploy the Guidance Solution automation for the Spoke Account. You will need to provide as variables the AWS Region to deploy the resources and the networking Account ID.

```
cd deployment/spoke_account
terraform apply
```

5. **Provider Account** Once the Guidance Solution automation is built in the provider (spoke) Account, the automation is ready to update the DNS configuration once a VPC Lattice service has been created. Deploy the VPC Lattice service. You will need to provide as variables the AWS Region to deploy the resources, the networking Account ID, and the VPC Lattice service's custom domain name.

```
cd test/provider_account
terraform apply
```

## Clean-up

1. **Networking Account** Remove all the Alias records created in the Private Hosted Zone, and remove all the SNS subscriptions in the SQS queue.

2. **Consumer Account** Remove the consumer VPC and related resources.

```
cd test/consumer_account
terraform destroy
```

3. **Provider Account** Remove both the VPC Lattice service and Guidance Solution automation.

```
cd test/provider_account
terraform destroty

cd deployment/spoke_account
terraform destroy
```

4. **Networking Account** Remove the VPC Lattice service network, Route 53 Profile and Private Hosted Zone, and Guidance Solution automation.

```
cd test/networking_account
terraform destroty

cd deployment/networking_account
terraform destroy
```

## What am I deploying?

### [consumer_account](./consumer_account/)

* Amazon VPC with an Amazon EC2 instance - to connect to the VPC Lattice service created by the *provider Account*. The VPC associates with the following resources created by the *networking Account*:
    * VPC Lattice service network.
    * Amazon Route 53 Profile.
* EC2 Instance Connect endpoint - to connect to the EC2 instance and test connectivity.

### [networking_account](./networking_account/)

* Amazon VPC Lattice service network.
* Amazon Route 53 Profile, and Private Hosted Zone (associated to the Profile).
* AWS Systems Manager parameter - with the VPC Lattice service network ARN and Route 53 Profile ID as values.
* AWS RAM resource share sharing the VPC Lattice service network, Route 53 Profile, and Systems Manager parameter with the Organization.

### [provider_account](./provider_account/)

* Amazon VPC Lattice service. Single listener (HTTP) with a default rule pointing to a Lambda target group.
* AWS Lambda function (*provider service*) and corresponding IAM role.
