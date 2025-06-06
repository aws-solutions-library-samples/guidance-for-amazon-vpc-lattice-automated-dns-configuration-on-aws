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
3. [Security](#security)
    - [Encryption at rest](#encryption-at-rest)
4. [Deploy the Guidance](#deploy-the-guidance)
5. [Unistall the Guidance](#uninstall-the-guidance)
6. [Technical Deep Dive](#technical-deep-dive)
    - [DNS configuration in VPC Lattice](#dns-configuration-in-vpc-lattice)
    - [Networking Account Configuration](#networking-account-configuration)
    - [Spoke Account Configuration](#spoke-account-configuration)
    - [AWS CloudFormation Custom Resources](#aws-cloudformation-custom-resources)
7. [Related resources](#related-resources)
8. [Contributors](#contributors)
9. [License](#license)
10. [Contributing](#contributing)

## Overview

[Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/) is an application networking service that simplifies connectivity, monitoring, and security between your services. Its main benefits are the configuration and management simplification, allowing developers to focus on building features while Networking & Security administrators can provide guardrails in the services’ communication. The service simplifies the onboarding experience for developers by removing the need to implement custom application code, or run additional proxies next to every workload, while maintaining the tools and controls network admins require to audit and secure their environment. 

VPC Lattice leverages [Domain Name System (DNS)](https://aws.amazon.com/route53/what-is-dns/) for service discovery, so each VPC Lattice service is easily identifiable through its service-managed or custom domain names. However, for custom domain names, extra manual configuration is needed to allow DNS resolution for the consumer workloads. This guidance automates the configuration of DNS resolution anytime a new VPC Lattice service (with a custom domain name configured) is created.

### Features and benefits 

This guidance provides the following features:

1. **Seamless service discovery with VPC Lattice when using custom domain names**. 
    * All the DNS resolution is configured in the Private Hosted Zone you desire.
    * Anytime a VPC Lattice service is created/deleted in any AWS Account, its DNS information (custom and service-managed domain names for created resources) is sent to the AWS Account managing the DNS configuration. This message is processed by creating/deleting an [Alias record](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html).

2. **Automation resources are built using Infrastructure-as-Code**.
    * [AWS CloudFormation](https://aws.amazon.com/cloudformation/) or [Hashicorp Terraform](https://www.terraform.io/) are used as options for the guidance automated code deployment.
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

![picture](./assets/vpc-lattice-dns-reference-architecture.png)
Figure 1. VPC Lattice automated DNS configuration on AWS - Reference Architecture
</div>

(**1**) When a new spoke Account creates a new VPC Lattice service, an [Amazon EventBridge](https://aws.amazon.com/eventbridge/) rule checks that a new [VPC Lattice](https://aws.amazon.com/vpc/lattice/) service has been created with the proper tag. The EventBridge rule also checks whether a VPC Lattice service has been deleted, from the deletion of such tag.

(**2**) The EventBridge rule is configured with a target pointing to the `cross_account` Event Bus in the Networking Account.

(**3**) Unsuccessfully processed delivery events are stored in the [Amazon SQS dead-letter queue (DLQ)](https://aws.amazon.com/what-is/dead-letter-queue/) in the Spoke Account for monitoring.

(**4**) The `cross_account` custom Event Bus in the Networking Account invokes the `DNS configuration` [AWS Step Functions](https://aws.amazon.com/step-functions/) state machine to process the notification send by the Spoke Account.

(**5**) Unsuccessfully processed delivery events are stored in the DLQ in the Networking Account for monitoring.

(**6**) The `DNS configuration` state machine will create/delete the corresponding Alias record in the [Amazon Route 53](https://aws.amazon.com/route53/) [Private Hosted Zone](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html).

(**7**) An [Amazon DynamoDB](https://aws.amazon.com/dynamodb/) table is used to track the records created. The state machine will use this information during the deletion process.

(**8**) [AWS Systems Manager](https://aws.amazon.com/systems-manager/) and [AWS Resource Access Manager (AWS RAM)](https://aws.amazon.com/ram/) are used for secure parameter storage and cross-account data sharing.

### AWS Services used in this Guidance

| **AWS service**  | Role | Description | Service Availability |
|-----------|------------|-------------|-------------|
|[Amazon EventBridge](https://aws.amazon.com/eventbridge/)| Core service | Rules and custom event buses are used for notifying and detecting new resources.| [Documentation](https://docs.aws.amazon.com/general/latest/gr/ev.html#ev_region) |
[AWS Step Functions](https://aws.amazon.com/step-functions/)| Core Service | Serverless state machine used for filtering, subscribing and updating information. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/step-functions.html#ram_region) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)| Support Service | Used to store parameters that will later be shared. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ssm.html#ssm_region) |
[AWS Resource Access Manager (RAM)](https://aws.amazon.com/ram/)| Support Service | Used to share parameters among accounts. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ram.html#ram_region) |
[Amazon Simple Queue Service (SQS)](https://aws.amazon.com/sqs/)| Support Service | Used to store unprocessed messages for troubleshooting. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sqs-service.html#ram_region)
[Amazon DynamoDB](https://aws.amazon.com/dynamodb/)| Support Service | Used to track DNS records created (for the deletion process). | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ddb.html)

### Cost 

You are responsible for the cost of the AWS services deployed while running this guidance. As of November 2024, the cost of running this Guidance with default settings lies within the Free Tier, except for the use of AWS Systems Manager Advanced Paramter storage.

We recommend creating a [budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html) through [AWS Cost Explorer](http://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. You can also estimate the cost for your architecture solution using [AWS Pricing Calculator](https://calculator.aws/#/). For full details, refer to the pricing webpage for each AWS service used in this Guidance or visit [Pricing by AWS Service](#pricing-by-aws-service).

**Estimated monthly cost breakdown - Networking Account**

This breakdown of the costs of the Networking Account shows that the highest cost of the implementation is the [Advanced Parameter Storage](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-advanced-parameters.html) resource from AWS Systems Manager service. The costs are estimated for US East 1 (Virginia) `us-east-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| AWS Systems Manager | 1 advanced parameter | \$ 0.05 |
| Amazon EventBridge  | <= 1 million custom events | \$ 1.00 |
| AWS Step Functions  | < 4,000 state transitions | \$ 0.00 |
| Amazon SQS          | < 1 million requests/month | \$ 0.40 |
| Amazon DynamoDB     | < 100 standard reads & writes | \$ 0.82 |
| **TOTAL estimate** |  | **\$ 2.27/month** |

Please see price breakdown details in this [AWS calculator](https://calculator.aws/#/estimate?id=e0185739794818a1a6dbc6c85a9659403784b3dc)

**Estimated monthly cost breakdown - Spoke Accounts**

The following table provides a sample cost breakdown for deploying this Guidance in 1,000 different spoke Accounts which are likely to provide a VPC Lattice service in the future. The costs are estimated for US East 1 (Virginia) `us-east-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| Amazon EventBridge  | <= 1 million custom events | \$ 1.00 |
| Amazon SQS          | <= 1 million requests/month | \$ 0.40 |
| **TOTAL estimate** |  | **\$ 1.40/month** |

Please see price breakdown details in this [AWS calculator](https://calculator.aws/#/estimate?id=1e434ca4615bd10af648d638eebee3f23f1c06cb)

**Pricing by AWS Service**

Bellow are the pricing references for each AWS Service used in this Guidance.

| **AWS service**  |  Pricing  |
|-----------|---------------|
|[Amazon EventBridge](https://aws.amazon.com/eventbridge/)| [Documentation](https://aws.amazon.com/eventbridge/pricing/) |
[AWS Step Functions](https://aws.amazon.com/step-functions/)|  [Documentation](https://aws.amazon.com/step-functions/pricing/) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)|  [Documentation](https://aws.amazon.com/systems-manager/pricing/) |
[Amazon Simple Queue Service (SQS)](https://aws.amazon.com/sqs/)| [Documentation](https://aws.amazon.com/sqs/pricing/) |
[Amazon DynamoDB](https://aws.amazon.com/dynamodb/)| [Documentation](https://aws.amazon.com/dynamodb/pricing/)

## Prerequisites

### Operating System

This Guidance uses [AWS Serverless](https://aws.amazon.com/serverless/) managed services, so there's no OS patching or management.

### Third-party tools

For this solution you can either use [AWS CloudFormation](https://aws.amazon.com/cloudformation/) or [Hashicorp Terraform](https://www.terraform.io/) as an Infrastructure-as-Code provider. **For Terraform, check the requirements below**.

You will need Terraform installed to deploy. These instructions were tested with Terraform version `1.9.3`. You can install Terraform following [Hashicorp's documentation](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli). In addition, AWS credentials need to be configured according to the [Terraform AWS Provider documentation](https://registry.terraform.io/providers/-/aws/latest/docs#authentication-and-configuration).

For each AWS Account deployment (under the [deployment/terraform](https://github.com/aws-solutions-library-samples/guidance-for-vpc-lattice-automated-dns-configuration-on-aws/tree/main/deployment/terraform) folder), you will find the following HCL config files:

* *providers.tf* file provides the Terraform and [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) version to use.
* *main.tf* and *iam.tf* provide the resources' configuration. While *main.tf* holds the configuration of the different services, *iam.tf* holds the configuration of IAM roles and policies.
* *variables.tf* defines the input each deployment requirements. Below in the [Deploy the Guidance](#deploy-the-guidance) section, you will see the link to the Deployment Guide for more information about the deployment steps.

```bash
bash-3.2$ cd guidance-for-vpc-lattice-automated-dns-configuration-on-aws/deployment/terraform/networking_account
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

The credentials must have **IAM permission to create and update resources in the Account** - these persmissions will vary depending the Account type (*networking* or *spoke*). 

In addition, the Guidance supposes the following:

* Your Accounts are part of the same [AWS Organization](https://aws.amazon.com/organizations/) - as IAM policies restrict cross-Account actions between Accounts within the same Organization. For RAM share to work, you need to [enable resource sharing with the Organization](https://docs.aws.amazon.com/ram/latest/userguide/getting-started-sharing.html#getting-started-sharing-orgs).
* Any VPC Lattice service created within the Organization has been shared with the Networking Account. This way, the [RAM share permissions](https://docs.aws.amazon.com/vpc-lattice/latest/ug/sharing.html#cross-account-events) allow the Networking Account to perform the `get-service` action.

### Service quotas

Make sure you have sufficient quota for each of the services implemented in this solution. For more information, see [AWS service quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html).

To view the service quotas for all AWS services in the documentation without switching pages, view the information in the [Service endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/aws-general.pdf#aws-service-information) page in the PDF instead.

## Security

When you build systems on AWS infrastructure, security responsibilities are shared between you and AWS. This [shared responsibility model](https://aws.amazon.com/compliance/shared-responsibility-model/) reduces your operational burden because AWS operates, manages, and controls the components including the host operating system, the virtualization layer, and the physical security of the facilities in which the services operate. For more information about AWS security visit [AWS Cloud Security](http://aws.amazon.com/security/).

This guidance relies on many reasonable default options and "principle of least privilege" access for all resources. Users that deploy it in production should go through all the deployed resources and ensure those defaults comply with their security requirements and policies, have adequate logging levels and alarms enabled, and protect access to publicly exposed APIs. In Amazon SQS and Amazon SNS, the resource policies are defined such that only the specified account, organization, or resource can access such resource. IAM roles are defined for Lambda to only access the corresponding resources such as EventBridge, Amazon SQS, and Amazon SNS. AWS RAM securely shares resource parameter such as SQS queue ARN and EventBridge custom event bus ARN. This limits the access to the Amazon VPC Lattice DNS resolution automation to the configuration resources and involved accounts only.

**NOTE**: Please note that by cloning and using third party open-source code, you assume responsibility for its patching, securing, and managing in the context of this project.

### Encryption at rest

Encryption at rest is configured in the SQS queues (DLQ), using AWS-managed keys. Systems Manager parameters are not configured as `SecureString` due to the fact that they must be encrypted with a customer managed key, and you must share the key separately through AWS Key Management Service (AWS KMS).

* Given its sensitivity, we are not creating any AWS KMS resource in this guidance.
* If you would like to use customer managed keys to encrypt at rest the data of all these services, you will need to change the code to configure this option in the corresponding resources:
    * [SQS queue](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-server-side-encryption.html)
    * [Systems Manager parameter](https://docs.aws.amazon.com/kms/latest/developerguide/services-parameter-store.html).

## Deploy the Guidance 

| **Account type** |  **Deployment time (min) - CloudFormation**  | **Deployment time (min) - Terraform** |
|------------------|----------------------------------------------|---------------------------------------|
| Networking       | 3                                            | 1                                     |
| Spoke            | 3                                            | 1                                     |

### AWS CloudFormation

1. **Networking AWS Account**
    * *Variables needed*: Private Hosted Zone ID to create/delete Alias records.
    * Locate yourself in the [deployment/cloudformation](./deployment/cloudformation/) folder and configure the AWS credentials of your Networking Account.

```bash
aws cloudformation deploy --stack-name {STACK_NAME} --template-file ./deployment/cloudformation/networking_account.yaml --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --parameter-overrides PrivateHostedZone={ZONE_ID} --region {REGION}
```

2. **Spoke AWS Account**. Follow this process for each spoke Account in which you are creating VPC Lattice services.
    * Locate yourself in the [deployment/cloudformation](./deployment/cloudformation/) folder and configure the AWS credentials of your Spoke Account.

```bash
aws cloudformation deploy --stack-name {STACK_NAME} --template-file ./deployment/cloudformation/spoke_account.yaml --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --region {REGION}
```

### Terraform

1. **Networking AWS Account**
    * *Variables needed*: AWS Region to deploy the resources, and Private Hosted Zone ID to create/delete Alias records.
    * Locate yourself in the [networking_account](./deployment/terraform/networking_account/) folder and configure the AWS credentials of your Networking Account.

```bash
cd deployment/networking_account
(configure AWS credentials)
...
terraform init
terraform apply
```

2. **Spoke AWS Account**. Follow this process for each spoke Account in which you are creating VPC Lattice services.
    * *Variables needed*: AWS Region to deploy the resources, and Networking Account ID.
    * Locate yourself in the [spoke_account](./deployment/terraform/spoke_account/) folder and configure the AWS credentials of your Spoke Account.

```bash
cd deployment/spoke_account
(configure AWS credentials)
...
terraform init
terraform apply
```

### Test environment

In the [test](./test/) folder you will find a test environment if you want to check and test an end-to-end implementation using the solution.

## Uninstall the Guidance

### AWS CloudFormation

1. (Optional) If you want to clean-up the Alias records created, make sure you have removed the corresponding VPC Lattice services (or tags).
2. In each Spoke Account you want to offboard, delete the guidance automation.

```bash
aws cloudformation delete-stack --stack-name {STACK_NAME} --region {REGION}
```

3. In the Networking Account, delete the guidance automation.

```bash
aws cloudformation delete-stack --stack-name {STACK_NAME} --region {REGION}
```

### Terraform

1. (Optional) If you want to clean-up the Alias records created, make sure you have removed the corresponding VPC Lattice services (or tags).
2. In each Spoke Account you want to offboard, delete the guidance automation.

```bash
cd deployment/spoke_account
(configure AWS credentials)
terraform destroy
```

3. In the Networking Account, delete the guidance automation.

```bash
cd deployment/spoke_account
(configure AWS credentials)
terraform destroy
```

## Technical Deep Dive

### DNS configuration in VPC Lattice

When a new Amazon VPC Lattice service is created, a service-managed domain name is generated. This domain name is publicly resolvable and resolves either to an IPv4 link-local address or an IPv6 unique-local address. In addition, when a [service network VPC endpoint](https://docs.aws.amazon.com/vpc/latest/privatelink/access-with-service-network-endpoint.html) has been created, another domain name is generated per each VPC Lattice service associated to this endpoint - this domain name now resolves to the IP address of such endpoint.

A consumer application using any of these service-managed domain names does not require any extra DNS configuration for the service-to-service communication (provided the VPC Lattice configuration allows connectivity). However, it’s more likely that you will use your own custom domain names. When using custom domain names for Amazon VPC Lattice services, an [alias](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/ResourceRecordTypes.html) (for Amazon Route 53 hosted zones) or [CNAME](https://support.dnsimple.com/articles/cname-record/) (if you use another DNS solution) have to be created to map the custom domain name with the service-managed domain name. In multi-account environments, the creation of the DNS resolution configuration can create heavy operational overhead. Each Amazon VPC Lattice service created (by each developers’ team) will require a central networking team to be notified with the information about the new service created and the required DNS resolution to be configured.

### Networking Account configuration

**Amazon EventBridge**

A [custom event bus](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-bus.html) (*cross_account_eventbus*) is configured to receive events from all the spoke AWS Accounts in the Organization.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowOrgAccess",
    "Effect": "Allow",
    "Principal": {
      "AWS": "*"
    },
    "Action": ["events:PutRule", "events:PutEvents"],
    "Resource": "arn:aws:events:{REGION}:{ACCOUNT_ID}:event-bus/cross_account_eventbus",
    "Condition": {
      "StringEquals": {
        "aws:PrincipalOrgID": "{ORG_ID}"
      }
    }
  }]
}
```

This event bus' rule will be similar to the one configured in the Spoke Accounts: any change in VPC Lattice service tag *NewService* will be processed. The target of this rule is the Step Functions state machine.

```json
{
  "detail": {
    "changed-tag-keys": ["NewService"],
    "resource-type": ["service"],
    "service": ["vpc-lattice"]
  },
  "detail-type": ["Tag Change on Resource"],
  "source": ["aws.tag"]
}
```

**AWS Step Functions State Machine**

<div align="center">

![picture](./assets/stepfunctions_graph.png)
Figure 2. Networking AWS Account state machine
</div>

Above you can find the Step Functions state machine definition for the Networking AWS Account. The first state will check the type of action to perform: 

* Create the Alias records if the *NewService* tag is equals to *true*.
* Clean-up the Alias records if the *NewService* tag has been deleted.

For the **creation of Alias records**, the following actions are performed:

1. A `GetService` state will obtain the information from the VPC Lattice service created in the Spoke AWS Account.
2. A [parallel workflow state](https://docs.aws.amazon.com/step-functions/latest/dg/state-parallel.html) will handle the following actions:
    * Two states will create the corresponding DNS configuration: A (IPv4) & AAAA (IPv6) Alias records.
    * The VPC Lattice service ARN, custom domain name, and VPC Lattice-generated domain name will be tracked in an DynamoDB table.

<div align="center">

![picture](./assets/stepfunctions_creation_parallel.png)

Figure 3. Networking AWS Account state machine: creating of Alias records and tracking in DynamoDB
</div>

For the **clean-up of Alias records**, the following actions are performed:

1. A `GetItem` state will obtain the DNS configuration created from the VPC Lattice service ARN.
2. A parallel workflow state will handle the following actions:
    * The item in the DynamoDB table will be deleted.
    * The Hosted Zone records will be obtained and a [map state](https://docs.aws.amazon.com/step-functions/latest/dg/state-map.html) will iterate over them to find the Alias records that need to be deleted.s

<div align="center">

![picture](./assets/stepfunctions_creation_parallel.png)

Figure 4. Networking AWS Account state machine: clean-up of Alias records and DynamoDB item
</div>

For malformed events, the state machine will end without any actions taken.

### Spoke Account Configuration

**Amazon EventBridge**

An EventBridge rule (default event bus) is configured to catch the creation/deletion of VPC Lattice services. Given VPC Lattice does not support EventBridge events, we use the aws.tag source.

```json
{
  "detail": {
    "changed-tag-keys": ["NewService"],
    "resource-type": ["service"],
    "service": ["vpc-lattice"]
  },
  "detail-type": ["Tag Change on Resource"],
  "source": ["aws.tag"]
}
```

The target of this rule is the custom event bus (*cross_account_eventbus*) in the Networking AWS Account.

### AWS CloudFormation Custom Resources

In the AWS CloudFormation deployment code, two [custom resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources.html) are used to obtain the AWS Organization ID (Networking AWS Account) and retrieve the AWS Systems Manager parameters shared (Spoke AWS Account). **These custom resources can be removed if the corresponding variables are passed as parameters**.

* **Networking AWS Account** - Retrieving AWS Organization ID

```python
import logging
import boto3
import json
import cfnresponse
from botocore.exceptions import ClientError

log = logging.getLogger("handler")
log.setLevel(logging.INFO)

org = boto3.client('organizations')

def lambda_handler(event, context):
    try:
        log.info("Received event: %s", json.dumps(event))
        request_type = event['RequestType']
        response = {}

        if request_type == 'Create':
            org_info = org.describe_organization()
            response['Id'] = org_info['Organization']['Id']
            response['Arn'] = org_info['Organization']['Arn']
                  
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response)
                  
    except:
        log.exception("whoops")
        cfnresponse.send(
            event,
            context,
            cfnresponse.FAILED,
            {},
            reason="Caught exception, check logs",
        )
```

* **Spoke AWS Account** - Retrieving AWS SSM parameters' values (shared by the Networking Account)

```python
import logging
import boto3
import json
import cfnresponse
from botocore.exceptions import ClientError

log = logging.getLogger("handler")
log.setLevel(logging.INFO)

ssm = boto3.client('ssm')

def lambda_handler(event, context):
    try:
        log.info("Received event: %s", json.dumps(event))
        request_type = event['RequestType']
        response = {}

        if request_type == 'Create':
            parameter_name = event["ResourceProperties"]['ParameterName']

            parameter_arn = ssm.describe_parameters(
                Filters=[
                    {
                        'Key': 'Name',
                        'Values': [
                            parameter_name,
                        ]
                    },
                ],
                MaxResults=5,
                Shared=True
            )['Parameters'][0]['ARN']
                    
            value = ssm.get_parameter(
                Name=parameter_arn
            )['Parameter']['Value']

            response['Value'] = value
                  
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response)
                  
    except:
        log.exception("whoops")
        cfnresponse.send(
            event,
            context,
            cfnresponse.FAILED,
            {},
            reason="Caught exception, check logs",
        )
```

## Related resources

* Blog post: [Managing DNS resolution with Amazon VPC Lattice and VPC resources](https://aws.amazon.com/blogs/networking-and-content-delivery/managing-dns-resolution-with-amazon-vpc-lattice-and-vpc-resources/)
* Blog Post: [Amazon VPC Lattice DNS migration strategies and best practices](https://aws.amazon.com/blogs/networking-and-content-delivery/amazon-vpc-lattice-dns-migration-strategies-and-best-practices/)

## Contributors

The following individuals contributed to this document:

* Maialen Loinaz Antón, Associate Solutions Architect
* Pablo Sánchez Carmona, Sr Networking Specialist Solutions Architect

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for more information.
