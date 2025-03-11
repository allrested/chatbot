import boto3
import json
import os
from datetime import datetime, timedelta
from typing import Any, Dict, List

# Initialize resources with correct type annotations
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
table = dynamodb.Table('ChatbotQueries')
bucket_name: str = os.environ['LOGGING_BUCKET']

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Handle Lambda invocation, process logs and export to S3."""
    yesterday: datetime = datetime.now() - timedelta(days=1)
    date_str: str = yesterday.strftime('%Y-%m-%d')

    # Scan DynamoDB with proper pagination and filtering
    logs: List[Dict[str, Any]] = []
    scan_params = {
        'FilterExpression': 'begins_with(QueryId, :date_prefix)',
        'ExpressionAttributeValues': {':date_prefix': date_str}
    }

    while True:
        response = table.scan(**scan_params)
        logs.extend(response.get('Items', []))
        
        if 'LastEvaluatedKey' not in response:
            break
        scan_params['ExclusiveStartKey'] = response['LastEvaluatedKey']

    if logs:
        s3.put_object(
            Bucket=bucket_name,
            Key=f'logs/{date_str}.json',
            Body=json.dumps(logs)
        )

    return {
        'statusCode': 200,
        'body': f"Processed {len(logs)} log entries"
    }