import './workerTestUtils.js';
import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import axios from 'axios';
import WorkerDetail from '../../src/WorkerDetail.jsx';

vi.mock('axios');
vi.mock('react-leaflet', () => ({
  MapContainer: () => <div data-testid="map" />,
  TileLayer: () => <div />,
  Marker: () => <div />,
  useMapEvents: () => ({ flyTo: vi.fn(), invalidateSize: vi.fn() })
}));

vi.mock('../../src/components/M3TopNavbar.jsx', () => ({
  default: () => <nav data-testid="top-navbar" />
}));

describe('Frontend Worker TC-07: Worker Detail Profile View', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.scrollTo = vi.fn();
  });

  it('renders worker details successfully after API fetch', async () => {
    // Set query param id=15
    delete window.location;
    window.location = new URL('http://localhost:5173/worker?id=15');

    axios.get.mockImplementation((url) => {
      if (url.includes('/workers/15/reviews')) {
        return Promise.resolve({ data: [] });
      }
      if (url.includes('/workers/15')) {
        return Promise.resolve({
          data: {
            id: 15,
            name: 'Sunil Perera',
            primaryServiceArea: 'Moratuwa',
            pricingModel: 'Hourly',
            hourlyRate: 2800,
            description: 'Experienced master carpenter specialized in timber doors.',
            overallRating: 4.9,
            skills: [{ id: 1, serviceName: 'Carpentry', skills: ['Door Fitting'] }],
            isVerified: true
          }
        });
      }
      return Promise.reject(new Error('Unknown url'));
    });

    render(<WorkerDetail />);

    await waitFor(() => {
      expect(screen.getAllByText('Sunil Perera').length).toBeGreaterThan(0);
      expect(screen.getAllByText(/Moratuwa/i).length).toBeGreaterThan(0);
      expect(screen.getAllByText(/2,800/i).length).toBeGreaterThan(0);
    });
  });
});
