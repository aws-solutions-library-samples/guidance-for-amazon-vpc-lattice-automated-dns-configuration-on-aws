import boto3
import json
import logging
import os

vpc_lattice = boto3.client('vpc-lattice')
sns = boto3.client('sns')
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    # Access the event data
    service_identifier = event['resources'][0]
    tag_value = event['detail']['tags']['NewService']

    if tag_value == 'true':
        response = vpc_lattice.get_service(serviceIdentifier=service_identifier)
        account_id = response['arn'].split(':')[4]
        service_arn = response['arn']
        custom_domain_name = response['customDomainName']
        vpc_lattice_domain_name = response['dnsEntry']['domainName']
        vpc_lattice_hostedzone = response['dnsEntry']['hostedZoneId']
        # Log event details
        event_details = {
            "Service Identifier": service_identifier,
            "Account ID": account_id,
            "Service ARN": service_arn,
            "Custom Domain Name": custom_domain_name,
            "VPC Lattice Domain Name": vpc_lattice_domain_name,
            "VPC Lattice Hosted Zone ID": vpc_lattice_hostedzone,
            "NewService Tag Value": tag_value
        }
        for key, value in event_details.items():
            logger.info(f"{key}: {value}")

        sns.publish(
            TopicArn=os.environ['SNS_TOPIC'],
            Message=json.dumps(event_details),
            Subject='VPC Lattice Service Created'
        )

    return {
        'statusCode': 200,
        'body': 'VPC Lattice service information retrieved successfully'
    }







