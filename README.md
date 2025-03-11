# Chatbot Application
This project is a simple chatbot that fetches weather data and random jokes using AWS services. It is deployed using AWS CloudFormation, API Gateway, Lambda, DynamoDB, and optionally S3 for storing documentation.

## Deployment Steps
Ensure AWS CLI is Configured:

Make sure the AWS CLI is installed and create S3 buckets to store CloudFormation stacks.

Run the following command to make the script executable:
   ```bash
chmod +x deploy.sh
   ```
Copy sample environnment:
   ```bash
cp .env.example .env
   ```

Edit Environment value and execute the script to deploy the stack:
   ```bash
./deploy.sh
   ```

This script will automatically upload the Lambda Layer, and deploy the CloudFormation stack.

Verify Deployment:
- After deployment, you can verify the resources in the AWS Management Console under CloudFormation, Lambda, API Gateway, and DynamoDB.

## Custom Domain
If you want to deploy to your custom domain, setting domain name on .env and make sure you have already add CAA domain below to DNS record.
   ```text
amazon.com
amazontrust.com
awstrust.com
amazonaws.com
   ```

Run the following command to make the script executable:
   ```bash
chmod +x custom_domain.sh
   ```

Run the script to configure custom domain:
   ```bash
./custom_domain.sh
   ```

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
curl --location 'https://chatapi.tatsuya.tech/chatbot' \
--header 'Content-Type: application/json' \
--data '{
  "query": "What's the weather in Bandung?"
}'
```
Ask about random jokes
```bash
curl --location 'https://chatapi.tatsuya.tech/chatbot' \
--header 'Content-Type: application/json' \
--data '{
  "query": "Tell me a joke."
}'
```
## Test Whatsapp Chat
Ask current weather of a city
<div align="center">
  <a href="https://wa.me/6285155010043?text=What%27s%20the%20weather%20in%20London%3F">
    <img src="https://img.shields.io/badge/Ask_Weather_via_WhatsApp-25D366?style=for-the-badge&logo=whatsapp&logoColor=white" alt="Weather WhatsApp">
  </a>
  <br>
  <img src="https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=https://wa.me/6285155010043?text=What%27s%20the%20weather%20in%20London%3F" width="120">
</div>
Ask about random jokes
<div align="center">
  <a href="https://wa.me/6285155010043?text=Tell%20me%20a%20joke.">
    <img src="https://img.shields.io/badge/Ask_Joke_via_WhatsApp-25D366?style=for-the-badge&logo=whatsapp&logoColor=white" alt="Joke WhatsApp">
  </a>
  <br>
  <img src="https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=https://wa.me/6285155010043?text=Tell%20me%20a%20joke." width="120">
</div>