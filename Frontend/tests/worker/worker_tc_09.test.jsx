import './workerTestUtils.js';
import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import axios from 'axios';
import WorkerPerformance from '../../src/pages/worker/WorkerPerformance.jsx';

vi.mock('axios');
vi.mock('../../src/pages/worker/WorkerLayout.jsx', () => ({
  default: ({ children }) => <div data-testid="worker-layout">{children}</div>
}));

describe('Frontend Worker TC-09: Worker Performance Metrics Calculation & Render', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.setItem('workerEmail', 'kamal@workio.lk');
    localStorage.setItem('token', 'fake-jwt-token');
  });

  it('renders overall rating and calculated performance rates', async () => {
    axios.get.mockImplementation((url) => {
      if (url.includes('/workers/me')) {
        return Promise.resolve({
          data: {
            worker: {
              id: 1,
              name: 'Kamal Perera',
              email: 'kamal@workio.lk',
              overallRating: 4.8
            }
          }
        });
      }
      if (url.includes('/workers/1/performance')) {
        return Promise.resolve({
          data: {
            id: 1,
            name: 'Kamal Perera',
            overallRating: 4.8,
            qualityRating: 5.0,
            punctualityRating: 4.8,
            communicationRating: 4.9,
            completedJobs: 25,
            cancelledJobs: 1,
            acceptanceRate: '95.5%',
            completionRate: '96.2%',
            cancellationRate: '3.8%'
          }
        });
      }
      if (url.includes('/bookings/worker')) {
        return Promise.resolve({ data: [] });
      }
      return Promise.reject(new Error('Unknown url'));
    });

    render(<WorkerPerformance />);

    await waitFor(() => {
      expect(screen.getAllByText(/4\.8/).length).toBeGreaterThan(0);
      expect(screen.getByText('95.5%')).toBeTruthy();
      expect(screen.getByText('96.2%')).toBeTruthy();
      expect(screen.getByText('3.8%')).toBeTruthy();
    });
  });
});
