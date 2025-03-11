#!/bin/sh

# Get the current folder's absolute path
BASE_DIR=$(pwd)

# Load environment variables from .env file if available
if [ -f "$BASE_DIR/.env" ]; then
  . "$BASE_DIR/.env"
else
  echo "❌ .env file not found in $BASE_DIR!"
  exit 1
fi

# Set default values if not provided in .env
REGION=${REGION:-"us-east-1"}
STAGE=${STAGE:-"api"}
DOMAIN_NAME=${DOMAIN_NAME:-"chatapi.tatsuya.tech"}
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
CLOUDFLARE_ZONE_ID=${CLOUDFLARE_ZONE_ID}

#######################################
# Part 1: Request ACM Certificate and Update Cloudflare DNS for DNS Validation
#######################################

echo "🔨 Requesting ACM certificate for $DOMAIN_NAME..."
CERTIFICATE_ARN=$(aws acm request-certificate \
  --domain-name "$DOMAIN_NAME" \
  --validation-method DNS \
  --region "$REGION" \
  --output text)

if [ -z "$CERTIFICATE_ARN" ]; then
  echo "❌ Failed to request certificate."
  exit 1
fi

echo "✅ Certificate requested. ARN: $CERTIFICATE_ARN"
echo "⏳ Waiting 10 seconds for ACM to generate DNS validation record details..."
sleep 10

CERT_DETAILS=$(aws acm describe-certificate --certificate-arn "$CERTIFICATE_ARN" --region "$REGION" --output json)
if [ -z "$CERT_DETAILS" ]; then
  echo "❌ Failed to retrieve certificate details."
  exit 1
fi

RESOURCE_RECORD_NAME=$(echo "$CERT_DETAILS" | jq -r '.Certificate.DomainValidationOptions[0].ResourceRecord.Name' | sed 's/\.$//')
RESOURCE_RECORD_TYPE=$(echo "$CERT_DETAILS" | jq -r '.Certificate.DomainValidationOptions[0].ResourceRecord.Type')
RESOURCE_RECORD_VALUE=$(echo "$CERT_DETAILS" | jq -r '.Certificate.DomainValidationOptions[0].ResourceRecord.Value')

if [ -z "$RESOURCE_RECORD_NAME" ] || [ -z "$RESOURCE_RECORD_VALUE" ]; then
  echo "❌ Failed to extract DNS validation record details. Check certificate details in AWS ACM."
  exit 1
fi

echo "✅ DNS validation record details:"
echo "   Name: $RESOURCE_RECORD_NAME"
echo "   Type: $RESOURCE_RECORD_TYPE"
echo "   Value: $RESOURCE_RECORD_VALUE"

echo "🔨 Checking Cloudflare DNS for existing DNS validation record..."
CF_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=$RESOURCE_RECORD_TYPE&name=$RESOURCE_RECORD_NAME" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json")
EXISTING_RECORD_ID=$(echo "$CF_RESPONSE" | jq -r '.result[0].id // empty')

# Prepare the DNS payload using jq
DNS_PAYLOAD=$(jq -n --arg type "$RESOURCE_RECORD_TYPE" \
                     --arg name "$RESOURCE_RECORD_NAME" \
                     --arg content "$RESOURCE_RECORD_VALUE" \
                     --argjson ttl 300 \
                     --argjson proxied false \
                     '{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}')

if [ -n "$EXISTING_RECORD_ID" ]; then
  echo "🔄 DNS validation record already exists (ID: $EXISTING_RECORD_ID). Skipping DNS update for validation."
else
  echo "🔨 Creating new DNS record in Cloudflare for DNS validation..."
  UPDATE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$DNS_PAYLOAD")
  SUCCESS=$(echo "$UPDATE_RESPONSE" | jq -r '.success')
  if [ "$SUCCESS" != "true" ]; then
    echo "❌ Failed to update Cloudflare DNS record for DNS validation."
    echo "Response: $UPDATE_RESPONSE"
    exit 1
  fi
fi

