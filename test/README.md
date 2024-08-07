# Guidance for VPC Lattice automated DNS configuration on AWS - Test environment

In this folder you can find code building the VPC Lattice and Amazon Route 53 resources needed to test this Guidance Solution. The code is divided in different subfolders, depending the different resources to build in a multi-Account environment:

* consumer_account
* networking_account
* provider_account

[ADD DIAGRAM]

## How to deploy this test code?

The test code assumes all the AWS Accounts are in the same AWS Organization - all the resources are shared using AWS RAM to the Organization. If that's not the case, change the [resources] in the *networking_account* folder to share the resources with the corresponding AWS Accounts.

1. (Networking Account) Deploy the VPC Lattice service network and Route 53 resources (Profile & Private Hosted Zone). In parallel, you can also deploy the Guidance Solution automation for the Networking Account.

```
cd test/networking_account
terraform apply

cd deployment/networking_account
terraform apply
```

2. (Consumer Account) Deploy the consumer application and associate the VPC Lattice service network and Route 53 Profile to the VPC.

```
cd test/consumer_account
terraform apply
```

3. (Provider Account) Deploy the Guidance Solution automation for the Spoke Account.

```
cd deployment/spoke_account
terraform apply
```

4. (Provider Account) Once the Guidance Solution automation is built in the provider (spoke) Account, the automation is ready to update the DNS configuration once a VPC Lattice service has been created. Deploy the VPC Lattice service.

```
cd test/provider_account
terraform apply
```

## What am I deploying?

### [consumer_accoount](./consumer_account/)

* Amazon VPC with an EC2 instance





### networking_account

Resources to be created in the Networking Account. Move to the [folder](./networking_account/) for more information about the resources.

### provider_account

Resources to be created in any Spoke Account you want to have this Guidance Solution running. Move to the [folder](./spoke_account/) for more information about the resources.