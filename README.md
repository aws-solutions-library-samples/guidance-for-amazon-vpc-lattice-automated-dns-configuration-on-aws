# Guidance for VPC Lattice automated DNS configuration on AWS

This guidance automates the creation of DNS (Domain Name System) resolution configuration in [Amazon Route 53](https://aws.amazon.com/route53/) when creating new [Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/) services with custom domain names.

While this README provides an overview of the Guidance Solution, its architecture, and deployment steps; you can get a more detailed documentation in the Implementation Guide (Link TBC).

## Background

### What is Amazon VPC Lattice?

Amazon VPC Lattice is an application networking service that simplifies the connectivity, monitoring, and security between your services. Its main benefits are the configuration and management simplification, allowing developers to focus on building features while Networking & Security administrators can provide guardrails in the services’ communication. 

The service simplifies the onboarding experience for developers by removing the need to implement custom application code, or run additional proxies next to every workload, while maintaining the tools and controls network admins require to audit and secure their environment. VPC Lattice leverages DNS for service discovery, so each VPC Lattice service is easily identifiable through its service-managed or custom domain names. However, for custom domain names, extra configuration is needed to allow DNS resolution for the consumer workloads. 

### Solution reasoning

When a new VPC Lattice service is created, a service-managed domain name is generated. This domain name is publicly resolvable and resolves either in an IPv4 link-local address or an IPv6 unique-local address. So, a consumer application using this service-managed domain name does not require any extra DNS configuration for the service-to-service communication (provided the VPC Lattice configuration allows connectivity). However, it's more likely that you will with to use your own custom domain names.

When using custom domain names for VPC Lattice services, an Alias (for Amazon Route 53 hosted zones) or CNANE (if you use another DNS solution) have to be created to map the custom domain name with the service-managed domain name. In multi-Account environments, the creation of the DNS resolution configuration can create heavy operational overhead. Each VPC Lattice service created (by each developers' team) will require a central Networking team to be notified with the information about the new service created and the required DNS resolution to be configured.

This Guidance Solution builds and automation - to be created in a central Networking AWS Account and each Spoke AWS Account creating VPC Lattice services - to automate the configuration of DNS resolution anytime a new VPC Lattice service (with a custom domain name configured) is created.

## Architecture overview

Below is the architecture diagram workflow of the Amazon VPC Lattice automated DNS configuration for multi-Account environments. 

<div align="center">

![reference_architecture](/assets/reference_architecture_numbers.png)

<br/>
<i>Figure 1: Amazon VPC Lattice automated DNS configuration workflow. </i>
</div>
<br/>

The Guidance Solution architecture is divided in two parts:

* **Spoke Account onboarding**. This is executed only once, as the [Amazon Simple Notification Service (SNS)](https://aws.amazon.com/sns/) topic created (getting the information about the new VPC Lattice services created) needs to be subscribed to the [Amazon Simple Queue Service (SQS)](https://aws.amazon.com/sqs/) queue in the Networking Account. 
    1. An [Amazon EventBridge](https://aws.amazon.com/eventbridge/) rule checks if a new SNS topic has been created (it checks for the tag *NewSNS = true*). If so, the event is sent to the Networking Account via a custom event bus, notifying about the topic creation. In the Networking Account, events pushed into the custom event bus are processed by an [AWS Lambda](https://aws.amazon.com/lambda/) function, creating the cross-account subscription of the SNS topic to the SQS queue.
* **Creation of Alias records when new VPC Lattice services are created**. Anytime a new VPC Lattice service gets created in an onboarded spoke Account, its DNS information is sent to the networking Account so an Alias record can be created.
    2. An EventBridge rule checks the tag in a new VPC Lattice service (*NewService = true*) and invokes a Lambda function which will obtain the DNS information of the VPC Lattice service and publish it to the SNS topic.
    3. Once the DNS information of the VPC Lattice service arrives to the SQS queue, a Lambda fuction is called to update the information in the Route 53 Private Hosted Zone.

### AWS services used in this Guidance

| **AWS service** | Role | Description | Service Availability |
|-----------------|------|-------------|----------------------|
| [Amazon EventBridge](https://aws.amazon.com/eventbridge/)| Core service | Rules and custom event buses are used for notifying and detecting new resources.| [Documentation](https://docs.aws.amazon.com/general/latest/gr/ev.html#ev_region) |
| [Amazon Lambda](https://aws.amazon.com/lambda/)| Core Service | Serverless functions used for filtering, subscribing and updating information. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/lambda-service.html#lambda_region) |
| [Amazon SNS](https://aws.amazon.com/sns/)| Core Service | Simple event information publisher, used for cross-account data sharing. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sns.html#sns_region) |
| [Amazon SQS](https://aws.amazon.com/sqs/)| Core Service | Simple event information queue, used for cross-account data sharing. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sqs-service.html#sqs_region) |
| [AWS Systems Manager Parameter Store](https://aws.amazon.com/systems-manager/)| Support Service | Used to store parameters that will later be shared. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ssm.html#ssm_region) |
| [AWS Resource Access Manager (RAM)](https://aws.amazon.com/ram/)| Support Service | Used to share resources between AWS Accounts. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ram.html#ram_region) |

### Considerations

1. This Guidance Solution supposses that all the AWS Accounts in your environment are within the same [AWS Organization](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_introduction.html). All the AWS RAM principal associations are done to the AWS Account's Organization ID, and IAM Roles are only allowing actions within resources in the same Organization.
    * You will need to change some pieces of code if you want to use this Guidance Solution automation between AWS Accounts outside of the Organization.
2. Encryption at rest is configured in the SNS topic and SQS queues, using AWS-managed keys. Systems Manager paramters are not configured with `SecureString` due they must be encrypted with a customer managed key, and you must share the key separately through [AWS Key Management Service](https://aws.amazon.com/kms/) (KMS).
    * If you would like to use customer managed keys to encrypt at rest the data of all these services, you will need to configure this option (we decided not to create key resources on your behalf). Check the Implementation Guide (LINK TBD) for more information about this configuration.

## Cost 

You are responsible for the cost of the AWS services used while running this solution guidance. As of August 2024, the cost of running this Guidance Solution with default settings lies within the Free Tier, except for the use of AWS Systems Manager Advanced Paramter storage.

We recommend creating a [budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html) through [AWS Cost Explorer](http://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. You can also estimate the cost for your architecture solution using [AWS Pricing Calculator](https://calculator.aws/#/). For full details, refer to the pricing webpage for each AWS service used in this Guidance or visit [Pricing by AWS Service](#pricing-by-aws-service).

### Estimated monthly cost breakdown - Networking Account

This breakdown of the costs of the Networking Account shows that the highest cost of the automation implementation is the Advanced Parameter Storage resource from AWS Systems Manager service. The costs are estimated in the Ireland `eu-west-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| AWS Systems Manager  | 1 advanced parameters | \$ 0.05 |
| Amazon EventBridge  | < 1 million custom events | \$ 0.00 |
| AWS Lambda  | < 1 million requests & 400,000 GB-seconds of compute time | \$ 0.00 |
| Amazon SQS | < 1 million requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 0.05** |

### Estimated monthly cost breakdown - Spoke Accounts

The following table provides a sample cost breakdown for deploying this Guidance Solution in 1,000 different spoke Accounts which are likely to provide a VPC Lattice service in the future. The costs are estimated in the Ireland `eu-west-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| Amazon EventBridge  | < 1 million custom events | \$ 0.00 |
| AWS Lambda  | < 1 million requests & 400,000 GB-seconds of compute time | \$ 0.00 |
| Amazon SNS  | < 1 million requests | \$ 0.00|
| Amazon SQS | < 1 million requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 0.00** |

### Pricing by AWS Service

Bellow are the pricing references for each AWS Service used in this Guidance Solution.

| **AWS service**  |  Pricing  |
|-----------|---------------|
|[Amazon EventBridge](https://aws.amazon.com/eventbridge/)| [Documentation](https://aws.amazon.com/eventbridge/pricing/) |
[Amazon Lambda](https://aws.amazon.com/lambda/)|  [Documentation](https://aws.amazon.com/lambda/pricing/) |
[Amazon SNS](https://aws.amazon.com/sns/)|  [Documentation](https://aws.amazon.com/sns/pricing/) |
[Amazon SQS](https://aws.amazon.com/sqs/)| [Documentation](https://aws.amazon.com/sqs/pricing/) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)|  [Documentation](https://aws.amazon.com/systems-manager/pricing/) |

## Deployment 

The deployment code uses [Terraform](https://www.terraform.io/) as Infrastructure-as-Code framework. Make sure to have Terraform installed before deploying the solution. In this code, we use the local backend configuration to store the state files. We recommend the use of another backend configuration that provides you more consistent storage and versioning, for example the use of [Amazon S3 and Amazon DynamoDB](https://developer.hashicorp.com/terraform/language/settings/backends/s3).

Below are the instructions to deploy the automation:

1. **Networking AWS Account**.
    * Variables needed: AWS Region to deploy the resources, and Private Hosted ID to create the Alias records.
    * Locate yourself in the [network_account](./deployment/networking_account/) folder and configure the AWS credentials of your Networking Account.

```
cd deployment/networking_account
(configure AWS credentials)
terraform init
terraform validate
terraform plan
terraform apply
```

2. **Spoke AWS Account**. Follow this process for each spoke Account in which you are creating VPC Lattice services.
    * Variables needed: AWS Region to deploy the resources, and Networking Account ID.
    * Locate yourself in the [spoke_account](./deployment/networking_account/) folder and configure the AWS credentials of your Spoke Account.

```
cd deployment/spoke_account
(configure AWS credentials)
terraform init
terraform validate
terraform plan
terraform apply
```

Move to the [deployment](./deployment/) folder for more information about this Guidance Solution's deployment code. If you want to deploy an end-to-end solution (with VPC Lattice resources), move to the [test](./test/) folder to know how to deploy this Guidance Solution with a test environment.

### Clean-up

1. In each **Spoke AWS Account** that you want to offboard, delete the Guidance Solution automation.

```
cd deployment/spoke_account
(configure AWS credentials)
terraform destroy
```

2. Make sure in the **Networking AWS Account** that the SNS topic of the Account offboard is no longer subscribed to the SQS queue.
3. In the **Networking AWS Account**, delete the Guidance Solution automation. Make sure the Private Hosted Zone does not have any Alias record created by the automation.

```
cd deployment/networking_account
(configure AWS credentials)
terraform destroy
```

## Security

When you build systems on AWS infrastructure, security responsibilities are shared between you and AWS. This [shared responsibility model](https://aws.amazon.com/compliance/shared-responsibility-model/) reduces your operational burden because AWS operates, manages, and controls the components including the host operating system, the virtualization layer, and the physical security of the facilities in which the services operate. For more information about AWS security visit [AWS Cloud Security](http://aws.amazon.com/security/).

This guidance relies on a lot of reasonable default options and "principle of least privilege" access for all resources. Users that deploy it in production should go through all the deployed resources and ensure those defaults comply with their security requirements and policies, have adequate logging levels and alarms enabled and protect access to publicly exposed APIs. In SQS and SNS, the Resource Policies are defined such that only the specified account/organization/resource can access such resource. IAM Roles are defined for AWS Lambda to only access the corresponding resources such as EventBridge, SQS and SNS. AWS RAM securely shares resource parameter such as SQS queue ARN and Eventbridge custom event bus ARN. This limits the access to the VPC Lattice DNS resolution automation to the configuration resources and involved accounts only.

**NOTE**: Please note that by cloning and using 3rd party open-source code you assume responsibility for its patching/securing/managing in the context of this project.

### Quotas for AWS services in this Guidance

Make sure you have sufficient quota for each of the services implemented in this solution. For more information, see [AWS service quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html).

To view the service quotas for all AWS services in the documentation without switching pages, view the information in the [Service endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/aws-general.pdf#aws-service-information) page in the PDF instead.
