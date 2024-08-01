# Guidance for VPC Lattice automated DNS configuration on AWS

This guidance automates the creation of the DNS resolution (in multi-Account environments) needed when creating [Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/) services with custom domain names.

Amazon VPC Lattice is an application networking service that simplifies the connectivity, monitoring, and security of applications within [Amazon Web Services (AWS)](https://aws.amazon.com) Cloud. The main benefits of the service is the configuration and management simplification, allowing developers to focus on building features while Networking & Security administrators can provide guardrails in the services’ communication. Now configuration is not based on IPs, rather on DNS resolution. However, when defining custom domain names for the different services, some extra configuration steps are needed to allow proper DNS resolution in multi-Account environments. This Guidance Solution will automate [Amazon Route 53](https://aws.amazon.com/route53/) DNS configuration from Amazon VPC Lattice actions (create and remove services) in multi-Account environments.

### Solution reasoning
In a multi-account environment where Route53 Profiles and Private Hosted Zones are implemented, the DNS resolution of a new VPC Lattice service is updated or created as a new ALIAS record manually. However, when the amount of services scale, this task becomes challenging. This solution automates the update of the DNS configuration when a new VPC Lattice service is created. More information about the solution and its recommended architecture can be found in the implementation guidance (add link).

## Architecture overview
Below is the architecture diagram workflow of the Amazon VPC Lattice automated DNS configuration in multi-account environment. The workflow is divided in 2 parts:
- The **first part** (step 1) is executed only once, during the onboarding of the spoke accounts to the central account.
- The **second part** (steps 2 & 3) is performed whenever a new VPC Lattice service is created.



<div align="center">

![picture](/vpc_lattice_dns_images/reference_architecture_numbers.png)

<br/>
<i>Figure 1: Amazon VPC Lattice automated DNS configuration workflow. </i>
</div>
<br/>

First part, onboarding:

1. Once the automation resources are deployed in the account, an [Amazon EventBridge](https://aws.amazon.com/eventbridge/) rule checks if a new [Amazon Simple Notification Service (SNS)](https://aws.amazon.com/sns/) topic has been created. If so, the event is sent to the Networking Account to a custom event bus, notifying about the topic creation. This process invokes the [AWS Lambda](https://aws.amazon.com/lambda/) function responisble for the cross-account subscription of the [Amazon Simple Queue Service (SQS)](https://aws.amazon.com/sqs/) queue in the Networking account to the SNS topic of the spoke account.<br/>

Second part, new VPC Lattice Service:

2. An EventBridge rule checks the tag in a new VPC Lattice service and invokes a Lambda function which will obtain the DNS information of the new VPC Lattice service and publish it to the SNS topic.<br/>
3. Once the DNS information of the VPC Lattice service arrives to the SQS queue, the Lambda fuction is called to update the information in the Route53 Private Hosted Zone .<br/>
<br/>


### AWS services used in this Guidance

| **AWS service**  | Role | Description |   Service Availability |
|-----------|------------|-------------|-------------|
| [Amazon EventBridge](https://aws.amazon.com/eventbridge/)| Core service | Rules and custom event buses are used for notifying and detecting new resources.| [Documentation](https://docs.aws.amazon.com/general/latest/gr/ev.html#ev_region) |
[Amazon Lambda](https://aws.amazon.com/lambda/)| Core Service | Serverless functions used for filtering, subscribing and updating information. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/lambda-service.html#lambda_region) |
[Amazon SNS](https://aws.amazon.com/sns/)| Core Service | Simple event information publisher, used for cross-account subscription. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sns.html#sns_region) |
[Amazon SQS](https://aws.amazon.com/sqs/)| Core Service | Simple event information queue, used for cross-account subscription. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/sqs-service.html#sqs_region) |
[Amazon Route53](https://aws.amazon.com/route53/)| Core Service | Private Hosted Zone is used for the DNS resolution automation. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/r53.html#r53_region) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)| Support Service | Used to store parameters that will later be shared. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ssm.html#ssm_region) |
[AWS Resource Access Manager (RAM)](https://aws.amazon.com/ram/)| Support Service | Used to store parameters that will later be shared. | [Documentation](https://docs.aws.amazon.com/general/latest/gr/ram.html#ram_region) |



## Cost 

You are responsible for the cost of the AWS services used while running this solution guidance. As of August 2024, the cost for running this guidance with the default settings in the EU-West(Ireland) `eu-west-1` Region is almost **none** since the only resource that doesn't fit in the Free Tier is the use of AWS Systems Manager Advanced Parameter storage.

We recommend creating a [budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html) through [AWS Cost Explorer](http://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. You can also estimate the cost for your architecture solution using [AWS Pricing Calculator](https://calculator.aws/#/). For full details, refer to the pricing webpage for each AWS service used in this Guidance or visit [Pricing by AWS Service](#pricing-by-aws-service).

### Estimated monthly cost breakdown - Central Account
This breakdown of the costs of the Central/Networking Account shows that the highest cost of the automation implementation is the Advanced Parameter Storage resource from AWS Systems Manager service. The costs are estimated in the Ireland `eu-west-1` region for one month.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| AWS Systems Manager  | 2 advanced parameters | \$ 0.10 |
| Amazon EventBridge  | < 1 million custom events | \$ 0.00 |
| AWS Lambda  | < 1 million requests & 400,000 GB-seconds of compute time | \$ 0.00 |
| Amazon SQS | < 1 million requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 0.10** |


### Estimated monthly cost breakdown - Spoke Account Onboarding

The following table provides a sample cost breakdown for deploying this guidance in 1,000 different spoke accounts which are likely to provide a VPC Lattice service in the future. 

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| Amazon EventBridge  | < 1 million custom events | \$ 0.00 |
| AWS Lambda  | < 1 million requests & 400,000 GB-seconds of compute time | \$ 0.00 |
| Amazon SNS  | < 1 million requests | \$ 0.00|
| Amazon SQS | < 1 million requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 0.00** |


### Estimated automated DNS configuration cost breakdown
Most services in this solution are in idle state unless they are triggered by an event or invocation. So, in order to estimate the cost of the automation when a new VPC Lattice service is created, let's suppose 500 new VPC Lattice services are created monthly.

| **AWS service**  | Dimensions | Cost, month \[USD\] |
|-----------|------------|------------|
| Amazon EventBridge  | 1500 custom events | \$ 0.00 |
| AWS Lambda  | 1500 requests & 36 GB-seconds of compute time | \$ 0.00 |
| Amazon SNS  | 500 requests | \$ 0.00|
| Amazon SQS | 500 requests| \$ 0.00 | 
| **TOTAL estimate** |  | **\$ 0.00** |

This example shows how cost-efficient the solution is with a high VPC Lattice service offer.

### Pricing by AWS Service
Bellow are the pricing references for each AWS Service used in this Guidance Solution.
| **AWS service**  |  Pricing  |
|-----------|---------------|
|[Amazon EventBridge](https://aws.amazon.com/eventbridge/)| [Documentation](https://aws.amazon.com/eventbridge/pricing/) |
[Amazon Lambda](https://aws.amazon.com/lambda/)|  [Documentation](https://aws.amazon.com/lambda/pricing/) |
[Amazon SNS](https://aws.amazon.com/sns/)|  [Documentation](https://aws.amazon.com/sns/pricing/) |
[Amazon SQS](https://aws.amazon.com/sqs/)| [Documentation](https://aws.amazon.com/sqs/pricing/) |
[Amazon Route53](https://aws.amazon.com/route53/)| [Documentation](https://aws.amazon.com/route53/pricing/) |
[AWS Systems Manager](https://aws.amazon.com/systems-manager/)|  [Documentation](https://aws.amazon.com/systems-manager/pricing/) |



<br/>

## Security

When you build systems on AWS infrastructure, security responsibilities are shared between you and AWS. This [shared responsibility model](https://aws.amazon.com/compliance/shared-responsibility-model/) reduces your operational burden because AWS operates, manages, and controls the components including the host operating system, the virtualization layer, and the physical security of the facilities in which the services operate. For more information about AWS security visit [AWS Cloud Security](http://aws.amazon.com/security/).

This guidance relies on a lot of reasonable default options and "principle of least privilege" access for all resources. Users that deploy it in production should go through all the deployed resources and ensure those defaults comply with their security requirements and policies, have adequate logging levels and alarms enabled and protect access to publicly exposed APIs. In SQS and SNS, the Resource Policies are defined such that only the specified account/organization/resource can access such resource. IAM Roles are defined for AWS Lambda to only access the corresponding resources such as EventBridge, SQS and SNS. AWS RAM securely shares resource parameter such as SQS queue ARN and Eventbridge custom event bus ARN. This limits the access to the VPC Lattice DNS resolution automation to the configuration resources and involved accounts only.

**NOTE**: Please note that by cloning and using 3rd party open-source code you assume responsibility for its patching/securing/managing in the context of this project.


### Quotas for AWS services in this Guidance

Make sure you have sufficient quota for each of the services implemented in this solution. For more information, see [AWS service quotas](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html).

To view the service quotas for all AWS services in the documentation without switching pages, view the information in the [Service endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/aws-general.pdf#aws-service-information) page in the PDF instead.


## Deployment 
The deployement of the solutions' resources is done with [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli). Make sure to have Terraform installed before deploying the solution. Bellow are the instructions to deploy the automation and also to deploy an example environemnt to test the automated DNS configuration.

1. **Automation deployment**:

    - After downloading the folders under /automation/, don't forget to update the path of the .py files in the main.tf files of both accounts. Search for "# UPDATE TO YOUR PATH" to help you find it. Regarding the **spoke_account** folder, if you already have your own spoke providers.tf and spoke variables.tf, you won't need to use these **BUT** don't forget to add the Networking Account ID in your spoke variables.tf.
    - Using the terminal, locate yourself in the /automation/networking_account folder, access your AWS Account and initialize terraform. If any changes have been made to the code, I recommend to run some validation checks before applying the changes in your AWS account.
        ```
        cd automation
        cd networking_account
        (access your AWS Networking Account)
        terraform init
        terraform validate
        terraform plan
        terraform apply
        ```
    - Now, open a new termianl and follow the same steps but from the service provider account (or spoke account). Locate yourself in the /automation/spoke_account folder, access you AWS Spoke Account and run terraform as done before.
        ```
        cd spoke_account
        (access your AWS Spoke Account)
        terraform init
        terraform validate
        terraform plan
        terraform apply
        ```
    - Now you have 2 open terminals, each of them for a separated AWS Account.
2. **Example architecture deployment**    
    - Using the Networking Account terminal, locate yourself in the /test/networking_account folder. Run some validation checks before applying the changes in your AWS account.
        ```
        cd test
        cd networking_account
        terraform validate
        terraform plan
        terraform apply
        ```
    - Change to the Spoke Account terminal, navigate to the /test/spoke_account folder and follow the same steps.
        ```
        cd spoke_account
        terraform validate
        terraform plan
        terraform apply
        ```
    - Check that the automation works correctly. To do so, open your R53 PHZ (Private Hosted Zone) in the Networking Account using the AWS Console and delete the record for service1. Then, from the Spoke Account, delete the VPC Lattice service1 and create it again with tag NewService = true (it's also possible to change the flag true-false-true for convenience). Check again the R53 PHZ and the service1 record should have been added automatically.






