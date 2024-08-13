# Guidance for VPC Lattice automated DNS configuration on AWS

This guidance automates the creation of DNS (Domain Name System) resolution configuration in [Amazon Route 53](https://aws.amazon.com/route53/) when creating new [Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/) services with custom domain names.

## Table of Contents

1. [Overview](#overview)
    - [Architecture](#architecture)
    - [AWS services used in this Guidance](#aws-services-used-in-this-guidance)
    - [Cost](#cost)
2. [Prerequisites](#prerequisites)
    - [Operating System](#operating-system)
    - [Third-party tools](#third-party-tools)
    - [AWS Account requirements](#aws-account-requirements)
    - [Service quotas](#service-quotas)
    - [Encryption at rest](#encryption-at-rest)
3. [Deploy the Guidance](#deploy-the-guidance)
4. [Uninstall the Guidance](#uninstall-the-guidance)
5. [Security](#security)
5. [License](#license)
6. [Contributing](#contributing)

## Overview

Amazon VPC Lattice is an application networking service that simplifies the connectivity, monitoring, and security between your services. Its main benefits are the configuration and management simplification, allowing developers to focus on building features while Networking & Security administrators can provide guardrails in the services’ communication. The service simplifies the onboarding experience for developers by removing the need to implement custom application code, or run additional proxies next to every workload, while maintaining the tools and controls network admins require to audit and secure their environment. VPC Lattice leverages DNS for service discovery, so each VPC Lattice service is easily identifiable through its service-managed or custom domain names. However, for custom domain names, extra manual configuration is needed to allow DNS resolution for the consumer workloads.

This Guidance Solution automate the configuration of DNS resolution anytime a new VPC Lattice service (with a custom domain name configured) is created. 

For more information about the Guidance Solution implementation, check the [Implementation Guide](TBA).

### Architecture

Below is the diagram workflow of the Guidance for VPC Lattice automated DNS configuration on AWS. 

<div align="center">

![picture](/assets/reference_architecture_numbers.png)

</div>

The workflow is divided in two parts:

* **Spoke Account onboarding**. This is executed only once, as the SNS topic created (sending the VPC Lattice service information to the Networking Account) needs to be subscribed to the SQS queue in the Networking Account.
    * (**1**) An [Amazon EventBridge rule](https://aws.amazon.com/eventbridge/) checks if a new SNS topic has been created (it checks for the tag *NewSNS = true*). If so, the event is sent to the Networking Account via a custom event bus, notifying about the topic creation. In the Networking Account, events pushed into the custom event bus are processed by an [AWS Lambda](https://aws.amazon.com/lambda/) function, creating the cross-account subscription of the SNS topic to the SQS queue.
* **Creation of Alias records when new VPC Lattice services are created**. Anytime a new VPC Lattice service gets created in an onboarded spoke Account, its DNS information is sent to the networking Account so an Alias record can be created.
    * (**2**) An EventBridge rule checks the tag in a new VPC Lattice service (*NewService = true*) and invokes a Lambda function which will obtain the DNS information of the VPC Lattice service and publish it to the SNS topic.
    * (**3**) Once the DNS information of the VPC Lattice service arrives to the SQS queue, a Lambda fuction is called to update the information in the Route 53 Private Hosted Zone.

### AWS services used in this Guidance

| **AWS service**  | Role | Description | Service Availability |
|-----------|------------|-------------|-------------|
| [Amazon EventBridge](https://aws.amazon.com/eventbridge/)| Core service | Rules and custom event buses are used for notifying and detecting new resources.| [Documentation](https://docs.aws.amazon.com/general/latest/gr/ev.html#ev_region) |
[Amazon Lambda](https://aws.amazon.com/lambda/)| Core Service | Serverless functions used for filtering, subscribing and updating information. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/lambda-service.html#lambda_region) |
[Amazon SNS](https://aws.amazon.com/sns/)| Core Service | Simple event information publisher, used for cross-account subscription. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sns.html#sns_region) |
[Amazon SQS](https://aws.amazon.com/sqs/)| Core Service | Simple event information queue, used for cross-account subscription. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sqs-service.html#sqs_region) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)| Support Service | Used to store parameters that will later be shared. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ssm.html#ssm_region) |
[AWS Resource Access Manager (RAM)](https://aws.amazon.com/ram/)| Support Service | Used to share parameters among accounts. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ram.html#ram_region) |

### Cost 

You are responsible for the cost of the AWS services used while running this solution guidance. As of August 2024, the cost of running this Guidance Solution with default settings lies within the Free Tier, except for the use of AWS Systems Manager Advanced Paramter storage.

We recommend creating a [budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html) through [AWS Cost Explorer](http://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. You can also estimate the cost for your architecture solution using [AWS Pricing Calculator](https://calculator.aws/#/). For full details, refer to the pricing webpage for each AWS service used in this Guidance or visit [Pricing by AWS Service](#pricing-by-aws-service).

**Estimated monthly cost breakdown - Networking Account**

This breakdown of the costs of the Networking Account shows that the highest cost of the automation implementation is the Advanced Parameter Storage resource from AWS Systems Manager service. The costs are estimated in the Ireland `eu-west-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| AWS Systems Manager  | 1 advanced parameters | \$ 0.05 |
| Amazon EventBridge  | < 1 million custom events | \$ 0.00 |
| AWS Lambda  | < 1 million requests & 400,000 GB-seconds of compute time | \$ 0.00 |
| Amazon SQS | < 1 million requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 0.05** |

**Estimated monthly cost breakdown - Spoke Accounts**

The following table provides a sample cost breakdown for deploying this Guidance Solution in 1,000 different spoke Accounts which are likely to provide a VPC Lattice service in the future. The costs are estimated in the Ireland `eu-west-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| Amazon EventBridge  | < 1 million custom events | \$ 0.00 |
| AWS Lambda  | < 1 million requests & 400,000 GB-seconds of compute time | \$ 0.00 |
| Amazon SNS  | < 1 million requests | \$ 0.00|
| Amazon SQS | < 1 million requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 0.00** |

**Pricing by AWS Service**

Bellow are the pricing references for each AWS Service used in this Guidance Solution.

| **AWS service**  |  Pricing  |
|-----------|---------------|
|[Amazon EventBridge](https://aws.amazon.com/eventbridge/)| [Documentation](https://aws.amazon.com/eventbridge/pricing/) |
[Amazon Lambda](https://aws.amazon.com/lambda/)|  [Documentation](https://aws.amazon.com/lambda/pricing/) |
[Amazon SNS](https://aws.amazon.com/sns/)|  [Documentation](https://aws.amazon.com/sns/pricing/) |
[Amazon SQS](https://aws.amazon.com/sqs/)| [Documentation](https://aws.amazon.com/sqs/pricing/) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)|  [Documentation](https://aws.amazon.com/systems-manager/pricing/) |

## Prerequisites

### Operating System

This Guidance Solution uses [AWS Serverless](https://aws.amazon.com/serverless/) managed services, so there's no OS patching or management. The Lambda functions are using Python, and all the code was tested using Python `3.12`.

### Third-party tools

This solution uses [Terraform](https://www.terraform.io/) as an Infrastructure-as-Code provider. You will need Terraform installed to deploy. These instructions were tested with Terraform version `1.9.3`. You can install Terraform following [Hashicorp's documentation](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli).

For each Account deployment (under the [deployment](./deployment/) folder), you will find the following HCL config files:

* *providers.tf* file provides the Terraform and [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) version to use.
* *main.tf* and *iam.tf* provides the resources' configuration. While *main.tf* holds the configuration of the different services, *iam.tf* holds the configuration of IAM roles and policies.
* *variables.tf* defines the input each deployment requirements. Below in the [Deploy the Guidance](#deploy-the-guidance) section, you will see which input variables are required in each AWS Account.

We use the local backend configuration to store the state files. We recommend the use of another backend configuration that provides you more consistent storage and versioning, for example the use of [Amazon S3 and Amazon DynamoDB](https://developer.hashicorp.com/terraform/language/settings/backends/s3).

### AWS account requirements

These instructions require AWS credentials configured according to the [Terraform AWS Provider documentation](https://registry.terraform.io/providers/-/aws/latest/docs#authentication-and-configuration).

The credentials must have IAM permission to create and update resources in the Account - these persmissions will vary depending the Account type (*networking* or *spoke*). 

In addition, the Guidance Solution supposes your Accounts are part of the same [AWS Organization](https://aws.amazon.com/organizations/) - as IAM policies restrict cross-Account actions between Accounts within the same Organization. For RAM share to work, you need to [enable resource sharing with the Organization](https://docs.aws.amazon.com/ram/latest/userguide/getting-started-sharing.html#getting-started-sharing-orgs).

### Service quotas

Make sure you have sufficient quota for each of the services implemented in this solution. For more information, see [AWS service quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html).

To view the service quotas for all AWS services in the documentation without switching pages, view the information in the [Service endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/aws-general.pdf#aws-service-information) page in the PDF instead.

### Encryption at rest

Encryption at rest is configured in the SNS topic and SQS queues, using AWS-managed keys. Systems Manager parameters are not configured as `SecureString` due they must be encrypted with a customer managed key, and you must share the key separately through [AWS Key Management Service](https://aws.amazon.com/kms/) (KMS).

* Given its sensitivity, we are not creating any KMS resource in this Guidance Solution.
* If you would like to use customer managed keys to encrypt at rest the data of all these services, you will to change the code to configure this option in the corresponding resources: 
    * [SNS topic](https://docs.aws.amazon.com/sns/latest/dg/sns-server-side-encryption.html)
    * [SQS queue](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-server-side-encryption.html)
    * [Systems Manager parameter](https://docs.aws.amazon.com/kms/latest/developerguide/services-parameter-store.html).

## Deploy the Guidance 

Below are the instructions to deploy the automation:

**Time to deploy**: deployment times will vary depending the AWS Account type.
* *Networking Account*: 3 minutes
* *Spoke Account*: 2 minutes (per Account)

* **Step 1: Networking AWS Account**.
    * *Variables needed*: AWS Region to deploy the resources, and Private Hosted ID to create the Alias records.
    * Locate yourself in the [network_account](./deployment/networking_account/) folder and configure the AWS credentials of your Networking Account.

```
cd deployment/networking_account
(configure AWS credentials)
terraform init
terraform apply
```

* **Step 2: Spoke AWS Account**. Follow this process for each spoke Account in which you are creating VPC Lattice services.
    * *Variables needed*: AWS Region to deploy the resources, and Networking Account ID.
    * Locate yourself in the [spoke_account](./deployment/networking_account/) folder and configure the AWS credentials of your Spoke Account.

```
cd deployment/spoke_account
(configure AWS credentials)
terraform init
terraform apply
```

You will find a [test environment](./test/) if you want to check and test an end-to-end implementation using the solution.

## Uninstall the Guidance

* **Step 1.** In the Networking Account, remove all the SNS subscriptions to the SQS queue, and Alias records created in the Private Hosted Zone.
* **Step 2.** In each Spoke Account that you want to offboard, delete the Guidance Solution automation.

```
cd deployment/spoke_account
(configure AWS credentials)
terraform destroy
```

* **Step 3.** In Networking AWS Account, delete the Guidance Solution automation.

```
cd deployment/networking_account
(configure AWS credentials)
terraform destroy
```

## Security

When you build systems on AWS infrastructure, security responsibilities are shared between you and AWS. This [shared responsibility model](https://aws.amazon.com/compliance/shared-responsibility-model/) reduces your operational burden because AWS operates, manages, and controls the components including the host operating system, the virtualization layer, and the physical security of the facilities in which the services operate. For more information about AWS security visit [AWS Cloud Security](http://aws.amazon.com/security/).

This guidance relies on a lot of reasonable default options and "principle of least privilege" access for all resources. Users that deploy it in production should go through all the deployed resources and ensure those defaults comply with their security requirements and policies, have adequate logging levels and alarms enabled and protect access to publicly exposed APIs. In SQS and SNS, the Resource Policies are defined such that only the specified account/organization/resource can access such resource. IAM Roles are defined for AWS Lambda to only access the corresponding resources such as EventBridge, SQS and SNS. AWS RAM securely shares resource parameter such as SQS queue ARN and Eventbridge custom event bus ARN. This limits the access to the VPC Lattice DNS resolution automation to the configuration resources and involved accounts only.

**NOTE**: Please note that by cloning and using 3rd party open-source code you assume responsibility for its patching/securing/managing in the context of this project.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for more information.
