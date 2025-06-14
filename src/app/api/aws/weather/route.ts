import { NextRequest, NextResponse } from 'next/server';

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const location = searchParams.get('location');

  if (!location) {
    return NextResponse.json(
      { error: 'Location parameter is required' },
      { status: 400 }
    );
  }

  try {
    // Check if AWS credentials are configured
    const awsApiKey = process.env.AWS_API_KEY;
    const awsLambdaUrl = process.env.AWS_LAMBDA_URL;

    if (!awsApiKey || !awsLambdaUrl) {
      return NextResponse.json({
        error: 'AWS credentials not configured',
        aggregatedData: { locations: [] },
        cloudProviders: [],
        executionTimeMs: 0,
        timestamp: new Date().toISOString()
      }, { status: 503 });
    }

    // Call AWS Lambda function
    const response = await fetch(awsLambdaUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${awsApiKey}`
      },
      body: JSON.stringify({
        location,
        action: 'get-weather'
      }),
    });

    if (!response.ok) {
      throw new Error(`AWS Lambda responded with status: ${response.status}`);
    }

    const data = await response.json();
    
    return NextResponse.json({
      aggregatedData: data.aggregatedData || { locations: [] },
      cloudProviders: data.cloudProviders || ['aws'],
      executionTimeMs: data.executionTimeMs || 0,
      timestamp: data.timestamp || new Date().toISOString()
    });

  } catch (error) {
    console.error('AWS Weather API Error:', error);
    
    // Return error response that frontend can handle
    return NextResponse.json({
      error: 'AWS service unavailable',
      aggregatedData: { locations: [] },
      cloudProviders: [],
      executionTimeMs: 0,
      timestamp: new Date().toISOString()
    }, { status: 503 });
  }
} 