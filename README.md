# Guidance for VPC Lattice automated DNS configuration on AWS

This guidance automates the creation of DNS (Domain Name System) resolution configuration in [Amazon Route 53](https://aws.amazon.com/route53/) when creating new [Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/) services with custom domain names.

Amazon VPC Lattice is an application networking service that simplifies the connectivity, monitoring, and security between your services. Its main benefits are the configuration and management simplification, allowing developers to focus on building features while Networking & Security administrators can provide guardrails in the services’ communication. The service simplifies the onboarding experience for developers by removing the need to implement custom application code, or run additional proxies next to every workload, while maintaining the tools and controls network admins require to audit and secure their environment. VPC Lattice leverages DNS for service discovery, so each VPC Lattice service is easily identifiable through its service-managed or custom domain names. However, for custom domain names, extra manual configuration is needed to allow DNS resolution for the consumer workloads.

This Guidance Solution automate the configuration of DNS resolution anytime a new VPC Lattice service (with a custom domain name configured) is created. In this README, you will find only the deployment steps. For more information about the Guidance Solution, check the [Implementation Guide](TO ADD).

<div align="center">

![picture](/assets/reference_architecture.png)

</div>

## Deploy the Guidance 

**Time to deploy**: deployment times will vary depending the AWS Account type.
* *Networking Account*: 3 minutes
* *Spoke Account*: 2 minutes (per Account)

The following **pre-requisites** are needed before starting the deployment:

* For each AWS Account, make sure you have the appropriate permissions (depending the Account type) to deploy the resources.
* [Hashicorp Terraform](https://www.terraform.io/) installed.
    * In this code, we use the local backend configuration to store the state files. We recommend the use of another backend configuration that provides you more consistent storage and versioning, for example the use of [Amazon S3 and Amazon DynamoDB](https://developer.hashicorp.com/terraform/language/settings/backends/s3).
* As discussed in the [Considerations](#considerations) section, AWS Organizations needs to be configured and all the AWS Accounts should be onboarded within the same organization.

Below are the instructions to deploy the automation:

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

## Contributors

The following individuals contributed to this document

* Maialen Loinaz Antón, Networking Solutions Architect Intern
* Pablo Sánchez Carmona, Sr Networking Specialist Solutions Architect
