#!/bin/bash

# Variables
STACK_NAME="ChatbotApplicationStack"
TEMPLATE_FILE="cloudformation.yml"
REGION="us-east-1"  # Replace with your desired AWS region
LAYER_NAME="requests-layer"
PYTHON_VERSION="python3.9"
LAYER_DIR="layer"
LAYER_ZIP="requests-layer.zip"

# Create a directory for the layer
mkdir -p $LAYER_DIR/python/lib/$PYTHON_VERSION/site-packages

# Install the requests library into the layer directory
pip install requests -t $LAYER_DIR/python/lib/$PYTHON_VERSION/site-packages

# Package the layer
cd $LAYER_DIR
zip -r ../$LAYER_ZIP .
cd ..

# Publish the layer to AWS Lambda
LAYER_VERSION_ARN=$(aws lambda publish-layer-version \
  --layer-name $LAYER_NAME \
  --zip-file fileb://$LAYER_ZIP \
  --compatible-runtimes $PYTHON_VERSION \
  --region $REGION \
  --query 'LayerVersionArn' --output text)

echo "Published layer ARN: $LAYER_VERSION_ARN"

# Deploy the CloudFormation stack
aws cloudformation deploy \
  --template-file $TEMPLATE_FILE \
  --stack-name $STACK_NAME \
  --capabilities CAPABILITY_IAM \
  --region $REGION \
  --parameter-overrides RequestsLayerArn=$LAYER_VERSION_ARN

# Check if the deployment was successful
if [ $? -eq 0 ]; then
  echo "CloudFormation stack deployed successfully."
else
  echo "Failed to deploy CloudFormation stack."
  exit 1
fi

# Clean up
rm -rf $LAYER_DIR $LAYER_ZIP