echo "✅ Cloudflare DNS validation record is in place."
echo "🎉 Certificate validation is in progress. It may take several minutes..."

#######################################
# Part 2: Wait for Certificate to be Issued
#######################################

echo "⏳ Waiting for certificate to be issued..."
TIMEOUT=600  # maximum wait time in seconds
INTERVAL=15  # poll interval in seconds
ELAPSED=0
while true; do
  CERT_STATUS=$(aws acm describe-certificate --certificate-arn "$CERTIFICATE_ARN" --region "$REGION" --query "Certificate.Status" --output text)
  echo "Certificate status: $CERT_STATUS"
  if [ "$CERT_STATUS" = "ISSUED" ]; then
    echo "✅ Certificate has been issued!"
    break
  fi
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "❌ Certificate validation timed out after $TIMEOUT seconds."
    exit 1
  fi
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

#######################################
# Part 3: Create API Gateway Custom Domain and Update Cloudflare DNS for Custom Domain Mapping
#######################################

echo "🔨 Creating API Gateway custom domain for $DOMAIN_NAME using the issued certificate..."
APIGW_DOMAIN_OUTPUT=$(aws apigateway create-domain-name \
  --domain-name "$DOMAIN_NAME" \
  --regional-certificate-arn "$CERTIFICATE_ARN" \
  --endpoint-configuration types=REGIONAL \
  --region "$REGION" \
  --output json) || {
    echo "❌ Failed to create API Gateway custom domain."
    exit 1
  }

APIGW_TARGET_DOMAIN=$(echo "$APIGW_DOMAIN_OUTPUT" | jq -r '.regionalDomainName')
if [ -z "$APIGW_TARGET_DOMAIN" ] || [ "$APIGW_TARGET_DOMAIN" = "null" ]; then
  echo "❌ Failed to extract API Gateway target domain."
  exit 1
fi
echo "✅ API Gateway custom domain created. Target domain: $APIGW_TARGET_DOMAIN"

# Create Base Path Mapping for the custom domain
echo "🔨 Creating base path mapping for API Gateway custom domain..."
aws apigateway create-base-path-mapping \
  --domain-name "$DOMAIN_NAME" \
  --rest-api-id "$REST_API_ID" \
  --stage "$STAGE" \
  --base-path '(none)' \
  --region "$REGION" || {
    echo "❌ Failed to create base path mapping."
    exit 1
}
echo "✅ Base path mapping created."

echo "🔨 Checking Cloudflare DNS for existing custom domain record..."
CF_CUSTOM_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=CNAME&name=$DOMAIN_NAME" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json")
EXISTING_CUSTOM_RECORD_ID=$(echo "$CF_CUSTOM_RESPONSE" | jq -r '.result[0].id // empty')

DNS_CUSTOM_PAYLOAD=$(jq -n --arg type "CNAME" \
                     --arg name "$DOMAIN_NAME" \
                     --arg content "$APIGW_TARGET_DOMAIN" \
                     --argjson ttl 120 \
                     --argjson proxied false \
                     '{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}')

if [ -n "$EXISTING_CUSTOM_RECORD_ID" ]; then
  echo "🔄 DNS custom record already exists (ID: $EXISTING_CUSTOM_RECORD_ID). Skipping update."
else
  echo "🔨 Creating new Cloudflare DNS record for custom domain mapping..."
  CUSTOM_UPDATE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$DNS_CUSTOM_PAYLOAD")
  CUSTOM_SUCCESS=$(echo "$CUSTOM_UPDATE_RESPONSE" | jq -r '.success')
  if [ "$CUSTOM_SUCCESS" != "true" ]; then
    echo "❌ Failed to update Cloudflare DNS record for custom domain mapping."
    echo "Response: $CUSTOM_UPDATE_RESPONSE"
    exit 1
  fi
fi

echo "✅ Cloudflare DNS custom record is in place."
echo "🎉 Your custom domain (https://$DOMAIN_NAME) is now registered with AWS (using ACM and API Gateway) and mapped in Cloudflare."
