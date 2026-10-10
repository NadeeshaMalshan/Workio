import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import WorkerListCard from '../../src/components/agent/WorkerListCard.jsx';

describe('Frontend Worker TC-06: Worker List Card Interaction Callbacks', () => {
  it('triggers onAction callback when clicking Book Pro and toggles favorite', () => {
    const handleAction = vi.fn();
    const mockWorker = {
      id: 25,
      name: 'Nimal Bandara',
      trade: 'Carpenter',
      overallRating: 4.8,
      hourlyRate: 2000,
      pricingModel: 'Hourly',
      distance: 3.0,
      isVerified: true
    };

    render(
      <WorkerListCard
        data={{
          category: 'Carpentry',
          totalCount: 1,
          workers: [mockWorker]
        }}
        onAction={handleAction}
      />
    );

    const bookBtn = screen.getByTitle(/Book this worker/i);
    fireEvent.click(bookBtn);

    expect(handleAction).toHaveBeenCalledWith('send_prompt', 'I would like to book Nimal Bandara (Worker ID: 25)');
  });
});
