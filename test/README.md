# Guidance for VPC Lattice automated DNS configuration on AWS - Test environment

In this folder you can find code building the VPC Lattice and Amazon Route 53 resources needed to test this Guidance Solution. 

* [AWS CloudFormation](./cloudformation/)
* [Terraform](./terraform/)

## What am I deploying?

### consumer_account

* Amazon VPC with an Amazon EC2 instance - to connect to the VPC Lattice service created by the *provider Account*. The VPC associates with the following resources created by the *networking Account*:
    * VPC Lattice service network.
    * Amazon Route 53 Profile.
* EC2 Instance Connect endpoint - to connect to the EC2 instance and test connectivity.

### networking_account

* Amazon VPC Lattice service network.
* Amazon Route 53 Profile, and Private Hosted Zone (associated to the Profile).
* AWS Systems Manager parameters - with the VPC Lattice service network ARN and Route 53 Profile ID as values.
* AWS RAM resource share sharing the VPC Lattice service network, Route 53 Profile, and Systems Manager parameter with the Organization.

### provider_account

* Amazon VPC Lattice service. Single listener (HTTP) with a default rule pointing to a Lambda target group.
* AWS Lambda function (*provider service*) and corresponding IAM role.
