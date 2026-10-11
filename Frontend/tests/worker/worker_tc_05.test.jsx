import React from 'react';
import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import WorkerListCard from '../../src/components/agent/WorkerListCard.jsx';

describe('Frontend Worker TC-05: Worker List Card Recommendations', () => {
  it('renders list of matched workers with rates, rating, and distance badges', () => {
    const mockWorkers = [
      {
        id: 10,
        name: 'Kamal Perera',
        trade: 'Plumber',
        overallRating: 4.9,
        hourlyRate: 2500,
        pricingModel: 'Hourly',
        distance: 2.4,
        isVerified: true,
        primaryServiceArea: 'Colombo 03'
      },
      {
        id: 11,
        name: 'Sunil Shantha',
        trade: 'Electrician',
        overallRating: 4.7,
        hourlyRate: 2200,
        pricingModel: 'Hourly',
        distance: 4.1,
        isVerified: true,
        primaryServiceArea: 'Dehiwala'
      }
    ];

    render(
      <WorkerListCard
        data={{
          category: 'Plumbing',
          totalCount: 2,
          workers: mockWorkers
        }}
      />
    );

    expect(screen.getByText('Kamal Perera')).toBeTruthy();
    expect(screen.getByText('Sunil Shantha')).toBeTruthy();
    expect(screen.getByText('Colombo 03')).toBeTruthy();
    expect(screen.getByText('Dehiwala')).toBeTruthy();
    expect(screen.getByText(/2,500/)).toBeTruthy();
  });
});
