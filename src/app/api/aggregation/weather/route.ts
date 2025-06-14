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
    // Check if aggregation Lambda is configured
    const aggregationUrl = process.env.AGGREGATION_LAMBDA_URL;
    const apiKey = process.env.AGGREGATION_API_KEY;

    if (!aggregationUrl) {
      return NextResponse.json({
        error: 'Aggregation service not configured',
        aggregatedData: { locations: [] },
        cloudProviders: [],
        executionTimeMs: 0,
        timestamp: new Date().toISOString()
      }, { status: 503 });
    }

    // Call aggregation Lambda function
    const response = await fetch(aggregationUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(apiKey && { 'Authorization': `Bearer ${apiKey}` })
      },
      body: JSON.stringify({
        location,
        action: 'aggregate-weather'
      }),
    });

    if (!response.ok) {
      throw new Error(`Aggregation service responded with status: ${response.status}`);
    }

    const data = await response.json();
    
    return NextResponse.json({
      aggregatedData: data.aggregatedData || { locations: [] },
      cloudProviders: data.cloudProviders || [],
      executionTimeMs: data.executionTimeMs || 0,
      timestamp: data.timestamp || new Date().toISOString()
    });

  } catch (error) {
    console.error('Aggregation Weather API Error:', error);
    
    // Return mock data when all services are unavailable
    const mockData = {
      aggregatedData: {
        locations: [
          {
            locationId: location.toLowerCase().replace(/[^a-z0-9]/g, '-'),
            locationName: location,
            lat: 40.7128,
            lon: -74.0060,
            agreement: 0,
            consensus: {
              temperature: 20,
              humidity: 65,
              description: 'Service Unavailable',
              windSpeed: 0,
              pressure: 1013,
              precipitation: 0,
              sunrise: '6:18 AM',
              sunset: '7:27 PM'
            },
            providers: []
          }
        ]
      },
      cloudProviders: [],
      executionTimeMs: 0,
      timestamp: new Date().toISOString(),
      error: 'All cloud providers are currently unavailable'
    };
    
    return NextResponse.json(mockData, { status: 503 });
  }
} 