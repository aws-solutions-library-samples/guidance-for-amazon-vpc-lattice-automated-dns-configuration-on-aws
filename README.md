# Guidance for VPC Lattice automated DNS configuration on AWS

This guidance automates the creation of DNS (Domain Name System) resolution configuration in [Amazon Route 53](https://aws.amazon.com/route53/) when creating new [Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/) services with custom domain names.

## Table of Contents

1. [Overview](#overview)
    - [Architecture](#architecture-overview)
    - [AWS services used in this Guidance](#aws-services-used-in-this-guidance)
    - [Cost](#cost)
2. [Prerequisites](#prerequisites)
    - [Operating System](#operating-system)
    - [Third-party tools](#third-party-tools)
    - [AWS Account requirements](#aws-account-requirements)
    - [Service quotas](#service-quotas)
3. [Deploy the Guidance](#deploy-the-guidance)
4. [Security](#security)
    - [Encryption at rest](#encryption-at-rest)
5. [License](#license)
6. [Contributing](#contributing)

## Overview

[Amazon VPC Lattice](https://aws-preview.aka.amazon.com/vpc/lattice/) is an application networking service that simplifies connectivity, monitoring, and security between your services. Its main benefits are the configuration and management simplification, allowing developers to focus on building features while Networking & Security administrators can provide guardrails in the services’ communication. The service simplifies the onboarding experience for developers by removing the need to implement custom application code, or run additional proxies next to every workload, while maintaining the tools and controls network admins require to audit and secure their environment. VPC Lattice leverages [Domain Name System (DNS)](https://aws.amazon.com/route53/what-is-dns/) for service discovery, so each VPC Lattice service is easily identifiable through its service-managed or custom domain names. However, for custom domain names, extra manual configuration is needed to allow DNS resolution for the consumer workloads.

This guidance automates the configuration of DNS resolution anytime a new VPC Lattice service (with a custom domain name configured) is created. For more information about how the guidance is implemented, check the [Implementation Guide](TBA).

### Features and benefits 

This guidance provides the following features:

1. **Seamless service discovery with VPC Lattice when using custom domain names**. 
    * All the DNS resolution is configured in the Private Hosted Zone you desire.
    * Anytime a VPC Lattice service is created in any AWS Account, its DNS configuration (custom and service-managed domain names) is sent to the AWS Account managing the DNS configuration. This messages are processed by creating an [Alias record](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html).

2. **Seamless AWS Account onboarding**.
    * When new Accounts that create VPC Lattice services (*spoke* Account) are needed to be onboarded (to the *central* Account), this guidance provides an automation for the onboarding process.
    * Each spoke Account will use an [Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/welcome.html) topic to send information to a central Account [Amazon SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/welcome.html) queue, so the onboarding automation will create the SNS subscription to the SQS queu.

3. **Automation resources are built using Infrastructure-as-Code**.
    * [Hashicorp Terraform](https://www.terraform.io/) is used for the guidance automated code deployment.
    * Given this automation is built for multi-account environments, detailed deployment steps are provided in the [Deploy the Guidance](#deploy-the-guidance) section.

### Use cases

While VPC Lattice can be used in a single Account, the most common use case is the use of the service in multi-Account environments. With VPC Lattice, two are the main resources to be used: the [VPC Lattice service network](https://docs.aws.amazon.com/vpc-lattice/latest/ug/service-networks.html) is the logical boundary that connects consumers and producers, and the [VPC Lattice service](https://docs.aws.amazon.com/vpc-lattice/latest/ug/services.html) is the independently deployable unit of software that delivers a task or function (the application). The multi-Account model for VPC Lattice can vary depending your use case, and any model you use can work with the use of this guidance. You can find more information about the different multi-Account architecture models can be found in the following [Reference Architecture](https://docs.aws.amazon.com/architecture-diagrams/latest/amazon-vpc-lattice-use-cases/amazon-vpc-lattice-use-cases.html).

This guidance assumes a centralized model in terms of the DNS resolution.

* A central Networking Account is the one owning all the DNS configuration, sharing it with the rest of the AWS Accounts.
* The rest of the spoke Accounts consume this DNS configuration shared by the Networking Account, so resources can resolve the services' custom domain names to the VPC Lattice-generated domain name (the consumer services *can know* the service they want to consume needs to be done via VPC Lattice).

The guidance is configured to create the DNS resolution using [Route 53 Private Hosted Zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html). The automation does not create any Private Hosted Zone, nor its association to the VPCs that need to consume the DNS configuration. For this association, we recommend the use of [Route 53 Profiles](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/profiles.html).

### Architecture overview

Below is the Reference architecture diagram and workflow of the Guidance for VPC Lattice automated DNS configuration on AWS. 

<div align="center">

![picture](./assets/amazon-vpc-lattice-automated-dns-configuration-on-aws.png)
Figure 1. VPC Lattice automated DNS configuration on AWS - Reference Architecture
</div>

The architecure workflow is divided in two parts:

* **'Spoke' Account onboarding**. This is executed only once, as the SNS topic created (sending the VPC Lattice service information to the Networking Account) needs to be subscribed to the SQS queue in the Networking Account.
    * (**1**) <!--An [Amazon EventBridge rule](https://aws.amazon.com/eventbridge/) checks if a new SNS topic has been created (it checks for the tag *NewSNS = true*). If so, the event is sent to the Networking Account via a custom event bus, notifying about the topic creation. In the Networking Account, events pushed into the custom event bus are processed by an [AWS Lambda](https://aws.amazon.com/lambda/) function, creating the cross-account subscription of the SNS topic to the SQS queue.-->
      When a new Spoke account deploys automation resources, an [Amazon EventBridge](https://aws-preview.aka.amazon.com/eventbridge/) rule checks that a new [Amazon Simple Notification Service (Amazon SNS)](https://aws-preview.aka.amazon.com/sns/) topic has been created with the proper tag.
* **Creation of DNS Alias records when new VPC Lattice services are created**. Anytime a new VPC Lattice service gets created in an onboarded spoke Account, its DNS information is sent to the networking Account so an Alias record can be created.
    * (**2**) <!-- An EventBridge rule checks the tag in a new VPC Lattice service (*NewService = true*) and invokes a Lambda function which will obtain the DNS information of the VPC Lattice service and publish it to the SNS topic.-->
The New SNS topic EventBridge rule in the spoke account sends the event to the networking account using a [custom event bus](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-event-bus.html) to notify the creation of a new [SNS topic](https://docs.aws.amazon.com/sns/latest/dg/sns-create-topic.html).
    * (**3**) <!-- Once the DNS information of the VPC Lattice service arrives to the SQS queue, a Lambda fuction is called to update the information in the Route 53 Private Hosted Zone.-->
The `SNS subscription` AWS Lambda function is invoked to subscribe the [Amazon Simple Queue Service (Amazon SQS)](https://aws-preview.aka.amazon.com/sqs/) topic in the Networking account to the newly created SNS topic in the Spoke account.
    * (**4**) The New VPC Lattice service EventBridge rule checks for a proper tag in [Amazon VPC Lattice](https://aws-preview.aka.amazon.com/vpc/lattice/).
    * (**5**) The `VPC Lattice service info` Lambda function is invoked to obtain the DNS information of *Amazon VPC Lattice* and publish that information to an SNS topic in the Spoke account.
    * (**6**) The SNS topic in the Spoke account sends the Amazon VPC Lattice DNS information to the Networking account through the [Amazon SQS queue](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-sqs-queue.html).
    * (**7**) Messages arriving to the *Amazon SQS queue* will invoke the Create/Update Alias record Lambda function.
    * (**8**) Unsuccessfully processed messages are stored in the [Amazon SQS dead-letter queue (DLQ)](https://aws-preview.aka.amazon.com/what-is/dead-letter-queue/) for monitoring.
    * (**9**) The `Create/Update Alias record` Lambda function will create and update the corresponding alias record in the [Amazon Route 53](https://aws-preview.aka.amazon.com/route53/) private hosted zone.
    * (**10**) [AWS Systems Manager](https://aws-preview.aka.amazon.com/systems-manager/) and [AWS Resource Access Manager (AWS RAM)](https://aws-preview.aka.amazon.com/ram/) are used for parameter storage and cross-account data sharing.

  
### AWS Services used in this Guidance

| **AWS service**  | Role | Description | Service Availability |
|-----------|------------|-------------|-------------|
| [Amazon EventBridge](https://aws.amazon.com/eventbridge/)| Core service | Rules and custom event buses are used for notifying and detecting new resources.| [Documentation](https://docs.aws.amazon.com/general/latest/gr/ev.html#ev_region) |
[Amazon Lambda](https://aws.amazon.com/lambda/)| Core Service | Serverless functions used for filtering, subscribing and updating information. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/lambda-service.html#lambda_region) |
[Amazon SNS](https://aws.amazon.com/sns/)| Core Service | Simple event information publisher, used for cross-account subscription. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sns.html#sns_region) |
[Amazon SQS](https://aws.amazon.com/sqs/)| Core Service | Simple event information queue, used for cross-account subscription. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sqs-service.html#sqs_region) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)| Support Service | Used to store parameters that will later be shared. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ssm.html#ssm_region) |
[AWS Resource Access Manager (RAM)](https://aws.amazon.com/ram/)| Support Service | Used to share parameters among accounts. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ram.html#ram_region) |

### Cost 

You are responsible for the cost of the AWS services deployed while running this guidance. As of August 2024, the cost of running this Guidance with default settings lies within the Free Tier, except for the use of AWS Systems Manager Advanced Paramter storage.

We recommend creating a [budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html) through [AWS Cost Explorer](http://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. You can also estimate the cost for your architecture solution using [AWS Pricing Calculator](https://calculator.aws/#/). For full details, refer to the pricing webpage for each AWS service used in this Guidance or visit [Pricing by AWS Service](#pricing-by-aws-service).

**Estimated monthly cost breakdown - Networking Account**

This breakdown of the costs of the Networking Account shows that the highest cost of the automation implementation is the [Advanced Parameter Storage](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-advanced-parameters.html) resource from AWS Systems Manager service. The costs are estimated for US East 1 (Virginia) `us-east-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| AWS Systems Manager  | 1 advanced parameters | \$ 0.05 |
| Amazon EventBridge  | <= 1 million custom events | \$ 1.00 |
| AWS Lambda  | < 1 million requests & 400,000 GB-seconds of compute time | \$ 0.00 |
| Amazon SQS | < 1 million requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 1.05/month** |

**Estimated monthly cost breakdown - Spoke Accounts**

The following table provides a sample cost breakdown for deploying this Guidance in 1,000 different spoke Accounts which are likely to provide a VPC Lattice service in the future. The costs are estimated in the Ireland `eu-west-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| Amazon EventBridge  | <= 1 million custom events | \$ 1.00 |
| AWS Lambda  | < 1 million requests & 400,000 GB-seconds of compute time | \$ 0.00 |
| Amazon SNS  | < 1 million requests | \$ 0.00|
| Amazon SQS | < 1 million requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 1.00/month** |

Please see price breakdown details in this [AWS calculator](https://calculator.aws/#/estimate?id=6ee067550372e1563469fded6e9f69d665113897)

**Pricing by AWS Service**

Bellow are the pricing references for each AWS Service used in this Guidance.

| **AWS service**  |  Pricing  |
|-----------|---------------|
|[Amazon EventBridge](https://aws.amazon.com/eventbridge/)| [Documentation](https://aws.amazon.com/eventbridge/pricing/) |
[Amazon Lambda](https://aws.amazon.com/lambda/)|  [Documentation](https://aws.amazon.com/lambda/pricing/) |
[Amazon SNS](https://aws.amazon.com/sns/)|  [Documentation](https://aws.amazon.com/sns/pricing/) |
[Amazon SQS](https://aws.amazon.com/sqs/)| [Documentation](https://aws.amazon.com/sqs/pricing/) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)|  [Documentation](https://aws.amazon.com/systems-manager/pricing/) |

## Prerequisites

### Operating System

This Guidance uses [AWS Serverless](https://aws.amazon.com/serverless/) managed services, so there's no OS patching or management. The Lambda functions are using [Python](https://docs.python.org/3/reference/index.html), and all the code was tested using `Python 3.12`.

### Third-party tools

This solution uses [Terraform](https://www.terraform.io/) as an Infrastructure-as-Code provider. You will need Terraform installed to deploy. These instructions were tested with Terraform version `1.9.3`. You can install Terraform following [Hashicorp's documentation](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli).

For each AWS Account deployment (under the [deployment](https://github.com/aws-solutions-library-samples/guidance-for-vpc-lattice-automated-dns-configuration-on-aws/tree/main/deployment) folder), you will find the following HCL config files:

* *providers.tf* file provides the Terraform and [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) version to use.
* *main.tf* and *iam.tf* provide the resources' configuration. While *main.tf* holds the configuration of the different services, *iam.tf* holds the configuration of IAM roles and policies.
* *variables.tf* defines the input each deployment requirements. Below in the [Deploy the Guidance](#deploy-the-guidance) section, you will see which input variables are required in each AWS Account.

```bash
bash-3.2$ cd guidance-for-vpc-lattice-automated-dns-configuration-on-aws/deployment/networking_account
bash-3.2$ ls
README.md
main.tf
providers.tf
iam.tf
outputs.tf
variables.tf
```
Sample contents of `variables/tf` source file is below:

```bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/networking_account/variables.tf ----------

variable "aws_region" {
  description = "AWS Region to build the automation in the Networking AWS Account."
  type        = string
}

variable "phz_id" {
  description = "Amazon Route 53 Private Hosted Zone ID."
  type        = string
}
```

We use the local backend configuration to store the state files. We recommend the use of another backend configuration that provides you more consistent storage and versioning, for example the use of [Amazon S3 and Amazon DynamoDB](https://developer.hashicorp.com/terraform/language/settings/backends/s3).

### AWS account requirements

These instructions require AWS credentials configured according to the [Terraform AWS Provider documentation](https://registry.terraform.io/providers/-/aws/latest/docs#authentication-and-configuration). 

The credentials must have **IAM permission to create and update resources in the Account** - these persmissions will vary depending the Account type (*networking* or *spoke*). 

In addition, the Guidance supposes your Accounts are part of the same [AWS Organization](https://aws.amazon.com/organizations/) - as IAM policies restrict cross-Account actions between Accounts within the same Organization. For RAM share to work, you need to [enable resource sharing with the Organization](https://docs.aws.amazon.com/ram/latest/userguide/getting-started-sharing.html#getting-started-sharing-orgs).

### Service quotas

Make sure you have sufficient quota for each of the services implemented in this solution. For more information, see [AWS service quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html).

To view the service quotas for all AWS services in the documentation without switching pages, view the information in the [Service endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/aws-general.pdf#aws-service-information) page in the PDF instead.

## Deploy the Guidance 

| **Account type** |  **Deployment time (min)**  |
|------------------|-----------------------------|
| Networking       | 3                           | 
| Spoke            | 2                           |

<!--
**TO DO - REPLACE THE IG LINK BELOW WITH PRODUCTION VERSION**

Please see the detailed Implementation Guide [here](https://implementationguides.kits.eventoutfitters.aws.dev/vpc-lattice-0716/networking/vpc-lattice-automated-dns-configuration.html)
-->

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for more information.
