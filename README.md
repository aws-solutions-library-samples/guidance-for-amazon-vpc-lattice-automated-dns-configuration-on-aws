# Guidance for VPC Lattice automated DNS configuration on AWS

This guidance automates the creation of the DNS resolution (in multi-Account environments) needed when creating [Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/) services with custom domain names.

Amazon VPC Lattice is an application networking service that simplifies the connectivity, monitoring, and security of applications within [Amazon Web Services (AWS)](https://aws.amazon.com) Cloud. The main benefits of the service is the configuration and management simplification, allowing developers to focus on building features while Networking & Security administrators can provide guardrails in the services’ communication. Now configuration is not based on IPs, rather on DNS resolution. However, when defining custom domain names for the different services, some extra configuration steps are needed to allow proper DNS resolution in multi-Account environments. This Guidance Solution will automate [Amazon Route 53](https://aws.amazon.com/route53/) DNS configuration from Amazon VPC Lattice actions (create and remove services) in multi-Account environments.

### Solution reasoning
In a multi-account environment where Route53 Profiles and Private Hosted Zones are implemented, the DNS resolution of a new VPC Lattice service is updated or created as a new ALIAS record manually. However, when the amount of services scale, this task becomes challenging. This solution automates the update of the DNS configuration when a new VPC Lattice service is created. More information about the solution and its recommended architecture can be found in the implementation guidance.

## Architecture overview
Below is the architecture diagram workflow of the Amazon VPC Lattice automated DNS configuration in multi-account environment.

<div align="center">

![picture](/vpc_lattice_dns_images/reference_architecture_numbers.png)

<br/>
<i>Figure 1: Amazon VPC Lattice automated DNS configuration workflow. </i>
</div>
<br/>

1. Once the automation resources are deployed in the account, an [Amazon EventBridge](https://aws.amazon.com/eventbridge/) rule checks if a new [Amazon Simple Notification Service (SNS)](https://aws.amazon.com/sns/) topic has been created. If so, the event is sent to the Networking Account to a custom event bus, notifying about the topic creation. This process invokes the [AWS Lambda](https://aws.amazon.com/lambda/) function responisble for the cross-account subscription of the [Amazon Simple Queue Service (SQS)](https://aws.amazon.com/sqs/) queue in the Networking account to the SNS topic of the spoke account.<br/>
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


## Plan your deployment
This guidance is based on a multi-account environment, more especifically, an account providing a service and an account with the Route53 Profiles records. It can be extended to multiple provider or spoke accounts.

### Cost 

You are responsible for the cost of the AWS services used while running this solution guidance. As of August 2024, the cost for running this guidance with the default settings in the EU-West(Ireland) `eu-west-1` Region is almost none since the only resource that doesn't fit in the Free Tier is the use of AWS Systems Manager Advanced Parameter storage, which is \$0.10 monthly with 2 parameters.

We recommend creating a [budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html) through [AWS Cost Explorer](http://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. For full details, refer to the pricing webpage for each AWS service used in this Guidance.

### Estimated monthly cost breakdown - Spoke Account Onboarding

The following table provides a sample cost breakdown for deploying this guidance in 1,000 different spoke accounts which are likely to provide a VPC Lattice service in the future. The costs are estimated in the Ireland `eu-west-1` region for one month. 

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

Please refer to [FULL IMPLEMENTATION GUIDE]() for ...






## Table of Contents (required)

List the top-level sections of the README template, along with a hyperlink to the specific section.

### Required

1. [Overview](#overview-required)
    - [Cost](#cost)
2. [Prerequisites](#prerequisites-required)
    - [Operating System](#operating-system-required)
3. [Deployment Steps](#deployment-steps-required)
4. [Deployment Validation](#deployment-validation-required)
5. [Running the Guidance](#running-the-guidance-required)
6. [Next Steps](#next-steps-required)
7. [Cleanup](#cleanup-required)

***Optional***

8. [FAQ, known issues, additional considerations, and limitations](#faq-known-issues-additional-considerations-and-limitations-optional)
9. [Revisions](#revisions-optional)
10. [Notices](#notices-optional)
11. [Authors](#authors-optional)

## Overview (required)

1. Provide a brief overview explaining the what, why, or how of your Guidance. You can answer any one of the following to help you write this:

    - **Why did you build this Guidance?**
    - **What problem does this Guidance solve?**

2. Include the architecture diagram image, as well as the steps explaining the high-level overview and flow of the architecture. 
    - To add a screenshot, create an ‘assets/images’ folder in your repository and upload your screenshot to it. Then, using the relative file path, add it to your README. 

### Cost ( required )

This section is for a high-level cost estimate. Think of a likely straightforward scenario with reasonable assumptions based on the problem the Guidance is trying to solve. Provide an in-depth cost breakdown table in this section below ( you should use AWS Pricing Calculator to generate cost breakdown ).

Start this section with the following boilerplate text:

_You are responsible for the cost of the AWS services used while running this Guidance. As of <month> <year>, the cost for running this Guidance with the default settings in the <Default AWS Region (Most likely will be US East (N. Virginia)) > is approximately $<n.nn> per month for processing ( <nnnnn> records )._

Replace this amount with the approximate cost for running your Guidance in the default Region. This estimate should be per month and for processing/serving resonable number of requests/entities.

Suggest you keep this boilerplate text:
_We recommend creating a [Budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html) through [AWS Cost Explorer](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. For full details, refer to the pricing webpage for each AWS service used in this Guidance._

### Sample Cost Table ( required )

**Note : Once you have created a sample cost table using AWS Pricing Calculator, copy the cost breakdown to below table and upload a PDF of the cost estimation on BuilderSpace. Do not add the link to the pricing calculator in the ReadMe.**

The following table provides a sample cost breakdown for deploying this Guidance with the default parameters in the US East (N. Virginia) Region for one month.

| AWS service  | Dimensions | Cost [USD] |
| ----------- | ------------ | ------------ |
| Amazon API Gateway | 1,000,000 REST API calls per month  | $ 3.50month |
| Amazon Cognito | 1,000 active users per month without advanced security feature | $ 0.00 |

## Prerequisites (required)

### Operating System (required)

- Talk about the base Operating System (OS) and environment that can be used to run or deploy this Guidance, such as *Mac, Linux, or Windows*. Include all installable packages or modules required for the deployment. 
- By default, assume Amazon Linux 2/Amazon Linux 2023 AMI as the base environment. All packages that are not available by default in AMI must be listed out.  Include the specific version number of the package or module.

**Example:**
“These deployment instructions are optimized to best work on **<Amazon Linux 2 AMI>**.  Deployment in another OS may require additional steps.”

- Include install commands for packages, if applicable.


### Third-party tools (If applicable)

*List any installable third-party tools required for deployment.*


### AWS account requirements (If applicable)

*List out pre-requisites required on the AWS account if applicable, this includes enabling AWS regions, requiring ACM certificate.*

**Example:** “This deployment requires you have public ACM certificate available in your AWS account”

**Example resources:**
- ACM certificate 
- DNS record
- S3 bucket
- VPC
- IAM role with specific permissions
- Enabling a Region or service etc.


### aws cdk bootstrap (if sample code has aws-cdk)

<If using aws-cdk, include steps for account bootstrap for new cdk users.>

**Example blurb:** “This Guidance uses aws-cdk. If you are using aws-cdk for first time, please perform the below bootstrapping....”

### Service limits  (if applicable)

<Talk about any critical service limits that affect the regular functioning of the Guidance. If the Guidance requires service limit increase, include the service name, limit name and link to the service quotas page.>

### Supported Regions (if applicable)

<If the Guidance is built for specific AWS Regions, or if the services used in the Guidance do not support all Regions, please specify the Region this Guidance is best suited for>


## Deployment Steps (required)

Deployment steps must be numbered, comprehensive, and usable to customers at any level of AWS expertise. The steps must include the precise commands to run, and describe the action it performs.

* All steps must be numbered.
* If the step requires manual actions from the AWS console, include a screenshot if possible.
* The steps must start with the following command to clone the repo. ```git clone xxxxxxx```
* If applicable, provide instructions to create the Python virtual environment, and installing the packages using ```requirement.txt```.
* If applicable, provide instructions to capture the deployed resource ARN or ID using the CLI command (recommended), or console action.

 
**Example:**

1. Clone the repo using command ```git clone xxxxxxxxxx```
2. cd to the repo folder ```cd <repo-name>```
3. Install packages in requirements using command ```pip install requirement.txt```
4. Edit content of **file-name** and replace **s3-bucket** with the bucket name in your account.
5. Run this command to deploy the stack ```cdk deploy``` 
6. Capture the domain name created by running this CLI command ```aws apigateway ............```



## Deployment Validation  (required)

<Provide steps to validate a successful deployment, such as terminal output, verifying that the resource is created, status of the CloudFormation template, etc.>


**Examples:**

* Open CloudFormation console and verify the status of the template with the name starting with xxxxxx.
* If deployment is successful, you should see an active database instance with the name starting with <xxxxx> in        the RDS console.
*  Run the following CLI command to validate the deployment: ```aws cloudformation describe xxxxxxxxxxxxx```



## Running the Guidance (required)

<Provide instructions to run the Guidance with the sample data or input provided, and interpret the output received.> 

This section should include:

* Guidance inputs
* Commands to run
* Expected output (provide screenshot if possible)
* Output description



## Next Steps (required)

Provide suggestions and recommendations about how customers can modify the parameters and the components of the Guidance to further enhance it according to their requirements.


## Cleanup (required)

- Include detailed instructions, commands, and console actions to delete the deployed Guidance.
- If the Guidance requires manual deletion of resources, such as the content of an S3 bucket, please specify.



## FAQ, known issues, additional considerations, and limitations (optional)


**Known issues (optional)**

<If there are common known issues, or errors that can occur during the Guidance deployment, describe the issue and resolution steps here>


**Additional considerations (if applicable)**

<Include considerations the customer must know while using the Guidance, such as anti-patterns, or billing considerations.>

**Examples:**

- “This Guidance creates a public AWS bucket required for the use-case.”
- “This Guidance created an Amazon SageMaker notebook that is billed per hour irrespective of usage.”
- “This Guidance creates unauthenticated public API endpoints.”


Provide a link to the *GitHub issues page* for users to provide feedback.


**Example:** *“For any feedback, questions, or suggestions, please use the issues tab under this repo.”*

## Revisions (optional)

Document all notable changes to this project.

Consider formatting this section based on Keep a Changelog, and adhering to Semantic Versioning.

## Notices (optional)

Include a legal disclaimer

**Example:**
*Customers are responsible for making their own independent assessment of the information in this Guidance. This Guidance: (a) is for informational purposes only, (b) represents AWS current product offerings and practices, which are subject to change without notice, and (c) does not create any commitments or assurances from AWS and its affiliates, suppliers or licensors. AWS products or services are provided “as is” without warranties, representations, or conditions of any kind, whether express or implied. AWS responsibilities and liabilities to its customers are controlled by AWS agreements, and this Guidance is not part of, nor does it modify, any agreement between AWS and its customers.*


## Authors (optional)

Name of code contributors
