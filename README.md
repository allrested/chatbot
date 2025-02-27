# Chatbot Application
This project is a simple chatbot that fetches weather data and random jokes using AWS services. It is deployed using AWS CloudFormation, API Gateway, Lambda, DynamoDB, and optionally S3 for storing documentation.

## Deployment Steps
Ensure AWS CLI is Configured:

Make sure the AWS CLI is installed and configured with the necessary permissions to create S3 buckets and deploy CloudFormation stacks.
Make the Script Executable:

Run the following command to make the script executable:
   ```bash
chmod +x deploy.sh
   ```
Execute the script to deploy the stack:
   ```bash
./deploy.sh
   ```
This script will automatically create a new S3 bucket with a unique name, upload the Lambda Layer, and deploy the CloudFormation stack.

Verify Deployment:
- After deployment, you can verify the resources in the AWS Management Console under CloudFormation, Lambda, API Gateway, and DynamoDB.
- You need to deploy stage on API Gateway to make the endpoint executable.

## Sample Requests/Responses
Weather Request
Request:
   ```json
{
   "query": "What's the weather in London?"
}
   ```
Response:
   ```json
{
   "city": "London",
   "temperature": 277.77,
   "description": "broken clouds"
}
   ```
Joke Request
Request:
   ```json
{
   "query": "Tell me a joke."
}
   ```
Response:
   ```json
{
   "setup": "How many lips does a flower have?",
   "punchline": "Tulips"
}
   ```

## High-Level Architecture
- API Gateway: Exposes a POST /chatbot endpoint that receives requests from clients.
- Lambda Function: Processes incoming requests, determines whether the request is for weather information or a joke, fetches data from external APIs, and logs interactions in DynamoDB.
- DynamoDB: Stores logs of queries and responses, including timestamps, for auditing and analysis.
- S3 (Optional): Used for storing documentation or static files related to the project.
This architecture leverages AWS services to provide a scalable and reliable solution for handling chatbot requests and integrating with external APIs.

## Test Case
Ask current weather of a city
```bash
curl --location 'https://ct4apx1sc5.execute-api.us-east-1.amazonaws.com/dev/chatbot' \
--header 'Content-Type: application/json' \
--data '{
  "query": "What's the weather in Bandung?"
}'
```
Ask about random jokes
```bash
curl --location 'https://ct4apx1sc5.execute-api.us-east-1.amazonaws.com/dev/chatbot' \
--header 'Content-Type: application/json' \
--data '{
  "query": "Tell me a joke."
}'
```
