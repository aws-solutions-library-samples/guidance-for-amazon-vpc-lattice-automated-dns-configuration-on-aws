# Guidance for VPC Lattice automated DNS configuration on AWS - Test environment (Terraform)

In this folder you can find code building the VPC Lattice and Amazon Route 53 resources needed to test this Guidance Solution. The code is divided in different subfolders, depending the AWS Account type to build the resources (we are supposing a multi-Account environment):

* [consumer_account](./consumer_account/)
* [networking_account](./networking_account/)
* [provider_account](./provider_account/)

## How to deploy this test code?

The test code assumes all the AWS Accounts are in the same AWS Organization - all the resources are shared using AWS RAM to the AWS Organization. If that's not the case, change the corresponding RAM resources in the *networking_account* folder to share with the corresponding AWS Accounts.

1. **Networking Account** Deploy the VPC Lattice service network and Route 53 resources (Profile & Private Hosted Zone). You will need to provide as variable the Private Hosted Zone name.

```
cd test/terraform/networking_account
terraform apply
```

2. **Networking Account** Deploy the Guidance Solution automation for the networking Account. You will need to provide as variable the Private Hosted Zone ID (created in Step 1).

```
cd deployment/terraform/networking_account
terraform apply
```

3. **Consumer Account** Deploy the consumer application and associate the VPC Lattice service network and Route 53 Profile to the VPC.

```
cd test/terraform/consumer_account
terraform apply
```

4. **Provider Account** Deploy the Guidance Solution automation for the Spoke Account.

```
cd deployment/terraform/spoke_account
terraform apply
```

5. **Provider Account** Once the Guidance Solution automation is built in the provider (spoke) Account, the automation is ready to update the DNS configuration once a VPC Lattice service has been created. Deploy the VPC Lattice service. You will need to provide as variables the AWS Region to deploy the resources, the networking Account ID, and the VPC Lattice service's custom domain name.

```
cd test/terraform/provider_account
terraform apply
```

## Clean-up

1. **Provider Account** Remove the VPC Lattice service, so the automation can notify the Networking Account and the DNS configuration is removed.

```
cd test/terraform/provider_account
terraform destroy
```

2. **Provider Account** Remove the Guidance Solution (*spoke Account*)

```
cd deployment/terraform/spoke_account
terraform destroy
```

3. **Consumer Account** Remove the consumer VPC and related resources.

```
cd test/terraform/consumer_account
terraform destroy
```

4. **Networking Account** Remove the VPC Lattice service network, Route 53 Profile and Private Hosted Zone, and Guidance Solution automation.

```
cd deployment/terraform/networking_account
terraform destroy

cd test/terraform/networking_account
terraform destroy
```