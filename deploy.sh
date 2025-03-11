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
STACK_NAME=${STACK_NAME:-"ChatbotApplicationStack"}
TEMPLATE_FILE=${TEMPLATE_FILE:-"cloudformation.yml"}
REGION=${REGION:-"us-east-1"}
STAGE=${STAGE:-"api"}
LAYER_NAME=${LAYER_NAME:-"requests-layer"}
PYTHON_VERSION=${PYTHON_VERSION:-"python3.12"}

# Lambda zipped code files
CHATBOT_ZIP=${CHATBOT_ZIP:-"chatbot_function.zip"}
EXPORT_LOGS_ZIP=${EXPORT_LOGS_ZIP:-"export_logs_function.zip"}

# Source Python files
CHATBOT_SOURCE=${CHATBOT_SOURCE:-"lambda_function.py"}
EXPORT_LOGS_SOURCE=${EXPORT_LOGS_SOURCE:-"export_logs.py"}

# S3 bucket for Lambda deployment
LAMBDA_CODE_BUCKET=${LAMBDA_CODE_BUCKET:-"chatbot-bucket-files"}

# Custom Domain variables (set in .env or here)
DOMAIN_NAME=${DOMAIN_NAME:-"chatapi.tatsuya.tech"}
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
CLOUDFLARE_ZONE_ID=${CLOUDFLARE_ZONE_ID}

# Helper function to build zip files
build_zip() {
  local src_file="$1"
  local zip_file="$2"
  if [ ! -f "$src_file" ]; then
    echo "❌ Source file '$src_file' missing. Cannot build zip."
    exit 1
  fi
  echo "🔨 Creating zip file '$zip_file' from '$src_file'..."
  zip -j "$zip_file" "$src_file" || {
    echo "❌ Failed to build zip file '$zip_file'."
    exit 1
  }
}

# Check Lambda zip files and build them automatically if missing
if [ ! -f "$CHATBOT_ZIP" ]; then
  build_zip "$CHATBOT_SOURCE" "$CHATBOT_ZIP"
fi

if [ ! -f "$EXPORT_LOGS_ZIP" ]; then
  build_zip "$EXPORT_LOGS_SOURCE" "$EXPORT_LOGS_ZIP"
fi

echo "✅ Zip files are ready."

# Layer configuration
LAYER_DIR="layer"
LAYER_ZIP="requests-layer.zip"
BUILT_LAYER=false

if [ -d "$LAYER_DIR" ] && [ -f "$LAYER_ZIP" ]; then
  echo "✅ Existing layer files found. Skipping layer creation."
else
  echo "🔨 Building new layer files..."
  rm -rf "$LAYER_DIR" "$LAYER_ZIP"  # Clean any partial files
  mkdir -p "$LAYER_DIR/python/lib/$PYTHON_VERSION/site-packages" || {
    echo "❌ Failed to create layer directory structure"
    exit 1
  }
  pip install requests -t "$LAYER_DIR/python/lib/$PYTHON_VERSION/site-packages" || {
    echo "❌ Failed to install Python dependencies"
    exit 1
  }
  (cd "$LAYER_DIR" && zip -qr "../$LAYER_ZIP" .) || {
    echo "❌ Failed to create layer zip file"
    exit 1
  }
  BUILT_LAYER=true
  echo "✅ Successfully created new layer files"
fi

echo "📦 Publishing Lambda layer..."
LAYER_VERSION_ARN=$(aws lambda publish-layer-version \
  --layer-name "$LAYER_NAME" \
  --zip-file "fileb://$LAYER_ZIP" \
  --compatible-runtimes "$PYTHON_VERSION" \
  --region "$REGION" \
  --query 'LayerVersionArn' \
  --output text) || {
  echo "❌ Failed to publish Lambda layer"
  exit 1
}
echo "✅ Layer published. ARN: $LAYER_VERSION_ARN"

echo "📤 Uploading Lambda code to S3..."
aws s3 cp "$CHATBOT_ZIP" "s3://$LAMBDA_CODE_BUCKET/$CHATBOT_ZIP" --region "$REGION" || {
  echo "❌ Failed to upload Chatbot Lambda code"
  exit 1
}
aws s3 cp "$EXPORT_LOGS_ZIP" "s3://$LAMBDA_CODE_BUCKET/$EXPORT_LOGS_ZIP" --region "$REGION" || {
  echo "❌ Failed to upload Export Logs Lambda code"
  exit 1
}

echo "🚀 Deploying CloudFormation Stack..."
aws cloudformation deploy \
  --template-file "$TEMPLATE_FILE" \
  --stack-name "$STACK_NAME" \
  --capabilities CAPABILITY_IAM \
  --region "$REGION" \
  --parameter-overrides \
    "LambdaCodeS3Bucket=$LAMBDA_CODE_BUCKET" \
    "ChatbotLambdaCodeS3Key=$CHATBOT_ZIP" \
    "ExportLogsLambdaCodeS3Key=$EXPORT_LOGS_ZIP" \
    "OpenWeatherApiKey=$OPEN_WEATHER_KEY" \
    "JokeApiUrl=$JOKE_API_URL" \
    "RequestsLayerArn=$LAYER_VERSION_ARN" || {
  echo "❌ CloudFormation deployment failed!"
  exit 1
}

echo "⏳ Waiting for stack to complete..."
aws cloudformation wait stack-create-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION" || {
  echo "❌ Stack creation failed!"
  aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --region "$REGION" --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
  exit 1
}

echo "🔍 Retrieving stack outputs..."
API_URL=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`ChatbotApiUrl`].OutputValue' \
  --output text)
if [ -z "$API_URL" ]; then
  echo "⚠️ Chatbot API URL not found in stack outputs"
  exit 1
else
  echo "✅ API Gateway URL: $API_URL"
fi

# Extract REST API ID from API_URL (assumes format: https://<restApiId>.execute-api.<region>.amazonaws.com/...)
DOMAIN_PART=$(echo "$API_URL" | sed 's_https://__' | cut -d'/' -f1)
REST_API_ID=$(echo "$DOMAIN_PART" | cut -d'.' -f1)
echo "Extracted REST API ID: $REST_API_ID"

# Update or add REST_API_ID in the .env file
if [ -f "$BASE_DIR/.env" ]; then
  if grep -q "^REST_API_ID=" "$BASE_DIR/.env"; then
    # For GNU sed use: sed -i "s/^REST_API_ID=.*/REST_API_ID=$REST_API_ID/" "$BASE_DIR/.env"
    sed -i.bak "s/^REST_API_ID=.*/REST_API_ID=$REST_API_ID/" "$BASE_DIR/.env"
  else
    echo "REST_API_ID=$REST_API_ID" >> "$BASE_DIR/.env"
  fi
  echo "✅ Updated REST_API_ID in .env to: $REST_API_ID"
else
  echo "❌ .env file not found at $BASE_DIR/.env!"
  exit 1
fi

# Ensure jq is installed for JSON parsing
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required but not installed. Please install jq and try again."
  exit 1
fi

if [ "$BUILT_LAYER" = true ]; then
  echo "🧹 Cleaning up temporary layer files..."
  rm -rf "$LAYER_DIR" "$LAYER_ZIP"
fi

echo "🎉 Deployment completed successfully!"