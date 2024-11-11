# Guidance for VPC Lattice automated DNS configuration on AWS - Test environment (CloudFormation)

In this folder you can find code building the VPC Lattice and Amazon Route 53 resources needed to test this Guidance Solution. The code is divided in different YAML files, depending the AWS Account type to build the resources (we are supposing a multi-Account environment):

* [consumer_account](consumer_account.yaml)
* [networking_account](networking_account.yaml)
* [provider_account](provider_account.yaml)

## How to deploy this test code?

The test code assumes all the AWS Accounts are in the same AWS Organization - all the resources are shared using AWS RAM to the AWS Organization. If that's not the case, change the corresponding RAM resources in the *networking_account* folder to share with the corresponding AWS Accounts.

1. **Networking Account** Deploy the VPC Lattice service network and Route 53 resources (Profile & Private Hosted Zone). You will need to provide as variable the Private Hosted Zone name.

```
aws cloudformation deploy --stack-name TestNetworkingAccount --template-file ./test/cloudformation/networking_account.yaml --capabilities CAPABILITY_IAM --parameter-overrides HostedZoneName={NAME} --region {REGION}
```

2. **Networking Account** Deploy the Guidance Solution automation for the networking Account. You will need to provide as variable the Private Hosted Zone ID (created in Step 1).

```
aws cloudformation deploy --stack-name DNSAutomationNetworking --template-file ./deployment/cloudformation/networking_account.yaml --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --parameter-overrides PrivateHostedZone={ZONE_ID} --region {REGION}
```

3. **Consumer Account** Deploy the consumer application and associate the VPC Lattice service network and Route 53 Profile to the VPC.

```
aws cloudformation deploy --stack-name TestConsumerAccount --template-file ./test/cloudformation/consumer_account.yaml --capabilities CAPABILITY_IAM --region {REGION}
```

4. **Provider Account** Deploy the Guidance Solution automation for the Spoke Account.

```
aws cloudformation deploy --stack-name DNSAutomationSpoke --template-file ./deployment/cloudformation/spoke_account.yaml --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --region {REGION}
```

5. **Provider Account** Once the Guidance Solution automation is built in the provider (spoke) Account, the automation is ready to update the DNS configuration once a VPC Lattice service has been created. Deploy the VPC Lattice service. You will need to provide as variables the AWS Region to deploy the resources, the networking Account ID, and the VPC Lattice service's custom domain name.

```
aws cloudformation deploy --stack-name TestProviderAccount --template-file ./test/cloudformation/provider_account.yaml --capabilities CAPABILITY_IAM --parameter-overrides VPCLatticeServiceCustomDomainName={VALUE} --region {REGION}
```

## Clean-up

1. **Provider Account** Remove both the VPC Lattice service, so the automation can notify the Networking Account and the DNS configuration is removed.

```
aws cloudformation delete-stack --stack-name TestProviderAccount --region {REGION}
```

2. **Provider Account** Remove the Guidance Solution (*spoke Account*)

```
aws cloudformation delete-stack --stack-name DNSAutomationSpoke --region {REGION}
```

3. **Consumer Account** Remove the consumer VPC and related resources.

```
aws cloudformation delete-stack --stack-name TestConsumerAccount --region {REGION}
```

4. **Networking Account** Remove the VPC Lattice service network, Route 53 Profile and Private Hosted Zone, and Guidance Solution automation.

```
aws cloudformation delete-stack --stack-name TestNetworkingAccount --region {REGION}
aws cloudformation delete-stack --stack-name DNSAutomationNetworking --region {REGION}
```