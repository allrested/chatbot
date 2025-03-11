import json
import boto3
import requests
import os
from datetime import datetime
from typing import Any, Dict, Union, TYPE_CHECKING

# Type hints for IDE support without runtime errors
if TYPE_CHECKING:
    from boto3.resources.base import ServiceResource
    from mypy_boto3_dynamodb.service_resource import Table

# Initialize DynamoDB with proper typing
dynamodb: "ServiceResource" = boto3.resource('dynamodb')
table: "Table" = dynamodb.Table('ChatbotQueries')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    # Parse the incoming request
    body: Dict[str, Any] = json.loads(event['body'])
    query: str = body.get('query', '')
    response: Dict[str, Any] = {}

    # Determine the type of request and fetch data accordingly
    query_lower: str = query.lower()
    if 'weather' in query_lower:
        city_part: str = query.split('in')[-1].strip()
        city: str = ''.join(char for char in city_part if char.isalpha())
        response = get_weather(city)
    elif 'joke' in query_lower:
        response = get_joke()

    # Log the query and response in DynamoDB
    log_query(query, json.dumps(response))

    # Return the response
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }

def get_weather(city: str) -> Dict[str, Union[str, float]]:
    # Fetch weather data from OpenWeather API
    api_key: str = os.environ['OPENWEATHER_API_KEY']
    url: str = f"http://api.openweathermap.org/data/2.5/weather?q={city}&appid={api_key}"
    weather_data: Dict[str, Any] = requests.get(url).json()
    return {
        'city': city,
        'temperature': weather_data['main']['temp'],  # Temperature in Kelvin
        'description': weather_data['weather'][0]['description']
    }

def get_joke() -> Dict[str, str]:
    # Fetch a random joke from the Official Joke API
    url: str = os.environ['JOKE_API_URL']
    joke_data: Dict[str, str] = requests.get(url).json()
    return {
        'setup': joke_data['setup'],
        'punchline': joke_data['punchline']
    }

def log_query(query: str, response: str) -> None:
    # Log the query and response in DynamoDB with a timestamp
    table.put_item(
        Item={
            'QueryId': str(datetime.now()),
            'Query': query,
            'Response': response
        }
    )